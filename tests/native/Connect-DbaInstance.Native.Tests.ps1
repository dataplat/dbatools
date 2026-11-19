#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
# NativeChecklist: whatif-confirm N/A -- the command does not support ShouldProcess; it opens connections and changes no server state.
param(
    $ModuleName = "dbatools",
    $CommandName = "Connect-DbaInstance",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe "Native Connect-DbaInstance" -Tag IntegrationTests {
    BeforeAll {
        # Nothing listens on port 1, so the connection is refused at once.
        $badInstance = "TCP:127.0.0.1,1"

        # The module registers its tab completion gather scripts from its maintenance runspace a little after import
        # (teppInsertTask). Several contexts save and restore that list; wait for the registration first, so none of
        # them can drop it. The task is registered at import when the maintenance system loads; without it there is
        # nothing to wait for.
        $teppTasks = [Dataplat.Dbatools.Maintenance.MaintenanceHost]::Tasks
        $teppDeadline = (Get-Date).AddSeconds(180)
        $nativeTeppRegistered = $false
        while ($teppTasks.ContainsKey("teppinserttask") -and (Get-Date) -lt $teppDeadline) {
            $teppInsertTask = $teppTasks["teppinserttask"]
            if ($teppInsertTask.LastExecution -gt $teppInsertTask.Registered) {
                $nativeTeppRegistered = $true
                break
            }
            Start-Sleep -Milliseconds 500
        }
    }

    AfterAll {
        $null = Get-DbaConnectedInstance | Disconnect-DbaInstance
        Clear-DbaConnectionPool
    }

    Context "Parameters" {
        It "has the pinned parameters plus EnableException" {
            # The pinned list (tests/Connect-DbaInstance.Tests.ps1:26) has no EnableException; the native build keeps it
            # because other commands' tests pass it (notes: enableexception-20261111.md).
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "ApplicationIntent",
                "AzureUnsupported",
                "BatchSeparator",
                "ClientName",
                "ConnectRetryCount",
                "ConnectRetryInterval",
                "ConnectTimeout",
                "EncryptConnection",
                "FailoverPartner",
                "LockTimeout",
                "MaxPoolSize",
                "MinPoolSize",
                "MinimumVersion",
                "MultipleActiveResultSets",
                "MultiSubnetFailover",
                "NetworkProtocol",
                "NonPooledConnection",
                "PacketSize",
                "PooledConnectionLifetime",
                "SqlExecutionModes",
                "StatementTimeout",
                "TrustServerCertificate",
                "AllowTrustServerCertificate",
                "WorkstationId",
                "AlwaysEncrypted",
                "AppendConnectionString",
                "SqlConnectionOnly",
                "AzureDomain",
                "Tenant",
                "AccessToken",
                "AuthenticationType",
                "DedicatedAdminConnection",
                "IsNewConnectionReference",
                "DisableException",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Several instances" {
        It "connects to every piped instance in order" -Tag "NativeChecklist:pipeline-multiple" {
            $servers = @($TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2 | Connect-DbaInstance)
            $servers.Count | Should -Be 2
            $servers[0].Name | Should -Be $TestConfig.InstanceMulti1
            $servers[1].Name | Should -Be $TestConfig.InstanceMulti2
            foreach ($server in $servers) {
                $server.ConnectionContext.ExecuteScalar("SELECT 1") | Should -Be 1
            }
        }

        It "warns for a failed middle instance and connects the others with -DisableException" -Tag "NativeChecklist:pipeline-multiple", "NativeChecklist:multi-instance-failure" {
            $connectWarnings = @()
            $splatContinue = @{
                DisableException = $true
                WarningVariable  = "connectWarnings"
                WarningAction    = "SilentlyContinue"
            }
            $servers = @($TestConfig.InstanceMulti1, $badInstance, $TestConfig.InstanceMulti2 | Connect-DbaInstance @splatContinue)
            $servers.Count | Should -Be 2
            $servers[0].Name | Should -Be $TestConfig.InstanceMulti1
            $servers[1].Name | Should -Be $TestConfig.InstanceMulti2
            @($connectWarnings | Where-Object { "$PSItem" -like "*Failure*" }).Count | Should -Be 1
        }

        It "streams the instance before a failure, then throws there by default" -Tag "NativeChecklist:multi-instance-failure", "NativeChecklist:enable-exception" {
            # Connect-DbaInstance throws by default; -DisableException is what makes it warn.
            $streamed = New-Object System.Collections.Generic.List[object]
            $caught = $null
            try {
                $TestConfig.InstanceMulti1, $badInstance, $TestConfig.InstanceMulti2 |
                    Connect-DbaInstance |
                    ForEach-Object { $streamed.Add($PSItem) }
            } catch {
                $caught = $PSItem
            }
            $caught | Should -Not -BeNullOrEmpty
            $streamed.Count | Should -Be 1
            $streamed[0].Name | Should -Be $TestConfig.InstanceMulti1
        }

        It "reports an instance whose connection settings cannot be built as failed and goes on to the next" {
            # SqlClient cannot parse this AppendConnectionString once -ConnectRetryCount makes it read the settings back.
            # The pinned loop wrote the parser's error and connected without the appended settings; each instance now
            # fails with the usual Failure instead, and the next instance is still tried.
            $settingsWarnings = @()
            $splatBadSettings = @{
                SqlInstance            = @($TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2)
                AppendConnectionString = "Packet Size 4096"
                ConnectRetryCount      = 1
                DisableException       = $true
                WarningVariable        = "settingsWarnings"
                WarningAction          = "SilentlyContinue"
            }
            $result = Connect-DbaInstance @splatBadSettings
            $result | Should -BeNullOrEmpty
            @($settingsWarnings | Where-Object { "$PSItem" -like "*Failure*" }).Count | Should -Be 2

            $splatBadSettings.Remove("DisableException")
            { Connect-DbaInstance @splatBadSettings } | Should -Throw
        }
    }

    Context "New connection reference" {
        It "tells whether -SqlConnectionOnly opened a new connection" {
            $isNewFromString = $null
            $connection = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -SqlConnectionOnly -IsNewConnectionReference ([ref]$isNewFromString)
            $connection | Should -BeOfType Microsoft.Data.SqlClient.SqlConnection
            $isNewFromString | Should -BeTrue

            $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
            $isNewFromServer = $null
            $sameConnection = Connect-DbaInstance -SqlInstance $server -SqlConnectionOnly -IsNewConnectionReference ([ref]$isNewFromServer)
            $sameConnection | Should -BeOfType Microsoft.Data.SqlClient.SqlConnection
            $isNewFromServer | Should -BeFalse
        }
    }

    Context "Failover partner" {
        # Quality gate 1: the pin appends "FailoverPartner=<name>;" to AdditionalParameters (pinned 1138), a keyword
        # Microsoft.Data.SqlClient does not know, with the name unescaped; SqlClient also refuses a Failover Partner
        # without an Initial Catalog when the connection is built. The port writes "Failover Partner" through the
        # builder and adds Initial Catalog=master when no catalog is given, as the pin does for a connection string.
        # The partner does not exist; SqlClient goes to it only when the instance cannot be reached.
        It "connects to the instance with the Failover Partner keyword and Initial Catalog=master" {
            $connection = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti1 -FailoverPartner "dbatoolsci-partner" -SqlConnectionOnly
            $connection | Should -BeOfType Microsoft.Data.SqlClient.SqlConnection
            $builder = New-Object -TypeName Microsoft.Data.SqlClient.SqlConnectionStringBuilder -ArgumentList $connection.ConnectionString
            $builder["Failover Partner"] | Should -Be "dbatoolsci-partner"
            $builder["Initial Catalog"] | Should -Be "master"

            $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti1 -FailoverPartner "dbatoolsci-partner"
            $server.ConnectionContext.ExecuteScalar("SELECT DB_NAME()") | Should -Be "master"
        }

        It "keeps the -Database catalog" {
            $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti1 -FailoverPartner "dbatoolsci-partner" -Database tempdb
            $builder = New-Object -TypeName Microsoft.Data.SqlClient.SqlConnectionStringBuilder -ArgumentList $server.ConnectionContext.ConnectionString
            $builder["Failover Partner"] | Should -Be "dbatoolsci-partner"
            $builder["Initial Catalog"] | Should -Be "tempdb"
            $server.ConnectionContext.ExecuteScalar("SELECT DB_NAME()") | Should -Be "tempdb"
        }

        It "adds Initial Catalog=master when -AppendConnectionString names an empty catalog" {
            # Review round 1, 2026-11-18: an empty "Database=" is no catalog, and SqlClient still refuses the partner
            # without one, so the fallback catalog goes in as it does with nothing appended.
            $splatEmptyCatalog = @{
                SqlInstance            = $TestConfig.InstanceMulti1
                FailoverPartner        = "dbatoolsci-partner"
                AppendConnectionString = "Database="
            }
            $server = Connect-DbaInstance @splatEmptyCatalog
            $builder = New-Object -TypeName Microsoft.Data.SqlClient.SqlConnectionStringBuilder -ArgumentList $server.ConnectionContext.ConnectionString
            $builder["Failover Partner"] | Should -Be "dbatoolsci-partner"
            $builder["Initial Catalog"] | Should -Be "master"
            $server.ConnectionContext.ExecuteScalar("SELECT DB_NAME()") | Should -Be "master"
        }

        It "keeps connection string text in the partner name inside that name" {
            $partner = "dbatoolsci-partner;Application Name=dbatoolsci-injected"
            $connection = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti1 -FailoverPartner $partner -SqlConnectionOnly
            $builder = New-Object -TypeName Microsoft.Data.SqlClient.SqlConnectionStringBuilder -ArgumentList $connection.ConnectionString
            $builder["Failover Partner"] | Should -Be $partner
            $builder["Application Name"] | Should -Not -Be "dbatoolsci-injected"
        }

        # The real-call form of pinned 161, byte-identical to the It in tests/native/replacements (the operator,
        # 2026-11-13: "ALWAYS REWRITE FAILING MOOCKS AS REAL CALL TESTS."). The pinned module fails it for its keyword
        # defect alone ("Keyword not supported: 'failoverpartner'.", replacement proofs e588ae6c and 762ff0ed). By IPv4
        # address an encrypted connection fails certificate validation on every lab instance, so the trust retry the
        # pinned mock forces runs for real; without -EncryptConnection the call does not encrypt and the retry never
        # runs (probes failover-trust-20261113 and trust-retry-20261113).
        It "retries with Initial Catalog after a trust certificate retry exposes the failover partner requirement" {
            $partnerInstance = [Dataplat.Dbatools.Parameter.DbaInstanceParameter]$TestConfig.InstanceMulti1
            $partnerAddress = @([System.Net.Dns]::GetHostAddresses($partnerInstance.ComputerName) | Where-Object { $PSItem.AddressFamily -eq "InterNetwork" })[0].IPAddressToString
            $splatPartner = @{
                SqlInstance                 = $(if ($partnerInstance.InstanceName -eq "MSSQLSERVER") { $partnerAddress } else { "$partnerAddress\$($partnerInstance.InstanceName)" })
                FailoverPartner             = "dbatoolsci-partner"
                AllowTrustServerCertificate = $true
                TrustServerCertificate      = $false
                EncryptConnection           = $true
                SqlConnectionOnly           = $true
            }

            $result = Connect-DbaInstance @splatPartner

            $result.ConnectionString | Should -Match "Trust Server Certificate=True"
            $result.ConnectionString | Should -Match "Failover Partner=dbatoolsci-partner"
            $result.ConnectionString | Should -Match "Initial Catalog=master"
        }
    }

    Context "AllowTrustServerCertificate retry" {
        # Quality gate 1: the pin's retry rewrites SqlConnectionObject.ConnectionString, which SMO resets from its own
        # settings before the retry, so -AllowTrustServerCertificate never rescued a connection whose certificate failed
        # validation (probe trust-retry-20261113, pin and port, all nine lab instances, both editions). The port sets
        # ConnectionSettings.TrustServerCertificate instead. By IPv4 address an encrypted connection fails validation
        # on every lab instance (the name does not match the certificate, or its chain is not trusted), which makes
        # the retry run wherever the runner places InstanceSingle.
        BeforeAll {
            $singleInstance = [Dataplat.Dbatools.Parameter.DbaInstanceParameter]$TestConfig.InstanceSingle
            $singleAddress = @([System.Net.Dns]::GetHostAddresses($singleInstance.ComputerName) | Where-Object { $PSItem.AddressFamily -eq "InterNetwork" })[0].IPAddressToString
            $addressInstance = if ($singleInstance.InstanceName -eq "MSSQLSERVER") { $singleAddress } else { "$singleAddress\$($singleInstance.InstanceName)" }
        }

        It "fails validation by address without the switch, and connects with it through one retry" {
            $plainWarnings = @()
            $splatPlain = @{
                SqlInstance            = $addressInstance
                EncryptConnection      = $true
                TrustServerCertificate = $false
                DisableException       = $true
                WarningVariable        = "plainWarnings"
                WarningAction          = "SilentlyContinue"
            }
            Connect-DbaInstance @splatPlain | Should -BeNullOrEmpty
            @($plainWarnings | Where-Object { "$PSItem" -match "certificate|principal name" }).Count | Should -Be 1

            $splatRetry = @{
                SqlInstance                 = $addressInstance
                EncryptConnection           = $true
                TrustServerCertificate      = $false
                AllowTrustServerCertificate = $true
            }
            $savedDebugPreference = $DebugPreference
            $DebugPreference = "Continue"
            try {
                $records = @(Connect-DbaInstance @splatRetry 5>&1)
            } finally {
                $DebugPreference = $savedDebugPreference
            }
            $debugMessages = @($records | Where-Object { $PSItem -is [System.Management.Automation.DebugRecord] } | ForEach-Object { $PSItem.Message })
            $server = @($records | Where-Object { $PSItem -isnot [System.Management.Automation.DebugRecord] })

            @($debugMessages | Where-Object { $PSItem -like "*Retrying connection with TrustServerCertificate enabled*" }).Count | Should -Be 1
            @($debugMessages | Where-Object { $PSItem -like "*Retry with TrustServerCertificate also failed*" }).Count | Should -Be 0
            $server.Count | Should -Be 1
            $server[0] | Should -BeOfType Microsoft.SqlServer.Management.Smo.Server
            $server[0].ConnectionContext.TrustServerCertificate | Should -BeTrue
            $server[0].ConnectionContext.ExecuteScalar("SELECT encrypt_option FROM sys.dm_exec_connections WHERE session_id = @@SPID") | Should -Be "TRUE"
        }
    }

    Context "Exception switches" {
        It "warns and returns nothing with -EnableException:`$false" -Tag "NativeChecklist:enable-exception", "NativeChecklist:switch-false" {
            # -EnableException is not a parameter of the pinned function; the native build has always accepted it
            # (notes: enableexception-20261111.md). Turned off, it gives the warning -DisableException gives.
            $offWarnings = @()
            $splatOff = @{
                SqlInstance     = $badInstance
                ConnectTimeout  = 3
                EnableException = $false
                WarningVariable = "offWarnings"
                WarningAction   = "SilentlyContinue"
            }
            $result = Connect-DbaInstance @splatOff
            $result | Should -BeNullOrEmpty
            ($offWarnings -join " ") | Should -BeLike "*Failure*"
        }

        It "still throws with -DisableException:`$false" -Tag "NativeChecklist:switch-false" {
            { Connect-DbaInstance -SqlInstance $badInstance -ConnectTimeout 3 -DisableException:$false -WarningAction SilentlyContinue } | Should -Throw
        }

        It "lets -DisableException decide when an EnableException default is set" -Tag "NativeChecklist:enable-exception" {
            # The pinned function has no -EnableException, so a $PSDefaultParameterValues entry for it never
            # reached it, and -DisableException still warned.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            try {
                $defaultWarnings = @()
                $splatDisabled = @{
                    SqlInstance      = $badInstance
                    ConnectTimeout   = 3
                    DisableException = $true
                    WarningVariable  = "defaultWarnings"
                    WarningAction    = "SilentlyContinue"
                }
                $result = Connect-DbaInstance @splatDisabled
                $result | Should -BeNullOrEmpty
                ($defaultWarnings -join " ") | Should -BeLike "*Failure*"
            } finally {
                $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
            }
        }
    }

    Context "SQL login" -Tag "NativeChecklist:sql-login" {
        It "connects with -SqlCredential as that login" {
            $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSqlLogin -SqlCredential $TestConfig.SqlLoginCred
            $server.ConnectedAs | Should -Be $TestConfig.SqlLoginCred.UserName
            $server.ConnectionContext.LoginSecure | Should -BeFalse
            $server.ConnectionContext.ExecuteScalar("SELECT SUSER_SNAME()") | Should -Be $TestConfig.SqlLoginCred.UserName
        }

        It "throws without the credential, where the Windows account is denied" {
            { Connect-DbaInstance -SqlInstance $TestConfig.InstanceSqlLogin -WarningAction SilentlyContinue } | Should -Throw
        }

        It "warns and returns nothing without the credential under -DisableException" {
            $loginWarnings = @()
            $splatNoCredential = @{
                SqlInstance      = $TestConfig.InstanceSqlLogin
                DisableException = $true
                WarningVariable  = "loginWarnings"
                WarningAction    = "SilentlyContinue"
            }
            $result = Connect-DbaInstance @splatNoCredential
            $result | Should -BeNullOrEmpty
            ($loginWarnings -join " ") | Should -BeLike "*Failure*"
        }

        It "switches the database of a wrapped Authentication=SqlPassword connection that hides its password" {
            # Quality gate 1 (pinned 942): the pin reads every Authentication other than NotSpecified as passwordless,
            # SqlPassword included, so it rebuilt the copy from the visible string, which an opened connection without
            # Persist Security Info shows without the password, and the login failed. The copy's own connection keeps
            # the login and takes a USE.
            $builder = New-Object -TypeName Microsoft.Data.SqlClient.SqlConnectionStringBuilder
            $builder["Data Source"] = ([Dataplat.Dbatools.Parameter.DbaInstanceParameter]$TestConfig.InstanceSqlLogin).FullSmoName
            $builder["Authentication"] = "SqlPassword"
            $builder["User ID"] = $TestConfig.SqlLoginCred.UserName
            $builder["Password"] = $TestConfig.SqlLoginCred.GetNetworkCredential().Password
            $builder["Persist Security Info"] = $false
            $builder["Trust Server Certificate"] = $true
            $builder["Initial Catalog"] = "master"
            $connection = New-Object -TypeName Microsoft.Data.SqlClient.SqlConnection -ArgumentList $builder.ConnectionString
            $server = $null
            try {
                $connection.Open()
                (New-Object -TypeName Microsoft.Data.SqlClient.SqlConnectionStringBuilder -ArgumentList $connection.ConnectionString)["Password"] | Should -BeNullOrEmpty
                $wrapped = Connect-DbaInstance -SqlInstance $connection
                $server = Connect-DbaInstance -SqlInstance $wrapped -Database tempdb
                $server.ConnectionContext.ExecuteScalar("SELECT DB_NAME()") | Should -Be "tempdb"
                $server.ConnectionContext.ExecuteScalar("SELECT SUSER_SNAME()") | Should -Be $TestConfig.SqlLoginCred.UserName
            } finally {
                if ($server) {
                    $server.ConnectionContext.Disconnect()
                }
                $connection.Dispose()
            }
        }
    }

    Context "Explicit Windows credentials" {
        BeforeAll {
            # The pinned Connect-DbaInstance.WindowsSspi.Tests.ps1 signs in with a temporary local Windows user of the
            # machine running the tests, so it needs the instance on that machine; the lab instances are remote. Harness
            # section "Connect-DbaInstance: a temporary local Windows account on the SQL host for the SSPI test (operator,
            # 2026-11-11)" lets this file create that user on the SQL host instead, reached as the account of the leg:
            # a prefixed random name, a random password made here and written nowhere, an expiry four hours out, no
            # group, and nothing left behind.
            $sspiPrefix = "dbacisspi"
            $sspiDescription = "dbatools Connect SSPI test account"
            $sspiHost = $null
            $sspiUserSid = $null
            $sspiLoginCreated = $false

            function Close-NativeSspiConnection($connection) {
                # A provider-backed connection is kept out of the connection hash, so Disconnect-DbaInstance cannot
                # reach it; it and its provider are released by hand.
                if (-not $connection) {
                    return
                }
                $provider = $connection.SspiContextProvider
                if ($connection.State -ne [System.Data.ConnectionState]::Closed) {
                    $connection.Close()
                }
                $connection.Dispose()
                if ($provider) {
                    $provider.Dispose()
                }
            }

            $splatAdmin = @{
                SqlInstance            = $TestConfig.InstanceSingle
                SqlCredential          = $TestConfig.SqlCred
                TrustServerCertificate = $true
                NonPooledConnection    = $true
            }
            $sspiAdmin = Connect-DbaInstance @splatAdmin
            $hostRow = $sspiAdmin.Query("SELECT CAST(SERVERPROPERTY('ComputerNamePhysicalNetBIOS') AS nvarchar(128)) AS PhysicalHost, CAST(SERVERPROPERTY('IsClustered') AS int) AS IsClustered")
            if ($hostRow.IsClustered -ne 0) {
                throw "InstanceSingle is clustered; a local account of one node cannot sign in to it."
            }
            $sspiHost = [string]$hostRow.PhysicalHost
            $sspiUserName = $sspiPrefix + [guid]::NewGuid().ToString("N").Substring(0, 10)
            $sspiPrincipal = $sspiHost + "\" + $sspiUserName

            # Fixtures of runs whose teardown never ran: both the prefix and the description, more than a day old.
            $splatStale = @{
                ComputerName = $sspiHost
                ArgumentList = $sspiPrefix, $sspiDescription
                ScriptBlock  = {
                    param($prefix, $description)
                    $cutoff = (Get-Date).AddDays(-1)
                    foreach ($user in @(Get-LocalUser | Where-Object { $PSItem.Name -like "$prefix*" -and $PSItem.Description -eq $description -and $PSItem.PasswordLastSet -and $PSItem.PasswordLastSet -lt $cutoff })) {
                        $sid = $user.SID.Value
                        Remove-LocalUser -SID $user.SID
                        @(Get-CimInstance -ClassName Win32_UserProfile -Filter "SID='$sid'") | Remove-CimInstance
                        "user " + $user.Name
                    }
                }
            }
            $staleRemoved = @(Invoke-Command @splatStale)
            $stalePattern = ($sspiHost + "\" + $sspiPrefix).Replace("'", "''").Replace("[", "[[]").Replace("%", "[%]").Replace("_", "[_]")
            foreach ($staleLogin in @($sspiAdmin.Query("SELECT name FROM sys.server_principals WHERE type = 'U' AND name LIKE N'$stalePattern%' AND create_date < DATEADD(DAY, -1, GETDATE())"))) {
                $sspiAdmin.Query("DROP LOGIN [" + ([string]$staleLogin.name).Replace("]", "]]") + "]")
                $staleRemoved += "login " + $staleLogin.name
            }
            foreach ($removal in $staleRemoved) {
                Write-Warning "Removed a stale SSPI test fixture: $removal"
            }

            $randomBytes = New-Object byte[] 18
            $generator = [System.Security.Cryptography.RandomNumberGenerator]::Create()
            $generator.GetBytes($randomBytes)
            $generator.Dispose()
            $sspiPassword = New-Object System.Security.SecureString
            foreach ($character in ("Dba!" + [Convert]::ToBase64String($randomBytes).Replace("+", "x").Replace("/", "y").Replace("=", "z") + "9x").ToCharArray()) {
                $sspiPassword.AppendChar($character)
            }
            $sspiPassword.MakeReadOnly()
            $sspiCredential = New-Object System.Management.Automation.PSCredential -ArgumentList $sspiPrincipal, $sspiPassword

            $splatCreate = @{
                ComputerName = $sspiHost
                ArgumentList = $sspiUserName, $sspiPassword, $sspiDescription
                ScriptBlock  = {
                    param($userName, $password, $description)
                    $splatUser = @{
                        Name           = $userName
                        Password       = $password
                        Description    = $description
                        AccountExpires = (Get-Date).AddHours(4)
                    }
                    (New-LocalUser @splatUser).SID.Value
                }
            }
            $sspiUserSid = Invoke-Command @splatCreate
            $sspiAdmin.Query("CREATE LOGIN [" + $sspiPrincipal.Replace("]", "]]") + "] FROM WINDOWS")
            $sspiLoginCreated = $true
        }

        AfterAll {
            $sspiLeft = @()
            Clear-DbaConnectionPool
            if ($sspiLoginCreated) {
                $principalLiteral = $sspiPrincipal.Replace("'", "''")
                try {
                    foreach ($session in @($sspiAdmin.Query("SELECT session_id FROM sys.dm_exec_sessions WHERE original_login_name = N'$principalLiteral'"))) {
                        $sspiAdmin.Query("KILL " + [int]$session.session_id)
                    }
                    $sspiAdmin.Query("IF SUSER_ID(N'$principalLiteral') IS NOT NULL DROP LOGIN [" + $sspiPrincipal.Replace("]", "]]") + "]")
                } catch {
                    $sspiLeft += "drop login " + $sspiPrincipal + ": " + $PSItem.Exception.GetBaseException().Message
                }
                if (@($sspiAdmin.Query("SELECT name FROM sys.server_principals WHERE name = N'$principalLiteral'")).Count) {
                    $sspiLeft += "login " + $sspiPrincipal
                }
            }
            if ($sspiHost) {
                $splatRemove = @{
                    ComputerName = $sspiHost
                    ArgumentList = $sspiUserName, $sspiUserSid
                    ScriptBlock  = {
                        param($userName, $userSid)
                        if (Get-LocalUser -Name $userName -ErrorAction SilentlyContinue) {
                            Remove-LocalUser -Name $userName
                        }
                        if ($userSid) {
                            @(Get-CimInstance -ClassName Win32_UserProfile -Filter "SID='$userSid'") | Remove-CimInstance
                        }
                        if (Get-LocalUser -Name $userName -ErrorAction SilentlyContinue) {
                            "user " + $userName
                        }
                        if ($userSid -and @(Get-CimInstance -ClassName Win32_UserProfile -Filter "SID='$userSid'").Count) {
                            "profile " + $userSid
                        }
                    }
                }
                try {
                    $sspiLeft += @(Invoke-Command @splatRemove)
                } catch {
                    $sspiLeft += "host teardown: " + $PSItem.Exception.GetBaseException().Message
                }
            }
            if ($sspiAdmin) {
                $sspiAdmin.ConnectionContext.Disconnect()
            }
            if ($sspiLeft.Count) {
                throw "The explicit Windows credential tests left fixtures behind: " + ($sspiLeft -join "; ")
            }
        }

        It "signs in as that account and reopens the same provider-backed connection" {
            $splatConnect = @{
                SqlInstance            = $TestConfig.InstanceSingle
                SqlCredential          = $sspiCredential
                NonPooledConnection    = $true
                TrustServerCertificate = $true
            }
            $server = Connect-DbaInstance @splatConnect
            $connection = $server.ConnectionContext.SqlConnectionObject
            try {
                $connection.SspiContextProvider | Should -BeOfType Dataplat.Dbatools.Connection.NetworkCredentialSspiContextProvider
                $server.ConnectionContext.ConnectAsUser | Should -BeFalse
                $server.ConnectionContext.ConnectAsUserName | Should -BeNullOrEmpty
                $server.ConnectionContext.ExecuteScalar("SELECT ORIGINAL_LOGIN()") | Should -Be $sspiPrincipal
                $server.ConnectionContext.Disconnect()

                foreach ($attempt in 1..2) {
                    $connection.Open()
                    $command = $connection.CreateCommand()
                    try {
                        $command.CommandText = "SELECT ORIGINAL_LOGIN()"
                        $command.ExecuteScalar() | Should -Be $sspiPrincipal
                    } finally {
                        $command.Dispose()
                        $connection.Close()
                    }
                }
            } finally {
                Close-NativeSspiConnection $connection
            }
        }

        It "refuses a wrong password rather than signing in as the account of the session" {
            # Were the credential ignored, the account running the tests would sign in and this would return a server.
            $wrongPassword = New-Object System.Security.SecureString
            foreach ($character in "Wrong!9x".ToCharArray()) {
                $wrongPassword.AppendChar($character)
            }
            $splatWrong = @{
                SqlInstance            = $TestConfig.InstanceSingle
                SqlCredential          = New-Object System.Management.Automation.PSCredential -ArgumentList $sspiPrincipal, $wrongPassword
                NonPooledConnection    = $true
                TrustServerCertificate = $true
                WarningAction          = "SilentlyContinue"
            }
            { Connect-DbaInstance @splatWrong } | Should -Throw
        }

        It "returns a provider-backed connection with -SqlConnectionOnly and caches nothing" {
            # The real-call form of the pinned "uses the SqlClient SSPI provider for explicit Windows credentials".
            $null = Get-DbaConnectedInstance | Disconnect-DbaInstance
            Clear-DbaConnectionPool
            $splatConnectionOnly = @{
                SqlInstance            = $TestConfig.InstanceSingle
                SqlCredential          = $sspiCredential
                SqlConnectionOnly      = $true
                TrustServerCertificate = $true
            }
            # Audit 1e100d4b: "caches nothing" is a claim about this call. Earlier Its in the leg may leave entries that
            # Disconnect-DbaInstance cannot remove, as the pin does (notes/probe-542-dispose-20261115.md), so the cache is
            # read just before the call and compared after it; nothing here depends on such entries staying.
            $keysBeforeCall = @([Dataplat.Dbatools.Connection.ConnectionHost]::ActiveConnections.Keys | ForEach-Object { [string]$PSItem })
            $connection = Connect-DbaInstance @splatConnectionOnly
            try {
                $connection | Should -BeOfType Microsoft.Data.SqlClient.SqlConnection
                $connection.SspiContextProvider | Should -BeOfType Dataplat.Dbatools.Connection.NetworkCredentialSspiContextProvider
                if ($connection.State -ne [System.Data.ConnectionState]::Open) {
                    $connection.Open()
                }
                $command = $connection.CreateCommand()
                try {
                    $command.CommandText = "SELECT ORIGINAL_LOGIN()"
                    $command.ExecuteScalar() | Should -Be $sspiPrincipal
                } finally {
                    $command.Dispose()
                }
                # Audit b9072c0c: name any entry left in the cache. Each key is parsed by SqlConnectionStringBuilder with
                # its Password value removed, never by text replacement; a key that does not parse is not shown. Its
                # source, the type of the object cached under it, is shown beside it.
                $shownEntries = foreach ($cachedKey in @([Dataplat.Dbatools.Connection.ConnectionHost]::ActiveConnections.Keys)) {
                    $cachedSources = @([Dataplat.Dbatools.Connection.ConnectionHost]::ActiveConnections[$cachedKey]) | ForEach-Object {
                        if ($null -eq $PSItem) { "null" } else { $PSItem.GetType().FullName }
                    }
                    try {
                        $keyBuilder = New-Object Microsoft.Data.SqlClient.SqlConnectionStringBuilder -ArgumentList $cachedKey
                        $null = $keyBuilder.Remove("Password")
                        $shownKey = $keyBuilder.ConnectionString
                    } catch {
                        $shownKey = "(key not parsed, not shown)"
                    }
                    "[{0}] from {1}" -f $shownKey, ($cachedSources -join ", ")
                }
                $shownText = @($shownEntries) -join "; "
                # Runs whatever the count: the shown text carries no password of any credential this file uses.
                $knownCredentials = @($sspiCredential, $TestConfig.SqlCred, $TestConfig.SqlLoginCred, $TestConfig.EntraPasswordCred, $TestConfig.AzureSqlDbCred) | Where-Object { $null -ne $PSItem }
                foreach ($knownCredential in $knownCredentials) {
                    $knownPassword = $knownCredential.GetNetworkCredential().Password
                    if ($knownPassword) {
                        $shownText.Contains($knownPassword) | Should -BeFalse -Because "a shown cache key must never carry a password"
                    }
                }
                $keysAfterCall = @([Dataplat.Dbatools.Connection.ConnectionHost]::ActiveConnections.Keys | ForEach-Object { [string]$PSItem })
                $keysChanged = @($keysAfterCall | Where-Object { $PSItem -notin $keysBeforeCall }) + @($keysBeforeCall | Where-Object { $PSItem -notin $keysAfterCall })
                $keysChanged.Count | Should -Be 0 -Because ("the provider-backed connection caches nothing, so the key set is unchanged by the call; entries now: {0}" -f $shownText)
                $holdingConnection = foreach ($cachedKey in $keysAfterCall) {
                    @([Dataplat.Dbatools.Connection.ConnectionHost]::ActiveConnections[$cachedKey]) | Where-Object { [object]::ReferenceEquals($PSItem, $connection) }
                }
                @($holdingConnection).Count | Should -Be 0 -Because ("no cache entry may hold the returned connection; entries now: {0}" -f $shownText)
            } finally {
                Close-NativeSspiConnection $connection
            }
        }

        It "keeps a provider-backed server that is passed back in out of the cache, with and without -SqlConnectionOnly" {
            # Quality gate 1 (pinned 1366, 1555, 1692): the pin skips the connection hash only when its String path made
            # the provider, so a provider-backed server passed back in was cached under a connection string that does
            # not name the account it signed in as, where a later caller with the same string could be handed it.
            $splatConnect = @{
                SqlInstance            = $TestConfig.InstanceSingle
                SqlCredential          = $sspiCredential
                TrustServerCertificate = $true
            }
            $server = Connect-DbaInstance @splatConnect
            $connection = $server.ConnectionContext.SqlConnectionObject
            try {
                $connection.SspiContextProvider | Should -BeOfType Dataplat.Dbatools.Connection.NetworkCredentialSspiContextProvider
                foreach ($connectionOnly in $false, $true) {
                    $keysBeforeCall = @([Dataplat.Dbatools.Connection.ConnectionHost]::ActiveConnections.Keys | ForEach-Object { [string]$PSItem })
                    $result = Connect-DbaInstance -SqlInstance $server -SqlConnectionOnly:$connectionOnly
                    $returned = if ($connectionOnly) { $result } else { $result.ConnectionContext.SqlConnectionObject }
                    $returned.SspiContextProvider | Should -BeOfType Dataplat.Dbatools.Connection.NetworkCredentialSspiContextProvider
                    $keysAfterCall = @([Dataplat.Dbatools.Connection.ConnectionHost]::ActiveConnections.Keys | ForEach-Object { [string]$PSItem })
                    $keysChanged = @($keysAfterCall | Where-Object { $PSItem -notin $keysBeforeCall }) + @($keysBeforeCall | Where-Object { $PSItem -notin $keysAfterCall })
                    $keysChanged.Count | Should -Be 0 -Because "a provider-backed server passed back in caches nothing (-SqlConnectionOnly:$connectionOnly)"
                    $holding = foreach ($cachedKey in $keysAfterCall) {
                        @([Dataplat.Dbatools.Connection.ConnectionHost]::ActiveConnections[$cachedKey]) | Where-Object { [object]::ReferenceEquals($PSItem, $result) -or [object]::ReferenceEquals($PSItem, $returned) -or [object]::ReferenceEquals($PSItem, $server) }
                    }
                    @($holding).Count | Should -Be 0 -Because "no cache entry may hold the provider-backed connection (-SqlConnectionOnly:$connectionOnly)"
                }
            } finally {
                $server.ConnectionContext.Disconnect()
                Close-NativeSspiConnection $connection
            }
        }

        It "trusts the certificate on the retry of a provider-backed connection by address" {
            # Review round 1, 2026-11-18: a ServerConnection built from a SqlConnection keeps that connection's string,
            # so the -AllowTrustServerCertificate retry edits the string whenever the SMO setter did not change it. By
            # IPv4 address an encrypted connection fails validation on every lab instance.
            $singleInstance = [Dataplat.Dbatools.Parameter.DbaInstanceParameter]$TestConfig.InstanceSingle
            $singleAddress = @([System.Net.Dns]::GetHostAddresses($singleInstance.ComputerName) | Where-Object { $PSItem.AddressFamily -eq "InterNetwork" })[0].IPAddressToString
            $splatRetry = @{
                SqlInstance                 = $(if ($singleInstance.InstanceName -eq "MSSQLSERVER") { $singleAddress } else { "$singleAddress\$($singleInstance.InstanceName)" })
                SqlCredential               = $sspiCredential
                EncryptConnection           = $true
                TrustServerCertificate      = $false
                AllowTrustServerCertificate = $true
                NonPooledConnection         = $true
            }
            $server = Connect-DbaInstance @splatRetry
            $connection = $server.ConnectionContext.SqlConnectionObject
            try {
                $connection.SspiContextProvider | Should -BeOfType Dataplat.Dbatools.Connection.NetworkCredentialSspiContextProvider
                (New-Object -TypeName Microsoft.Data.SqlClient.SqlConnectionStringBuilder -ArgumentList $connection.ConnectionString).TrustServerCertificate | Should -BeTrue
                $server.ConnectionContext.ExecuteScalar("SELECT ORIGINAL_LOGIN()") | Should -Be $sspiPrincipal
                # sys.dm_exec_connections needs VIEW SERVER STATE, which the temporary account lacks; the context's admin
                # connection to the same instance reads the row of this session.
                $sessionId = [int]$server.ConnectionContext.ExecuteScalar("SELECT @@SPID")
                @($sspiAdmin.Query("SELECT encrypt_option FROM sys.dm_exec_connections WHERE session_id = $sessionId"))[0].encrypt_option | Should -Be "TRUE"
            } finally {
                $server.ConnectionContext.Disconnect()
                Close-NativeSspiConnection $connection
            }
        }

        It "still caches a Server input that follows an SSPI connection in the same call" {
            # Pinned WindowsSspi: the provider path keeps its own instance out of the connection hash; a later element of
            # the same call must not inherit that.
            $splatSeed = @{
                SqlInstance            = $TestConfig.InstanceSingle
                SqlCredential          = $TestConfig.SqlCred
                TrustServerCertificate = $true
            }
            $seedServer = Connect-DbaInstance @splatSeed
            $servers = $null
            try {
                $null = Get-DbaConnectedInstance | Disconnect-DbaInstance
                Clear-DbaConnectionPool

                $splatMixed = @{
                    SqlInstance            = @($TestConfig.InstanceSingle, $seedServer)
                    SqlCredential          = $sspiCredential
                    TrustServerCertificate = $true
                }
                $servers = @(Connect-DbaInstance @splatMixed)

                $servers.Count | Should -Be 2
                $servers[0].ConnectionContext.ExecuteScalar("SELECT ORIGINAL_LOGIN()") | Should -Be $sspiPrincipal
                $cached = @(Get-DbaConnectedInstance | Where-Object ConnectionType -match "Smo\.Server$")
                $cached.Count | Should -Be 1
            } finally {
                if ($servers -and $servers[0]) {
                    $sspiConnection = $servers[0].ConnectionContext.SqlConnectionObject
                    $servers[0].ConnectionContext.Disconnect()
                    Close-NativeSspiConnection $sspiConnection
                }
                $seedServer.ConnectionContext.Disconnect()
                $null = Get-DbaConnectedInstance | Disconnect-DbaInstance
                Clear-DbaConnectionPool
            }
        }

        It "registers neither the instance nor the gather scripts for tab completion" {
            # The pin hands an SSPI connection to neither the TEPP updater nor the fast gather scripts. The instance is
            # taken out of the TEPP registry first, so an entry afterwards could only come from this connection.
            $teppHost = [Dataplat.Dbatools.TabExpansion.TabExpansionHost]
            $teppKey = ([DbaInstanceParameter]$TestConfig.InstanceSingle).FullSmoName.ToLowerInvariant()
            $savedAccess = $null
            $hadAccess = $teppHost::InstanceAccess.TryRemove($teppKey, [ref]$savedAccess)
            $savedNames = $teppHost::Cache["sqlinstance"]
            $savedSyncDisabled = $teppHost::TeppSyncDisabled
            $savedFastScripts = $teppHost::TeppGatherScriptsFast.ToArray()
            $server = $null
            try {
                $teppHost::Cache["sqlinstance"] = @(@($savedNames) | Where-Object { $PSItem -and "$PSItem" -ne $teppKey })
                $global:nativeSspiTeppSeen = New-Object System.Collections.ArrayList
                $teppHost::TeppGatherScriptsFast.Clear()
                $teppHost::TeppGatherScriptsFast.Add({ $null = $global:nativeSspiTeppSeen.Add($FullSmoName) })
                $teppHost::TeppSyncDisabled = $false

                $splatConnect = @{
                    SqlInstance            = $TestConfig.InstanceSingle
                    SqlCredential          = $sspiCredential
                    NonPooledConnection    = $true
                    TrustServerCertificate = $true
                }
                $server = Connect-DbaInstance @splatConnect

                $server.ConnectionContext.ExecuteScalar("SELECT ORIGINAL_LOGIN()") | Should -Be $sspiPrincipal
                $teppHost::InstanceAccess.ContainsKey($teppKey) | Should -BeFalse
                @($teppHost::Cache["sqlinstance"]) -contains $teppKey | Should -BeFalse
                $global:nativeSspiTeppSeen.Count | Should -Be 0
            } finally {
                if ($server) {
                    $teppConnection = $server.ConnectionContext.SqlConnectionObject
                    $server.ConnectionContext.Disconnect()
                    Close-NativeSspiConnection $teppConnection
                }
                $teppHost::TeppGatherScriptsFast.Clear()
                $teppHost::TeppGatherScriptsFast.AddRange($savedFastScripts)
                $teppHost::TeppSyncDisabled = $savedSyncDisabled
                $teppHost::Cache["sqlinstance"] = $savedNames
                if ($hadAccess) {
                    $teppHost::InstanceAccess[$teppKey] = $savedAccess
                }
                Remove-Variable -Name nativeSspiTeppSeen -Scope Global -ErrorAction SilentlyContinue
            }
        }
    }

    Context "Access token with a Windows credential" {
        It "impersonates nobody and reports the instance as failed before any sign-in" {
            # The one input that still reaches the ConnectAsUser block (ConnectionService.Resolve.cs:987; pinned 1315 and
            # 1374): a truthy -AccessToken with a Windows-shaped -SqlCredential, a non-Azure instance and no
            # -AuthenticationType. The token branch builds the ServerConnection from a SqlConnection, and SMO refuses
            # ConnectAsUser there (PropertyNotAvailableException, SMO 18.100 on both editions), so nothing is impersonated.
            # The pin stops at that setter with ExceptionWhenSetting,Connect-DbaInstance in both modes, -DisableException
            # included; the port reports the instance as failed (a warning under -DisableException, the same text thrown by
            # default). Neither builds the Server or signs in (probe token-windows-credential-20261112). The debug messages
            # show how far the build went: the one before the ConnectAsUser setter is written, the ones after it are not.
            $unusedPassword = New-Object System.Security.SecureString
            foreach ($character in "Unused!9x".ToCharArray()) {
                $unusedPassword.AppendChar($character)
            }
            $tokenCredential = New-Object System.Management.Automation.PSCredential -ArgumentList "dbatoolsci-nobody@dbatoolsci.invalid", $unusedPassword
            $refusal = "*Property ConnectAsUser cannot be changed or read after a connection string has been set*"
            $tokenWarnings = @()
            $splatToken = @{
                SqlInstance      = $TestConfig.InstanceSingle
                AccessToken      = "dbatoolsci-not-a-token"
                SqlCredential    = $tokenCredential
                DisableException = $true
                WarningVariable  = "tokenWarnings"
                WarningAction    = "SilentlyContinue"
            }
            $savedDebugPreference = $DebugPreference
            $DebugPreference = "Continue"
            try {
                $records = @(Connect-DbaInstance @splatToken 5>&1)
            } finally {
                $DebugPreference = $savedDebugPreference
            }
            $debugMessages = @($records | Where-Object { $PSItem -is [System.Management.Automation.DebugRecord] } | ForEach-Object { $PSItem.Message })

            @($records | Where-Object { $PSItem -isnot [System.Management.Automation.DebugRecord] }) | Should -BeNullOrEmpty
            @($debugMessages | Where-Object { $PSItem -like "*We have an AccessToken and build a SqlConnection with that token*" }).Count | Should -Be 1
            @($debugMessages | Where-Object { $PSItem -like "*ConnectAsUser will be set to 'True'*" }).Count | Should -Be 1
            @($debugMessages | Where-Object { $PSItem -like "*ConnectAsUserName will be set*" }).Count | Should -Be 0
            @($debugMessages | Where-Object { $PSItem -like "*Building Server from ServerConnection*" }).Count | Should -Be 0
            @($tokenWarnings | Where-Object { "$PSItem" -like "*Failure | $refusal" }).Count | Should -Be 1
            { Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -AccessToken "dbatoolsci-not-a-token" -SqlCredential $tokenCredential -WarningAction SilentlyContinue } | Should -Throw $refusal
        }
    }

    Context "Access token with -NonPooledConnection" {
        It "does not reapply NonPooledConnection to a ServerConnection built from the token connection" {
            # Pinned 226, kept pinned and mocked under point 4 until the lab has a token fixture: a real call with a
            # made-up token is refused at sign-in, so the connection string of a returned connection cannot be read.
            # This covers the rest by a real call. The token connection already carries Pooling=False, and SMO refuses
            # NonPooledConnection on a ServerConnection built from a SqlConnection ("Property NonPooledConnection cannot
            # be changed or read after a connection string has been set."), the throw the pinned mock simulates. The
            # build reaches the check (the StatementTimeout line just before it), never writes the setter's line, and
            # goes on to the sign-in, which refuses the token.
            $tokenWarnings = @()
            $tokenErrors = @()
            $splatToken = @{
                SqlInstance         = $TestConfig.AzureSqlDbServer
                Database            = $TestConfig.AzureSqlDbName
                AccessToken         = "dbatoolsci-not-a-token"
                NonPooledConnection = $true
                SqlConnectionOnly   = $true
                DisableException    = $true
                WarningVariable     = "tokenWarnings"
                WarningAction       = "SilentlyContinue"
                ErrorVariable       = "tokenErrors"
                ErrorAction         = "SilentlyContinue"
            }
            $savedDebugPreference = $DebugPreference
            $DebugPreference = "Continue"
            try {
                $records = @(Connect-DbaInstance @splatToken 5>&1)
            } finally {
                $DebugPreference = $savedDebugPreference
            }
            $debugMessages = @($records | Where-Object { $PSItem -is [System.Management.Automation.DebugRecord] } | ForEach-Object { $PSItem.Message })
            $reported = @($tokenWarnings | ForEach-Object { "$PSItem" }) + @($tokenErrors | ForEach-Object { "$PSItem"; "$($PSItem.Exception)" })

            @($records | Where-Object { $PSItem -isnot [System.Management.Automation.DebugRecord] }) | Should -BeNullOrEmpty
            @($debugMessages | Where-Object { $PSItem -like "*We have an AccessToken and build a SqlConnection with that token*" }).Count | Should -Be 1
            @($debugMessages | Where-Object { $PSItem -like "*Setting ConnectionContext.StatementTimeout to*" }).Count | Should -Be 1
            @($debugMessages | Where-Object { $PSItem -like "*Setting ConnectionContext.NonPooledConnection*" }).Count | Should -Be 0
            # The warning carries the exception's stack, whose frame SqlConnectionFactory.CreateNonPooledConnection is
            # not the property, so the match needs no letter before the name.
            ($reported -join " ") | Should -Not -Match "(?<![A-Za-z])NonPooledConnection"
            ($reported -join " ") | Should -BeLike "*Failure*"
        }
    }

    Context "Microsoft Entra password on a non-Azure instance" {
        It "builds an ActiveDirectoryPassword connection from the credential and impersonates nobody" {
            # Pinned 382, kept pinned and mocked under point 4: no lab SQL Server outside Azure accepts Microsoft Entra
            # password sign-in, so a real call returns no connection whose string could be read (probe
            # aad-password-nonazure-20261112: the server refuses the login on both editions, pinned and native). This
            # covers the build by a real call. The debug messages show what the pinned assertions read:
            # - Authentication is set from -AuthenticationType (pinned 388) and integrated security is turned off (390).
            # - The user name and password come from the credential (389).
            # - The ServerConnection is built from that SqlConnectionInfo.
            # - The ConnectAsUser block is never reached (391-392).
            # - The masked connection string the port logs before the sign-in (ConnectionService.Verify.cs:23) carries
            #   the three ConnectionString assertions of pinned 388-390 on the real call.
            # The refusal text can differ by SQL Server version, so only the failure report is asserted. Probe
            # aad-password-debug-20261113 measured this call on SQL 2017, 2019 and 2022 under both editions: the same
            # debug sequence, masked connection string and refusal on all six.
            $unusedPassword = New-Object System.Security.SecureString
            foreach ($character in "Unused!9x".ToCharArray()) {
                $unusedPassword.AppendChar($character)
            }
            $entraCredential = New-Object System.Management.Automation.PSCredential -ArgumentList "user@contoso.com", $unusedPassword
            $entraWarnings = @()
            $splatEntra = @{
                SqlInstance        = $TestConfig.InstanceSingle
                SqlCredential      = $entraCredential
                AuthenticationType = "ActiveDirectoryPassword"
                SqlConnectionOnly  = $true
                DisableException   = $true
                WarningVariable    = "entraWarnings"
                WarningAction      = "SilentlyContinue"
            }
            $savedDebugPreference = $DebugPreference
            $DebugPreference = "Continue"
            try {
                $records = @(Connect-DbaInstance @splatEntra 5>&1)
            } finally {
                $DebugPreference = $savedDebugPreference
            }
            $debugMessages = @($records | Where-Object { $PSItem -is [System.Management.Automation.DebugRecord] } | ForEach-Object { $PSItem.Message })

            @($records | Where-Object { $PSItem -isnot [System.Management.Automation.DebugRecord] }) | Should -BeNullOrEmpty
            @($debugMessages | Where-Object { $PSItem -like "*Authentication will be set to 'ActiveDirectoryPassword' (from AuthenticationType parameter)*" }).Count | Should -Be 1
            @($debugMessages | Where-Object { $PSItem -like "*UseIntegratedSecurity will be set to 'False' for ActiveDirectoryPassword*" }).Count | Should -Be 1
            @($debugMessages | Where-Object { $PSItem -like "*UserName will be set to 'user@contoso.com'*" }).Count | Should -Be 1
            @($debugMessages | Where-Object { $PSItem -like "*SecurePassword will be set*" }).Count | Should -Be 1
            @($debugMessages | Where-Object { $PSItem -like "*Building ServerConnection from SqlConnectionInfo*" }).Count | Should -Be 1
            @($debugMessages | Where-Object { $PSItem -like "*ConnectAsUser*" }).Count | Should -Be 0
            $maskedConnectionStrings = @($debugMessages | Where-Object { $PSItem -like "*The masked server.ConnectionContext.ConnectionString is *" })
            $maskedConnectionStrings.Count | Should -Be 1
            $maskedConnectionStrings[0] | Should -Match "Authentication=ActiveDirectoryPassword"
            $maskedConnectionStrings[0] | Should -Match "User ID=user@contoso.com"
            $maskedConnectionStrings[0] | Should -Not -Match "Integrated Security=True"
            @($entraWarnings | Where-Object { "$PSItem" -like "*Failure | Error connecting to*" }).Count | Should -Be 1
        }

        It "puts the dbatools password provider in place for the connection string form too" {
            # Review round 1, 2026-11-18: SqlClient's own ActiveDirectoryPassword provider signs in through the Windows
            # account broker, which fails without an interactive logon session, so the first such connect of a process
            # registers dbatools' provider. The connection string form must do that as -AuthenticationType does. The
            # registration happens once per process, so a shell of the same edition that has loaded only the module
            # connects once and reports what SqlClient holds afterwards; the lab instance refuses the sign-in itself.
            $moduleBase = @(Get-Module -Name dbatools)[0].ModuleBase
            $shellPath = (Get-Process -Id $PID).Path
            $dataSource = ([Dataplat.Dbatools.Parameter.DbaInstanceParameter]$TestConfig.InstanceSingle).FullSmoName
            $probe = {
                param($ModuleBase, $DataSource)
                Import-Module -Name (Join-Path -Path $ModuleBase -ChildPath "dbatools.psm1") -DisableNameChecking
                $builder = New-Object -TypeName Microsoft.Data.SqlClient.SqlConnectionStringBuilder
                $builder["Data Source"] = $DataSource
                $builder["Authentication"] = "ActiveDirectoryPassword"
                $builder["User ID"] = "user@contoso.com"
                $builder["Password"] = "Unused!9x"
                $builder["Trust Server Certificate"] = $true
                $splatEntra = @{
                    SqlInstance       = $builder.ConnectionString
                    SqlConnectionOnly = $true
                    DisableException  = $true
                    Verbose           = $true
                    WarningAction     = "SilentlyContinue"
                }
                $records = @(Connect-DbaInstance @splatEntra 4>&1)
                $passwordMethod = [Microsoft.Data.SqlClient.SqlAuthenticationMethod]"ActiveDirectoryPassword"
                [pscustomobject]@{
                    Registered = @($records | Where-Object { $PSItem -is [System.Management.Automation.VerboseRecord] -and $PSItem.Message -like "*Registered the dbatools Microsoft Entra password provider*" }).Count
                    Provider   = [Microsoft.Data.SqlClient.SqlAuthenticationProvider]::GetProvider($passwordMethod).GetType().FullName
                }
            }
            $report = @(& $shellPath -NoProfile -NonInteractive -Command $probe -args $moduleBase, $dataSource)

            $report.Count | Should -Be 1
            $report[0].Registered | Should -Be 1
            $report[0].Provider | Should -Be "Dataplat.Dbatools.Connection.EntraPasswordAuthenticationProvider"
        }
    }

    Context "Microsoft Entra sign-in with the shipped libraries" {
        It "signs in through Microsoft.Identity.Client and works through SMO and Microsoft.Data.SqlClient" {
            # On Windows PowerShell the module used to ship System.Runtime.CompilerServices.Unsafe 4.0.4.1 to every
            # request. Microsoft.Identity.Client, which Microsoft.Data.SqlClient uses for every Microsoft Entra
            # authentication type, needs Unsafe 6.x, so each such sign-in failed with "Method not found: ...
            # Unsafe.AddByteOffset(!!0 ByRef, UIntPtr)" (probe entra-382-draft-r1-20261114). The build now ships the
            # .NET Framework build of 6.x and the loader serves it to every request. This It makes the real sign-in on
            # both editions. InstanceEntra is a SQL Server 2022 on Windows set up for Microsoft Entra authentication;
            # EntraPasswordCred is a Microsoft Entra user with a password and a login there. The leg writes
            # EntraPasswordCred as $null when the operator's host file is absent; this test then fails here.
            $TestConfig.InstanceEntra | Should -Not -BeNullOrEmpty -Because "the leg must name the Microsoft Entra instance"
            $TestConfig.EntraPasswordCred | Should -BeOfType System.Management.Automation.PSCredential -Because "the leg must carry the Microsoft Entra test user"
            $splatEntra = @{
                SqlInstance        = $TestConfig.InstanceEntra
                SqlCredential      = $TestConfig.EntraPasswordCred
                AuthenticationType = "ActiveDirectoryPassword"
            }

            # Microsoft.Data.SqlClient: open the returned connection and query through it.
            $connection = Connect-DbaInstance @splatEntra -SqlConnectionOnly
            try {
                if ($connection.State -ne "Open") {
                    $connection.Open()
                }
                $command = $connection.CreateCommand()
                $command.CommandText = "SELECT SUSER_SNAME()"
                $command.ExecuteScalar() | Should -Be $TestConfig.EntraPasswordCred.UserName
                $command.Dispose()
            } finally {
                $connection.Dispose()
            }

            # SMO: a server object signed in the same way reads server metadata and runs a query.
            $server = Connect-DbaInstance @splatEntra -NonPooledConnection
            try {
                $server.VersionMajor | Should -BeGreaterOrEqual 16
                $server.ConnectionContext.ExecuteScalar("SELECT SUSER_SNAME()") | Should -Be $TestConfig.EntraPasswordCred.UserName
                @($server.Databases.Name) | Should -Contain "master"
            } finally {
                $server.ConnectionContext.Disconnect()
            }

            # Every loaded copy of Unsafe has the member Microsoft.Identity.Client needs.
            $loadedUnsafe = @([AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $PSItem.GetName().Name -eq "System.Runtime.CompilerServices.Unsafe" })
            foreach ($assembly in $loadedUnsafe) {
                $unsafeType = $assembly.GetType("System.Runtime.CompilerServices.Unsafe")
                if ($null -eq $unsafeType) {
                    # A forwarding facade (PowerShell 7): the type lives in the shared framework.
                    $unsafeType = [System.Runtime.CompilerServices.Unsafe]
                }
                $byteOffsetOverloads = @($unsafeType.GetMethods() | Where-Object { $PSItem.Name -eq "AddByteOffset" -and @($PSItem.GetParameters())[1].ParameterType -eq [System.UIntPtr] })
                $byteOffsetOverloads.Count | Should -BeGreaterThan 0 -Because "$($assembly.FullName) at $($assembly.Location) must have AddByteOffset(ref T, UIntPtr)"
            }
        }

        It "signs in with -AccessToken, given as text and as an object whose Token is a SecureString" {
            # Follow-up 746d91d8 (review round 1): the access-token Its elsewhere prove only the refusal of a fabricated
            # token. This one gets a real token for EntraPasswordCred from the Microsoft.Identity.Client the module ships,
            # with the public client id, scope and username-password flow of the module's own ActiveDirectoryPassword
            # provider (EntraPasswordAuthenticationProvider), and signs in to InstanceEntra with it in the two forms the
            # help documents: the token text, and Get-AzAccessToken's object whose Token is a SecureString (Az 14).
            $TestConfig.InstanceEntra | Should -Not -BeNullOrEmpty -Because "the leg must name the Microsoft Entra instance"
            $TestConfig.EntraPasswordCred | Should -BeOfType System.Management.Automation.PSCredential -Because "the leg must carry the Microsoft Entra test user"
            $userName = $TestConfig.EntraPasswordCred.UserName
            # The provider SqlClient holds for ActiveDirectoryPassword is the shipped one: the context's first It signed in
            # with ActiveDirectoryPassword in this process, and that first connect registered it. The class is internal,
            # so its assembly is reached through that instance, not a type literal.
            $passwordProvider = [Microsoft.Data.SqlClient.SqlAuthenticationProvider]::GetProvider([Microsoft.Data.SqlClient.SqlAuthenticationMethod]::ActiveDirectoryPassword)
            $passwordProvider.GetType().FullName | Should -Be "Dataplat.Dbatools.Connection.EntraPasswordAuthenticationProvider"
            $msalName = @($passwordProvider.GetType().Assembly.GetReferencedAssemblies() | Where-Object { $PSItem.Name -eq "Microsoft.Identity.Client" })
            $msalName.Count | Should -Be 1
            # The copy the provider signed in with is loaded already; use it rather than a second copy.
            $msal = @([AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $PSItem.FullName -eq $msalName[0].FullName })
            if ($msal.Count -eq 0) {
                $msal = @([System.Reflection.Assembly]::Load($msalName[0]))
            }
            $builderType = $msal[0].GetType("Microsoft.Identity.Client.PublicClientApplicationBuilder", $true)
            $authority = "https://login.microsoftonline.com/$($userName.Split("@")[-1])/"
            $client = $builderType::Create("2fd908ad-0664-4344-b9be-cd3e8b574c38").WithAuthority($authority, $true).Build()
            $scopes = [string[]]@("https://database.windows.net//.default")
            $tokenResult = $client.AcquireTokenByUsernamePassword($scopes, $userName, $TestConfig.EntraPasswordCred.GetNetworkCredential().Password).ExecuteAsync().GetAwaiter().GetResult()
            $token = $tokenResult.AccessToken
            $token | Should -Not -BeNullOrEmpty

            # SMO, with the token text.
            $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceEntra -AccessToken $token
            try {
                $server.VersionMajor | Should -BeGreaterOrEqual 16
                $server.ConnectionContext.ExecuteScalar("SELECT SUSER_SNAME()") | Should -Be $userName
                @($server.Databases.Name) | Should -Contain "master"
            } finally {
                $server.ConnectionContext.Disconnect()
            }

            # Microsoft.Data.SqlClient, with the token as Get-AzAccessToken returns it from Az 14 on.
            $secureToken = New-Object -TypeName System.Security.SecureString
            foreach ($character in $token.ToCharArray()) {
                $secureToken.AppendChar($character)
            }
            $secureToken.MakeReadOnly()
            $azToken = [pscustomobject]@{ Token = $secureToken }
            $connection = Connect-DbaInstance -SqlInstance $TestConfig.InstanceEntra -AccessToken $azToken -SqlConnectionOnly
            try {
                if ($connection.State -ne "Open") {
                    $connection.Open()
                }
                $command = $connection.CreateCommand()
                $command.CommandText = "SELECT SUSER_SNAME()"
                $command.ExecuteScalar() | Should -Be $userName
                $command.Dispose()
            } finally {
                $connection.Dispose()
            }
        }

        It "signs in with an Authentication=ActiveDirectoryPassword connection string in a new process" {
            # F4 (review round 1): the connection string form registers the module's password provider as
            # -AuthenticationType does. The It in "Microsoft Entra password on a non-Azure instance" proves the registration
            # against an instance that refuses the user; this one signs in for real. A shell of the same edition that has
            # loaded only the module connects to InstanceEntra in the connection string form first, so no
            # -AuthenticationType call of that process registered the provider before it.
            $TestConfig.InstanceEntra | Should -Not -BeNullOrEmpty -Because "the leg must name the Microsoft Entra instance"
            $TestConfig.EntraPasswordCred | Should -BeOfType System.Management.Automation.PSCredential -Because "the leg must carry the Microsoft Entra test user"
            $moduleBase = @(Get-Module -Name dbatools)[0].ModuleBase
            $shellPath = (Get-Process -Id $PID).Path
            $dataSource = ([Dataplat.Dbatools.Parameter.DbaInstanceParameter]$TestConfig.InstanceEntra).FullSmoName
            $probe = {
                param($ModuleBase, $DataSource, $UserName, $SecurePassword)
                Import-Module -Name (Join-Path -Path $ModuleBase -ChildPath "dbatools.psm1") -DisableNameChecking
                $credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $UserName, $SecurePassword
                $builder = New-Object -TypeName Microsoft.Data.SqlClient.SqlConnectionStringBuilder
                $builder["Data Source"] = $DataSource
                $builder["Authentication"] = "ActiveDirectoryPassword"
                $builder["User ID"] = $credential.UserName
                $builder["Password"] = $credential.GetNetworkCredential().Password
                $builder["Trust Server Certificate"] = $true
                $failure = $null
                try {
                    $records = @(Connect-DbaInstance -SqlInstance $builder.ConnectionString -Verbose 4>&1)
                } catch {
                    $records = @()
                    $failure = $PSItem.Exception.Message
                }
                $servers = @($records | Where-Object { $PSItem -is [Microsoft.SqlServer.Management.Smo.Server] })
                $login = $null
                if ($servers.Count -eq 1) {
                    $login = $servers[0].ConnectionContext.ExecuteScalar("SELECT SUSER_SNAME()")
                    $servers[0].ConnectionContext.Disconnect()
                }
                $passwordMethod = [Microsoft.Data.SqlClient.SqlAuthenticationMethod]"ActiveDirectoryPassword"
                [pscustomobject]@{
                    Registered = @($records | Where-Object { $PSItem -is [System.Management.Automation.VerboseRecord] -and $PSItem.Message -like "*Registered the dbatools Microsoft Entra password provider*" }).Count
                    Provider   = [Microsoft.Data.SqlClient.SqlAuthenticationProvider]::GetProvider($passwordMethod).GetType().FullName
                    Servers    = $servers.Count
                    Login      = $login
                    Failure    = $failure
                }
            }
            $report = @(& $shellPath -NoProfile -NonInteractive -Command $probe -args $moduleBase, $dataSource, $TestConfig.EntraPasswordCred.UserName, $TestConfig.EntraPasswordCred.Password)

            $report.Count | Should -Be 1
            $report[0].Failure | Should -BeNullOrEmpty
            $report[0].Registered | Should -Be 1
            $report[0].Provider | Should -Be "Dataplat.Dbatools.Connection.EntraPasswordAuthenticationProvider"
            $report[0].Servers | Should -Be 1
            $report[0].Login | Should -Be $TestConfig.EntraPasswordCred.UserName
        }
    }

    # NativeSkip: keeps the forced certificate trust of a local dedicated admin connection -- covered: Native Connect-DbaInstance.Local dedicated admin connection on the host of the instance.keeps the forced certificate trust when run on the host of the instance
    Context "Local dedicated admin connection on the host of the instance" {
        BeforeAll {
            # The pinned It runs only where InstanceMulti1 is on the machine running the tests, and no lab leg is. This
            # context runs its assertions on the own host of InstanceMulti1 (watchman 8b04c013, ask 3): the build of this
            # leg, copied as one archive to C:\native\<run>\ there, expanded and checked by hash on that side, imported
            # by path in a remote session of the PowerShell edition of this leg, as the identity of the leg. AfterAll
            # closes the DAC, removes the session and the copy, and fails on anything left behind.
            # Its time limits bound it: a connection with no limit retries a network error without end.
            $dacAdmin = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti1 -NonPooledConnection -ConnectTimeout 30 -StatementTimeout 60
            $dacHostRow = $dacAdmin.Query("SELECT CAST(SERVERPROPERTY('ComputerNamePhysicalNetBIOS') AS nvarchar(128)) AS PhysicalHost, CAST(SERVERPROPERTY('IsClustered') AS int) AS IsClustered")
            if ($dacHostRow.IsClustered -ne 0) {
                throw "InstanceMulti1 is clustered; a local dedicated admin connection needs a standalone instance on its own host."
            }
            $dacHost = [string]$dacHostRow.PhysicalHost
            $dacStage = "C:\native\connect-dac-" + [Guid]::NewGuid().ToString("N").Substring(0, 10)
            $dacModule = "$dacStage\dbatools"
            $dacRemotePid = $null
            $dacSession = $null
            $dacConfiguration = if ($PSVersionTable.PSEdition -eq "Core") { "PowerShell.7" } else { "Microsoft.PowerShell" }

            # Every remote step, from opening the session on, runs apart from this runspace and is stopped at one
            # deadline for the whole setup, so a stalled remote session fails this context instead of holding the leg.
            # The steps that use the remote session share one runspace, kept open until AfterAll: a session closes with
            # the runspace that opened it, and a PowerShell instance made without a runspace closes its own when it is
            # disposed. Errors that do not stop the step are written here as they would have been.
            $dacRunspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
            $dacRunspace.Open()
            $dacBounded = {
                param([string]$What, [string]$Command, [hashtable]$Parameters, [DateTime]$Deadline, [System.Management.Automation.Runspaces.Runspace]$Runspace)
                $remaining = [int]($Deadline - [DateTime]::UtcNow).TotalMilliseconds
                if ($remaining -le 0) {
                    throw "The local DAC test ran out of time before $What on $dacHost."
                }
                $shell = [PowerShell]::Create()
                if ($Runspace) {
                    $shell.Runspace = $Runspace
                }
                $null = $shell.AddCommand($Command).AddParameters($Parameters)
                $pending = $shell.BeginInvoke()
                if (-not $pending.AsyncWaitHandle.WaitOne($remaining)) {
                    $null = $shell.BeginStop($null, $null)
                    throw "The local DAC test ran out of time in $What on $dacHost."
                }
                try {
                    $shell.EndInvoke($pending)
                    foreach ($record in $shell.Streams.Error) {
                        Write-Error -ErrorRecord $record
                    }
                } finally {
                    $shell.Dispose()
                }
            }

            $dacDeadline = [DateTime]::UtcNow.AddSeconds(600)

            # The build of this leg, without its tests folder (it holds the generated constants of the leg) and the empty
            # .git folder the runner adds.
            $dacLocalModule = (Get-Module dbatools).ModuleBase
            $dacItems = @(Get-ChildItem -LiteralPath $dacLocalModule -Force | Where-Object Name -notin "tests", ".git")
            $dacHashScript = {
                param($Base, $Names)
                $lines = foreach ($name in $Names) {
                    $item = Get-Item -LiteralPath (Join-Path $Base $name) -Force
                    $files = if ($item.PSIsContainer) { Get-ChildItem -LiteralPath $item.FullName -Recurse -File -Force } else { $item }
                    foreach ($file in $files) {
                        $fileSha = [System.Security.Cryptography.SHA256]::Create()
                        $stream = [System.IO.File]::OpenRead($file.FullName)
                        try {
                            $fileHash = [BitConverter]::ToString($fileSha.ComputeHash($stream)).Replace("-", "")
                        } finally {
                            $stream.Dispose()
                            $fileSha.Dispose()
                        }
                        $file.FullName.Substring($Base.Length).TrimStart("\").ToLowerInvariant() + ":" + $fileHash
                    }
                }
                $sorted = [string[]]@($lines)
                [Array]::Sort($sorted, [StringComparer]::Ordinal)
                $treeSha = [System.Security.Cryptography.SHA256]::Create()
                try {
                    $treeHash = [BitConverter]::ToString($treeSha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes(($sorted -join "`n")))).Replace("-", "")
                } finally {
                    $treeSha.Dispose()
                }
                [PSCustomObject]@{
                    Count = $sorted.Count
                    Hash  = $treeHash
                }
            }
            $dacLocalHash = & $dacHashScript $dacLocalModule $dacItems.Name

            # The build goes over as one archive: one copy over the remote session, expanded on the host.
            Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
            $dacArchive = Join-Path ([System.IO.Path]::GetTempPath()) "$(Split-Path $dacStage -Leaf).zip"
            $dacRemoteArchive = "$dacStage\dbatools.zip"
            $dacZip = [System.IO.Compression.ZipFile]::Open($dacArchive, [System.IO.Compression.ZipArchiveMode]::Create)
            try {
                foreach ($dacItem in $dacItems) {
                    $dacFiles = if ($dacItem.PSIsContainer) { Get-ChildItem -LiteralPath $dacItem.FullName -Recurse -File -Force } else { $dacItem }
                    foreach ($dacFile in $dacFiles) {
                        $dacEntry = $dacFile.FullName.Substring($dacLocalModule.Length).TrimStart("\").Replace("\", "/")
                        $null = [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($dacZip, $dacFile.FullName, $dacEntry, [System.IO.Compression.CompressionLevel]::Fastest)
                    }
                }
            } finally {
                $dacZip.Dispose()
            }

            $splatOption = @{
                OpenTimeout      = 60000
                OperationTimeout = 900000
            }
            $splatSession = @{
                ComputerName      = $dacHost
                ConfigurationName = $dacConfiguration
                SessionOption     = (New-PSSessionOption @splatOption)
                ErrorAction       = "Stop"
            }
            $dacSession = & $dacBounded "opening the remote session" "New-PSSession" $splatSession $dacDeadline $dacRunspace
            $dacRemotePid = & $dacBounded "reading the remote process id" "Invoke-Command" @{ Session = $dacSession; ScriptBlock = { $PID } } $dacDeadline $dacRunspace
            $splatFolder = @{
                Session      = $dacSession
                ScriptBlock  = { param($Path) $null = New-Item -ItemType Directory -Path $Path -Force }
                ArgumentList = $dacModule
            }
            & $dacBounded "making the copy folder" "Invoke-Command" $splatFolder $dacDeadline $dacRunspace
            $splatCopy = @{
                LiteralPath = $dacArchive
                Destination = $dacRemoteArchive
                ToSession   = $dacSession
                Force       = $true
                ErrorAction = "Stop"
            }
            & $dacBounded "copying the build archive" "Copy-Item" $splatCopy $dacDeadline $dacRunspace
            $splatExpand = @{
                Session      = $dacSession
                ErrorAction  = "Stop"
                ArgumentList = $dacRemoteArchive, $dacModule
                ScriptBlock  = {
                    param($Archive, $Module)
                    Add-Type -AssemblyName System.IO.Compression.FileSystem
                    [System.IO.Compression.ZipFile]::ExtractToDirectory($Archive, $Module)
                    Remove-Item -LiteralPath $Archive -Force
                }
            }
            & $dacBounded "expanding the build archive" "Invoke-Command" $splatExpand $dacDeadline $dacRunspace
            $splatHash = @{
                Session      = $dacSession
                ScriptBlock  = $dacHashScript
                ArgumentList = $dacModule, $dacItems.Name
            }
            $dacRemoteHash = & $dacBounded "hashing the copy" "Invoke-Command" $splatHash $dacDeadline $dacRunspace
            if ($dacRemoteHash.Count -ne $dacLocalHash.Count -or $dacRemoteHash.Hash -cne $dacLocalHash.Hash) {
                throw "The copy on $dacHost does not match the build of this leg: $($dacRemoteHash.Count) files $($dacRemoteHash.Hash), expected $($dacLocalHash.Count) files $($dacLocalHash.Hash)."
            }

            # The pinned It, run on the host of the instance against the copy just checked. Values come back as plain
            # strings, booleans and numbers.
            $splatRun = @{
                Session      = $dacSession
                ArgumentList = $dacModule, $TestConfig.InstanceMulti1, $env:DBATOOLS_NATIVE_STRICT
                ScriptBlock  = {
                    param($Module, $Instance, $Strict)
                    $env:DBATOOLS_NATIVE_STRICT = $Strict
                    $env:PSModulePath = "$Module\modules;$env:PSModulePath"
                    Import-Module "$Module\dbatools.psd1" -ErrorAction Stop
                    $loaded = Get-Module dbatools
                    $localDacConnectionString = "Data Source=$Instance;Integrated Security=True;Encrypt=False;Trust Server Certificate=False"
                    [Microsoft.Data.SqlClient.SqlConnection]$localDacConnection = $localDacConnectionString
                    $serverForLocalDac = Connect-DbaInstance -SqlInstance $localDacConnection
                    try {
                        $startBuilder = New-Object -TypeName Microsoft.Data.SqlClient.SqlConnectionStringBuilder -ArgumentList $serverForLocalDac.ConnectionContext.ConnectionString
                        $startTrust = [bool]$startBuilder["Trust Server Certificate"]
                        $serverClone = Connect-DbaInstance -SqlInstance $serverForLocalDac -DedicatedAdminConnection
                        try {
                            $cloneStringBuilder = New-Object -TypeName Microsoft.Data.SqlClient.SqlConnectionStringBuilder -ArgumentList $serverClone.ConnectionContext.ConnectionString
                            $dacQuery = "SELECT COUNT(*) FROM sys.dm_exec_sessions AS s JOIN sys.endpoints AS e ON e.endpoint_id = s.endpoint_id WHERE e.is_admin_endpoint = 1 AND s.session_id = @@SPID"
                            [PSCustomObject]@{
                                Edition         = [string]$PSVersionTable.PSEdition
                                ModuleBase      = [string]$loaded.ModuleBase
                                IsLocalHost     = [bool]([Dataplat.Dbatools.Parameter.DbaInstanceParameter]$Instance).IsLocalHost
                                StartTrust      = $startTrust
                                CloneTrust      = [bool]$cloneStringBuilder["Trust Server Certificate"]
                                CloneDataSource = [string]$cloneStringBuilder["Data Source"]
                                OnAdminEndpoint = [int]$serverClone.ConnectionContext.ExecuteScalar($dacQuery)
                            }
                        } finally {
                            $null = $serverClone | Disconnect-DbaInstance
                        }
                    } finally {
                        $null = $serverForLocalDac | Disconnect-DbaInstance
                    }
                }
            }
            $dacResult = & $dacBounded "running the test on the host" "Invoke-Command" $splatRun $dacDeadline $dacRunspace
        }

        AfterAll {
            $dacLeftovers = @()
            $dacCleanupDeadline = [DateTime]::UtcNow.AddSeconds(240)
            if ($dacSession) {
                try {
                    & $dacBounded "closing the remote session" "Remove-PSSession" @{ Session = $dacSession; ErrorAction = "SilentlyContinue" } $dacCleanupDeadline $dacRunspace
                } catch {
                    $dacLeftovers += "$PSItem"
                }
            }
            if ($dacRunspace) {
                # Closing it also closes a session still open in it; a close that has not ended by the deadline is left.
                try {
                    $dacRunspace.CloseAsync()
                    while ($dacRunspace.RunspaceStateInfo.State -notin "Closed", "Broken" -and [DateTime]::UtcNow -lt $dacCleanupDeadline) {
                        Start-Sleep -Milliseconds 200
                    }
                    if ($dacRunspace.RunspaceStateInfo.State -in "Closed", "Broken") {
                        $dacRunspace.Dispose()
                    } else {
                        $dacLeftovers += "the runspace of the remote session was still $($dacRunspace.RunspaceStateInfo.State) at the deadline"
                    }
                } catch {
                    $dacLeftovers += "$PSItem"
                }
            }
            # A fresh session on the default endpoint waits for the remote process of the test session to end (it holds
            # the loaded library files), stops it after a minute, then deletes the copy and reports what is left.
            $splatCleanup = @{
                ComputerName = $dacHost
                ErrorAction  = "Stop"
                ArgumentList = $dacStage, $dacRemotePid
                ScriptBlock  = {
                    param($Stage, $RemotePid)
                    $left = @()
                    if ($RemotePid) {
                        $deadline = (Get-Date).AddSeconds(60)
                        while ((Get-Process -Id $RemotePid -ErrorAction SilentlyContinue) -and (Get-Date) -lt $deadline) {
                            Start-Sleep -Milliseconds 500
                        }
                        if (Get-Process -Id $RemotePid -ErrorAction SilentlyContinue) {
                            Stop-Process -Id $RemotePid -Force -ErrorAction SilentlyContinue
                            $left += "the remote process $RemotePid was still running after a minute"
                        }
                    }
                    if (Test-Path -LiteralPath $Stage) {
                        Remove-Item -LiteralPath $Stage -Recurse -Force -ErrorAction SilentlyContinue
                    }
                    if (Test-Path -LiteralPath $Stage) {
                        $left += "$Stage still exists"
                    }
                    $left
                }
            }
            if ($dacHost) {
                try {
                    $dacLeftovers += @(& $dacBounded "removing the copy" "Invoke-Command" $splatCleanup $dacCleanupDeadline)
                } catch {
                    $dacLeftovers += "$PSItem"
                }
            }
            if ($dacAdmin) {
                $openDac = $dacAdmin.Query("SELECT COUNT(*) AS Sessions FROM sys.dm_exec_sessions AS s JOIN sys.endpoints AS e ON e.endpoint_id = s.endpoint_id WHERE e.is_admin_endpoint = 1").Sessions
                if ($openDac -ne 0) {
                    $dacLeftovers += "$openDac session(s) still on the admin endpoint"
                }
                $null = $dacAdmin | Disconnect-DbaInstance
            }
            if ($dacArchive -and (Test-Path -LiteralPath $dacArchive)) {
                Remove-Item -LiteralPath $dacArchive -Force -ErrorAction SilentlyContinue
            }
            if ($dacLeftovers.Count) {
                throw "The local DAC test left: $($dacLeftovers -join '; ')"
            }
        }

        It "keeps the forced certificate trust when run on the host of the instance" {
            # Same build and edition, on the host where the pinned skip condition is false.
            $dacRemoteHash.Count | Should -BeGreaterThan 0
            $dacRemoteHash.Hash | Should -BeExactly $dacLocalHash.Hash
            $dacResult.Edition | Should -BeExactly $PSVersionTable.PSEdition
            $dacResult.ModuleBase | Should -Be $dacModule
            $dacResult.IsLocalHost | Should -BeTrue
            # The pinned assertions, from Trust Server Certificate=False on the string the clone is made from.
            $dacResult.StartTrust | Should -BeFalse
            $dacResult.CloneTrust | Should -BeTrue
            $dacResult.CloneDataSource | Should -Match "^ADMIN:localhost"
            $dacResult.OnAdminEndpoint | Should -Be 1
        }
    }

    Context "Azure SQL Database" -Tag "NativeChecklist:azure-sqldb" {
        BeforeAll {
            $splatAzure = @{
                SqlInstance   = $TestConfig.AzureSqlDbServer
                Database      = $TestConfig.AzureSqlDbName
                SqlCredential = $TestConfig.AzureSqlDbCred
            }
        }

        It "connects to the database and marks the server as Azure" {
            $server = Connect-DbaInstance @splatAzure
            $server.IsAzure | Should -BeTrue
            $server.DatabaseEngineType | Should -Be "SqlAzureDatabase"
            $server.ComputerName | Should -Be ([DbaInstanceParameter]$TestConfig.AzureSqlDbServer).ComputerName
            $server.ConnectionContext.ExecuteScalar("SELECT DB_NAME()") | Should -Be $TestConfig.AzureSqlDbName
        }

        It "refuses it with -AzureUnsupported, throwing by default and warning under -DisableException" {
            { Connect-DbaInstance @splatAzure -AzureUnsupported -WarningAction SilentlyContinue } | Should -Throw "*Azure SQL Database not supported*"

            $azureWarnings = @()
            $splatRefused = @{
                AzureUnsupported = $true
                DisableException = $true
                WarningVariable  = "azureWarnings"
                WarningAction    = "SilentlyContinue"
            }
            $result = Connect-DbaInstance @splatAzure @splatRefused
            $result | Should -BeNullOrEmpty
            ($azureWarnings -join " ") | Should -BeLike "*Azure SQL Database not supported*"
        }
    }

    Context "Tab completion cache from the gather scripts of the module" {
        BeforeAll {
            # The gather scripts the module itself registered, not stand-ins: they are created in its maintenance
            # runspace, which is what this context proves the synchronous path can run (watchmen 8b04c013, cde2e907).
            # The asynchronous cache updater runs the same scripts on its own schedule, so it is stopped for this
            # context and started again afterwards: only Connect-DbaInstance can fill the cache in between.
            $teppHost = [Dataplat.Dbatools.TabExpansion.TabExpansionHost]
            $cacheSavedSyncDisabled = $teppHost::TeppSyncDisabled
            $cacheKey = ([DbaInstanceParameter]$TestConfig.InstanceMulti1).FullSmoName.ToLowerInvariant()
            $loginBuilders = @($teppHost::TeppGatherScriptsFast | Where-Object { $PSItem.ToString().Contains('Cache["login"][$FullSmoName]') })
            $databaseBuilders = @($teppHost::TeppGatherScriptsFast | Where-Object { $PSItem.ToString().Contains('Cache["database"][$FullSmoName]') })
            $runspaces = [Dataplat.Dbatools.Runspace.RunspaceHost]::Runspaces
            $asyncUpdater = if ($runspaces.ContainsKey("dbatools-teppasynccache")) { $runspaces["dbatools-teppasynccache"] } else { $null }
            $asyncWasRunning = $null -ne $asyncUpdater -and "$($asyncUpdater.State)" -eq "Running"
            if ($asyncWasRunning) {
                $asyncUpdater.Stop()
            }
        }

        AfterAll {
            $teppHost::TeppSyncDisabled = $cacheSavedSyncDisabled
            if ($asyncWasRunning) {
                $asyncUpdater.Start()
            }
        }

        It "fills the login and database cache of the instance from them when sync is on" {
            $nativeTeppRegistered | Should -BeTrue -Because "the module registers its gather scripts at import"
            $loginBuilders.Count | Should -Be 1
            $databaseBuilders.Count | Should -Be 1
            "$($asyncUpdater.State)" | Should -Not -Be "Running"
            $teppHost::Cache["login"].Remove($cacheKey)
            $teppHost::Cache["database"].Remove($cacheKey)
            $teppHost::TeppSyncDisabled = $false

            $connected = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti1

            $saLogin = $connected.Query("SELECT name FROM sys.server_principals WHERE sid = 0x01").name
            $cachedLogins = @($teppHost::Cache["login"][$cacheKey])
            $cachedLogins | Should -Contain $saLogin
            Compare-Object -ReferenceObject @($connected.Logins.Name) -DifferenceObject $cachedLogins | Should -BeNullOrEmpty
            $cachedDatabases = @($teppHost::Cache["database"][$cacheKey])
            foreach ($systemDatabase in "master", "model", "msdb", "tempdb") {
                $cachedDatabases | Should -Contain $systemDatabase
            }
            Compare-Object -ReferenceObject @($connected.Databases.Name) -DifferenceObject $cachedDatabases | Should -BeNullOrEmpty
        }

        It "leaves the cache of the instance alone when sync is off, as by default" {
            $nativeTeppRegistered | Should -BeTrue -Because "the module registers its gather scripts at import"
            $teppHost::Cache["login"].Remove($cacheKey)
            $teppHost::Cache["database"].Remove($cacheKey)
            $teppHost::TeppSyncDisabled = $true

            $connected = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti1

            $connected.Name | Should -Be $TestConfig.InstanceMulti1
            $teppHost::Cache["login"].ContainsKey($cacheKey) | Should -BeFalse
            $teppHost::Cache["database"].ContainsKey($cacheKey) | Should -BeFalse
        }

        It "logs the pinned failure text with the name of a gather script of the module that fails" {
            # The login script writes into Cache["login"]; with that table taken away it fails on the instance. The
            # pinned name is the first double-quoted string of the script text, which for this script is login. The pinned
            # Write-Message logs that text followed by " | " and the message of the error record it is given
            # (dbatools.library b1b63e031, WriteMessageCommand.cs:216), and the port's MessageService does the same.
            $nativeTeppRegistered | Should -BeTrue -Because "the module registers its gather scripts at import"
            $pinnedName = [regex]::Match($loginBuilders[0].ToString(), '"(.*?)"').Groups[1].Value
            $pinnedName | Should -BeExactly "login"
            $savedLoginCache = $teppHost::Cache["login"]
            try {
                $teppHost::Cache["login"] = $null
                $teppHost::TeppSyncDisabled = $false
                $started = Get-Date
                $gatherErrors = @()

                $connected = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti1 -ErrorVariable gatherErrors

                $connected.Name | Should -Be $TestConfig.InstanceMulti1
                $gatherErrors.Count | Should -Be 0
                $logged = @([Dataplat.Dbatools.Message.LogHost]::GetLog() | Where-Object { $PSItem.Timestamp -ge $started -and "$($PSItem.Message)" -clike "Failed TEPP Caching: $pinnedName | *" })
                $logged.Count | Should -Be 1
            } finally {
                $teppHost::Cache["login"] = $savedLoginCache
            }
        }
    }

    Context "Tab completion gather scripts" {
        BeforeAll {
            $teppHost = [Dataplat.Dbatools.TabExpansion.TabExpansionHost]
            $savedSyncDisabled = $teppHost::TeppSyncDisabled
            $savedFastScripts = $teppHost::TeppGatherScriptsFast.ToArray()
        }

        AfterAll {
            $teppHost::TeppGatherScriptsFast.Clear()
            $teppHost::TeppGatherScriptsFast.AddRange($savedFastScripts)
            $teppHost::TeppSyncDisabled = $savedSyncDisabled
            Remove-Variable -Name nativeTeppSeen -Scope Global -ErrorAction SilentlyContinue
        }

        It "runs each fast gather script with the new connection's server and lower-cased name" {
            # The registered gather scripts read $FullSmoName and $server, which the pinned function set in its own
            # scope. Variables of the same names in the caller's scope must be neither what the script sees nor changed.
            $global:nativeTeppSeen = New-Object System.Collections.ArrayList
            $teppHost::TeppGatherScriptsFast.Clear()
            $teppHost::TeppGatherScriptsFast.Add({
                    $null = $global:nativeTeppSeen.Add([PSCustomObject]@{
                            FullSmoName = $FullSmoName
                            ServerName  = $server.Name
                        })
                })
            $teppHost::TeppSyncDisabled = $false
            $FullSmoName = "dbatoolsci-caller-name"
            $server = "dbatoolsci-caller-server"

            $connected = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti1

            $connected.Name | Should -Be $TestConfig.InstanceMulti1
            $global:nativeTeppSeen.Count | Should -Be 1
            $global:nativeTeppSeen[0].FullSmoName | Should -BeExactly ([DbaInstanceParameter]$TestConfig.InstanceMulti1).FullSmoName.ToLowerInvariant()
            $global:nativeTeppSeen[0].ServerName | Should -Be $TestConfig.InstanceMulti1
            $FullSmoName | Should -BeExactly "dbatoolsci-caller-name"
            $server | Should -BeExactly "dbatoolsci-caller-server"
        }

        It "only logs a gather script that fails, writing no error and returning the server" {
            # The pinned Write-Message for this failure passes no -EnableException, so it logs and shows nothing, even
            # though Connect-DbaInstance itself throws by default. Developer mode and AppVeyor turn it into an error.
            $savedDeveloperMode = [Dataplat.Dbatools.Message.MessageHost]::DeveloperMode
            $savedAppVeyor = $env:APPVEYOR_BUILD_FOLDER
            try {
                [Dataplat.Dbatools.Message.MessageHost]::DeveloperMode = $false
                Remove-Item -Path Env:APPVEYOR_BUILD_FOLDER -ErrorAction SilentlyContinue
                $teppHost::TeppGatherScriptsFast.Clear()
                $teppHost::TeppGatherScriptsFast.Add({ throw "dbatoolsci gather failure" })
                $teppHost::TeppSyncDisabled = $false
                $started = Get-Date
                $gatherErrors = @()

                $connected = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti2 -ErrorVariable gatherErrors -ErrorAction Stop

                $connected.Name | Should -Be $TestConfig.InstanceMulti2
                $gatherErrors.Count | Should -Be 0
                $logged = @([Dataplat.Dbatools.Message.LogHost]::GetLog() | Where-Object { $PSItem.Timestamp -ge $started -and "$($PSItem.Message)" -like "*Failed TEPP Caching: dbatoolsci gather failure*" })
                $logged.Count | Should -Be 1
            } finally {
                [Dataplat.Dbatools.Message.MessageHost]::DeveloperMode = $savedDeveloperMode
                if ($null -ne $savedAppVeyor) {
                    $env:APPVEYOR_BUILD_FOLDER = $savedAppVeyor
                }
            }
        }
    }

    Context "Service principal secret" {
        It "keeps the client secret out of every message, warning and error" {
            # A tenant and an application id with a secret take the service principal path. Microsoft Entra ID
            # refuses the made-up application, and nothing the command reports may carry the secret.
            $secretText = "dbatoolsci-secret-" + [guid]::NewGuid().ToString("N")
            $splatSecret = @{
                String      = $secretText
                AsPlainText = $true
                Force       = $true
            }
            $clientCredential = New-Object System.Management.Automation.PSCredential ([guid]::NewGuid().ToString(), (ConvertTo-SecureString @splatSecret))
            $started = Get-Date
            # $Error keeps a fixed number of records, so the new ones are found by reference, not by count.
            $errorsBefore = New-Object System.Collections.Generic.HashSet[object]
            foreach ($record in $Error) {
                $null = $errorsBefore.Add($record)
            }
            $principalWarnings = @()
            $principalErrors = @()
            $splatServicePrincipal = @{
                SqlInstance      = $TestConfig.AzureSqlDbServer
                Database         = $TestConfig.AzureSqlDbName
                Tenant           = [guid]::NewGuid().ToString()
                SqlCredential    = $clientCredential
                DisableException = $true
                WarningVariable  = "principalWarnings"
                WarningAction    = "SilentlyContinue"
                ErrorVariable    = "principalErrors"
                ErrorAction      = "SilentlyContinue"
                Verbose          = $true
            }
            $streams = @(Connect-DbaInstance @splatServicePrincipal 4>&1)

            @($streams | Where-Object { $PSItem -isnot [System.Management.Automation.VerboseRecord] }) | Should -BeNullOrEmpty
            $principalWarnings | Should -Not -BeNullOrEmpty
            $newErrors = @($Error | Where-Object { -not $errorsBefore.Contains($PSItem) })
            $logged = @([Dataplat.Dbatools.Message.LogHost]::GetLog() | Where-Object Timestamp -ge $started)
            $reported = @()
            $reported += $streams | ForEach-Object { "$PSItem" }
            $reported += $principalWarnings | ForEach-Object { "$PSItem" }
            $reported += @($principalErrors) + $newErrors | ForEach-Object { "$PSItem"; "$($PSItem.Exception)" }
            $reported += $logged | ForEach-Object { "$($PSItem.Message)" }
            $logged.Count | Should -BeGreaterThan 0
            @($reported | Where-Object { $PSItem -like "*$secretText*" }) | Should -BeNullOrEmpty
        }

        It "asks Microsoft Entra ID for the token on Windows PowerShell and warns with its answer" {
            # Pinned 541-559: on Windows PowerShell the flow takes New-DbaAzAccessToken's renewable token for Azure SQL
            # Database and asks it for its access token, and a failure warns "Failed to get access token for Azure SQL DB
            # (...)"; PowerShell 7 rewrites the instance into a service principal connection string instead. The request
            # really reaches Microsoft Entra ID, which answers a tenant that does not exist with an AADSTS error.
            $clientCredential = New-Object System.Management.Automation.PSCredential ([guid]::NewGuid().ToString(), (ConvertTo-SecureString "dbatoolsci-secret" -AsPlainText -Force))
            $tokenWarnings = @()
            $splatToken = @{
                SqlInstance      = $TestConfig.AzureSqlDbServer
                Database         = $TestConfig.AzureSqlDbName
                Tenant           = "dbatoolsci.invalid"
                SqlCredential    = $clientCredential
                DisableException = $true
                WarningVariable  = "tokenWarnings"
                WarningAction    = "SilentlyContinue"
            }

            Connect-DbaInstance @splatToken | Should -BeNullOrEmpty

            $tokenFailures = @($tokenWarnings | Where-Object { "$PSItem" -like "*Failed to get access token for Azure SQL DB (*" })
            if ($PSVersionTable.PSEdition -eq "Desktop") {
                $tokenFailures.Count | Should -Be 1
                "$($tokenFailures[0])" | Should -BeLike "*Failed to get access token for Azure SQL DB (*AADSTS*"
            } else {
                $tokenFailures.Count | Should -Be 0
                $tokenWarnings | Should -Not -BeNullOrEmpty
            }
        }
    }
}
