#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Connect-DbaInstance",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

BeforeDiscovery {
    $script:hasCredentialSspiProvider = $null -ne ("Dataplat.Dbatools.Connection.NetworkCredentialSspiContextProvider" -as [type])
}

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
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
                "DisableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Validate alias" {
        It "Should contain the alias: cdi" {
            (Get-Alias cdi) | Should -Not -BeNullOrEmpty
        }
    }

    Context "Failover partner retry behavior" {
        BeforeAll {
            function New-MockConnectionContext {
                param(
                    [string]$ConnectionString,
                    [string[]]$AttemptErrors
                )

                $sqlConnectionObject = [PSCustomObject]@{
                    ConnectionString = $ConnectionString
                }

                $connectionContext = [PSCustomObject]@{
                    ConnectionString    = $ConnectionString
                    SqlConnectionObject = $sqlConnectionObject
                    AttemptErrors       = $AttemptErrors
                    AttemptCount        = 0
                    StatementTimeout    = 0
                }

                Add-Member -InputObject $connectionContext -Name ExecuteWithResults -MemberType ScriptMethod -Value {
                    param($Query)
                    $this.AttemptCount++
                    $this.ConnectionString = $this.SqlConnectionObject.ConnectionString
                    $attemptIndex = $this.AttemptCount - 1
                    if ($attemptIndex -lt $this.AttemptErrors.Count -and $this.AttemptErrors[$attemptIndex]) {
                        throw (New-Object -TypeName System.Exception -ArgumentList $this.AttemptErrors[$attemptIndex])
                    }
                } -Force

                $connectionContext
            }

            function New-MockServer {
                param(
                    [string]$ConnectionString,
                    [string[]]$AttemptErrors
                )

                [PSCustomObject]@{
                    ConnectionContext = New-MockConnectionContext -ConnectionString $ConnectionString -AttemptErrors $AttemptErrors
                }
            }

            Mock Add-ConnectionHashValue { } -ModuleName dbatools
            Mock New-Object { & (Get-Command -Name 'New-Object' -CommandType Cmdlet) @PesterBoundParameters } -ModuleName dbatools
            Mock New-Object {
                [PSCustomObject]@{ }
            } -ModuleName dbatools -ParameterFilter {
                $TypeName -eq "Microsoft.SqlServer.Management.Common.ServerConnection"
            }
            Mock New-Object {
                New-MockServer -ConnectionString $script:mockConnectionString -AttemptErrors $script:attemptErrors
            } -ModuleName dbatools -ParameterFilter {
                $TypeName -eq "Microsoft.SqlServer.Management.Smo.Server"
            }
        }

        It "retries connection string inputs when failover partner requires Initial Catalog" {
            $script:mockConnectionString = "Data Source=sqlmirror;Integrated Security=True;Failover Partner=mirrorpartner"
            $script:attemptErrors = @(
                "Use of key 'Failover Partner' requires the key 'Initial Catalog' to be present."
            )

            $result = Connect-DbaInstance -SqlInstance $script:mockConnectionString -SqlConnectionOnly

            $result.ConnectionString | Should -Match "Initial Catalog=master"
        }

        It "retries with Initial Catalog after a trust certificate retry exposes the failover partner requirement" {
            $script:mockConnectionString = "Data Source=sqlmirror;Integrated Security=True;FailoverPartner=mirrorpartner;Trust Server Certificate=False"
            $script:attemptErrors = @(
                "The certificate chain was issued by an authority that is not trusted.",
                "Use of key 'Failover Partner' requires the key 'Initial Catalog' to be present."
            )

            $result = Connect-DbaInstance -SqlInstance "sqlmirror" -FailoverPartner "mirrorpartner" -AllowTrustServerCertificate -TrustServerCertificate:$false -SqlConnectionOnly

            $result.ConnectionString | Should -Match "Trust Server Certificate=True"
            $result.ConnectionString | Should -Match "Initial Catalog=master"
        }
    }

    Context "Access token connection behavior" {
        BeforeAll {
            function New-MockAccessTokenServer {
                $sqlConnectionObject = [PSCustomObject]@{
                    ConnectionString = "Data Source=sqltoken;Integrated Security=True"
                }
                $connectionContext = [PSCustomObject]@{
                    ConnectionString    = $sqlConnectionObject.ConnectionString
                    SqlConnectionObject = $sqlConnectionObject
                    StatementTimeout    = 0
                }

                Add-Member -InputObject $connectionContext -Name NonPooledConnection -MemberType ScriptProperty -Value {
                    $true
                } -SecondValue {
                    param($value)
                    $script:nonPooledConnectionSetterCalls++
                    throw "Property NonPooledConnection cannot be changed or read after a connection string has been set."
                } -Force

                Add-Member -InputObject $connectionContext -Name ExecuteWithResults -MemberType ScriptMethod -Value {
                    param($Query)
                } -Force

                [PSCustomObject]@{
                    ConnectionContext = $connectionContext
                }
            }

            Mock Add-ConnectionHashValue { } -ModuleName dbatools
            Mock New-Object { & (Get-Command -Name 'New-Object' -CommandType Cmdlet) @PesterBoundParameters } -ModuleName dbatools
            Mock New-Object {
                [PSCustomObject]@{
                    ConnectionString = "Data Source=sqltoken;Integrated Security=True"
                    AccessToken      = $null
                }
            } -ModuleName dbatools -ParameterFilter {
                $TypeName -eq "Microsoft.Data.SqlClient.SqlConnection"
            }
            Mock New-Object {
                [PSCustomObject]@{ }
            } -ModuleName dbatools -ParameterFilter {
                $TypeName -eq "Microsoft.SqlServer.Management.Common.ServerConnection"
            }
            Mock New-Object {
                New-MockAccessTokenServer
            } -ModuleName dbatools -ParameterFilter {
                $TypeName -eq "Microsoft.SqlServer.Management.Smo.Server"
            }
        }

        It "does not reapply NonPooledConnection when AccessToken already uses a SqlConnection" {
            $script:nonPooledConnectionSetterCalls = 0

            $result = Connect-DbaInstance -SqlInstance "sqltoken" -AccessToken "token" -NonPooledConnection -SqlConnectionOnly

            $result.ConnectionString | Should -Be "Data Source=sqltoken;Integrated Security=True"
            $script:nonPooledConnectionSetterCalls | Should -Be 0
        }
    }

    Context "AuthenticationType behavior" {
        BeforeAll {
            function New-MockAuthenticationServer {
                param(
                    $ServerConnection
                )

                if ($ServerConnection.SqlConnectionObject) {
                    $sqlConnectionObject = $ServerConnection.SqlConnectionObject
                } else {
                    $sqlConnectionObject = [PSCustomObject]@{
                        ConnectionString = $ServerConnection.ConnectionString
                    }
                }
                $connectionContext = [PSCustomObject]@{
                    ConnectionString    = $sqlConnectionObject.ConnectionString
                    SqlConnectionObject = $sqlConnectionObject
                    StatementTimeout    = 0
                }

                Add-Member -InputObject $connectionContext -Name ExecuteWithResults -MemberType ScriptMethod -Value {
                    param($Query)
                } -Force

                [PSCustomObject]@{
                    ConnectionContext = $connectionContext
                }
            }

            Mock Add-ConnectionHashValue { } -ModuleName dbatools
            Mock New-Object { & (Get-Command -Name 'New-Object' -CommandType Cmdlet) @PesterBoundParameters } -ModuleName dbatools
            Mock New-Object {
                $sqlConnectionObject = if ($ArgumentList[0] -is [Microsoft.Data.SqlClient.SqlConnection]) {
                    $ArgumentList[0]
                } else {
                    $null
                }
                $script:lastServerConnection = [PSCustomObject]@{
                    ConnectionString      = $ArgumentList[0].ConnectionString
                    SqlConnectionObject   = $sqlConnectionObject
                    ConnectAsUser         = $false
                    ConnectAsUserName     = $null
                    ConnectAsUserPassword = $null
                }
                $script:lastServerConnection
            } -ModuleName dbatools -ParameterFilter {
                $TypeName -eq "Microsoft.SqlServer.Management.Common.ServerConnection"
            }
            Mock New-Object {
                New-MockAuthenticationServer -ServerConnection $ArgumentList[0]
            } -ModuleName dbatools -ParameterFilter {
                $TypeName -eq "Microsoft.SqlServer.Management.Smo.Server"
            }
        }

        It "requires SqlCredential when AuthenticationType uses password-based auth" {
            Mock Stop-Function { } -ModuleName dbatools

            Connect-DbaInstance -SqlInstance "sqlauth" -AuthenticationType ActiveDirectoryPassword | Should -BeNullOrEmpty

            Should -Invoke Stop-Function -Times 1 -Exactly -ModuleName dbatools
        }

        It "uses SqlConnectionInfo credentials for ActiveDirectoryPassword on non-Azure servers" {
            $securePassword = ConvertTo-SecureString "password" -AsPlainText -Force
            $credential = New-Object System.Management.Automation.PSCredential ("user@contoso.com", $securePassword)

            $result = Connect-DbaInstance -SqlInstance "sqlauth" -SqlCredential $credential -AuthenticationType ActiveDirectoryPassword -SqlConnectionOnly

            $result.ConnectionString | Should -Match "Authentication=ActiveDirectoryPassword"
            $result.ConnectionString | Should -Match "User ID=user@contoso.com"
            $result.ConnectionString | Should -Not -Match "Integrated Security=True"
            $script:lastServerConnection.ConnectAsUser | Should -Be $false
            $script:lastServerConnection.ConnectAsUserName | Should -BeNullOrEmpty
        }

        It "uses the SqlClient SSPI provider for explicit Windows credentials" -Skip:(-not $script:hasCredentialSspiProvider) {
            $splatPassword = @{
                String      = "password"
                AsPlainText = $true
                Force       = $true
            }
            $securePassword = ConvertTo-SecureString @splatPassword
            $credential = New-Object System.Management.Automation.PSCredential ("CONTOSO\user", $securePassword)
            $splatConnect = @{
                SqlInstance       = "sqlauth"
                SqlCredential     = $credential
                SqlConnectionOnly = $true
            }

            $result = Connect-DbaInstance @splatConnect

            $result.SspiContextProvider | Should -BeOfType Dataplat.Dbatools.Connection.NetworkCredentialSspiContextProvider
            $script:lastServerConnection.ConnectAsUser | Should -Be $false
            $script:lastServerConnection.ConnectAsUserName | Should -BeNullOrEmpty
            Should -Invoke Add-ConnectionHashValue -Times 0 -Exactly -ModuleName dbatools
        }

        It "uses SMO impersonation when the SqlClient SSPI provider is unavailable" -Skip:$script:hasCredentialSspiProvider {
            $splatPassword = @{
                String      = "password"
                AsPlainText = $true
                Force       = $true
            }
            $securePassword = ConvertTo-SecureString @splatPassword
            $credential = New-Object System.Management.Automation.PSCredential ("user@CONTOSO", $securePassword)
            $splatConnect = @{
                SqlInstance       = "sqlauth"
                SqlCredential     = $credential
                SqlConnectionOnly = $true
            }

            $null = Connect-DbaInstance @splatConnect

            $script:lastServerConnection.ConnectAsUser | Should -Be $true
            $script:lastServerConnection.ConnectAsUserName | Should -Be "user@CONTOSO"
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    AfterAll {
        $null = Get-DbaConnectedInstance | Disconnect-DbaInstance
        Clear-DbaConnectionPool
    }

    if ($env:azuredbpasswd -eq "failstoooften") {
        Context "Connect to Azure" {
            BeforeAll {
                $securePassword = ConvertTo-SecureString $env:azuredbpasswd -AsPlainText -Force
                $cred = New-Object System.Management.Automation.PSCredential ($TestConfig.azuresqldblogin, $securePassword)
            }

            It "Should login to Azure" {
                $s = Connect-DbaInstance -SqlInstance psdbatools.database.windows.net -SqlCredential $cred -Database test
                $s.Name | Should -match "psdbatools.database.windows.net"
                $s.DatabaseEngineType | Should -Be "SqlAzureDatabase"
            }

            It "Should keep the same database context" {
                $s = Connect-DbaInstance -SqlInstance psdbatools.database.windows.net -SqlCredential $cred -Database test
                $results = Invoke-DbaQuery -SqlInstance $s -Query "select db_name() as dbname"
                $results.dbname | Should -Be "test"
            }

            It "Should keep the same database context again" {
                $s = Connect-DbaInstance -SqlInstance psdbatools.database.windows.net -SqlCredential $cred -Database test
                $results = Invoke-DbaQuery -SqlInstance $s -Query "select db_name() as dbname"
                $results.dbname | Should -Be "test"
                $results = Invoke-DbaQuery -SqlInstance $s -Query "select db_name() as dbname"
                $results.dbname | Should -Be "test"
            }

            It "Should keep the same database context" {
                $s = Connect-DbaInstance -SqlInstance psdbatools.database.windows.net -SqlCredential $cred -Database test
                $server = Connect-DbaInstance -SqlInstance $s
                $server.Query("select db_name() as dbname").dbname | Should -Be "test"
            }
        }
    }

    Context "connection is properly made using a string" {
        BeforeAll {
            $params = @{
                BatchSeparator           = "GO"
                ConnectTimeout           = 1
                Database                 = "tempdb"
                LockTimeout              = 1
                MaxPoolSize              = 20
                MinPoolSize              = 1
                NetworkProtocol          = "TcpIp"
                PacketSize               = 4096
                PooledConnectionLifetime = 600
                WorkstationId            = "MadeUpServer"
                SqlExecutionModes        = "ExecuteSql"
                StatementTimeout         = 0
                ApplicationIntent        = "ReadOnly"
            }
            $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti1 @params
        }

        It "returns the proper name" {
            $server.Name | Should -Be $TestConfig.InstanceMulti1
        }

        It "sets connectioncontext parameters that are provided" {
            foreach ($param in $params.GetEnumerator()) {
                if ($param.Key -eq "Database") {
                    $propName = "DatabaseName"
                } else {
                    $propName = $param.Key
                }
                $server.ConnectionContext.PSObject.Properties[$propName].Value | Should -Be $param.Value
            }
        }

        It "returns more than one database" {
            $server.Databases.Name.Count | Should -BeGreaterThan 1
        }

        It "returns the connection with ApplicationIntent of ReadOnly" {
            $server.ConnectionContext.ConnectionString | Should -Match "Intent=ReadOnly"
        }

        It "keeps the same database context" {
            $null = $server.Databases["msdb"].Tables.Count
            $server.ConnectionContext.ExecuteScalar("select db_name()") | Should -Be "tempdb"
        }

        It "sets StatementTimeout to 0" {
            $server.ConnectionContext.StatementTimeout | Should -Be 0
        }
    }

    Context "IsNewConnectionVariable tells the caller whether a connection was opened" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # We predefine the variables so that a test fails if Connect-DbaInstance does not set them at all.
            $newFromString = $null
            $newFromServer = $null
            $newFromCopy = $null

            $serverFromString = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti1 -NonPooledConnection -IsNewConnectionReference ([ref]$newFromString)
            $serverFromServer = Connect-DbaInstance -SqlInstance $serverFromString -IsNewConnectionReference ([ref]$newFromServer)
            # Asking for a different database forces Connect-DbaInstance to copy the connection context, so this is a new connection.
            $serverFromCopy = Connect-DbaInstance -SqlInstance $serverFromString -Database tempdb -IsNewConnectionReference ([ref]$newFromCopy)

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $null = $serverFromString, $serverFromCopy | Disconnect-DbaInstance
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "is true when the connection is opened from a string" {
            $newFromString | Should -BeTrue
        }

        It "is false when the server object is passed back in" {
            $newFromServer | Should -BeFalse
        }

        It "returns the object that was passed in when nothing has to change" {
            [object]::ReferenceEquals($serverFromServer, $serverFromString) | Should -BeTrue
        }

        It "is true when the connection context has to be copied" {
            $newFromCopy | Should -BeTrue
        }
    }

    Context "connection is properly made using a connection string" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance "Data Source=$($TestConfig.InstanceMulti1);Initial Catalog=tempdb;Integrated Security=True"
        }

        It "returns the proper name" {
            $server.Name | Should -Be $TestConfig.InstanceMulti1
        }

        It "returns more than one database" {
            $server.Databases.Name.Count | Should -BeGreaterThan 1
        }

        It "keeps the same database context" {
            # Before #8962 this changed the context to msdb
            $null = $server.Databases["msdb"].Tables.Count
            $server.ConnectionContext.ExecuteScalar("select db_name()") | Should -Be "tempdb"
        }
    }

    if ($TestConfig.InstanceMulti1 -match "localhost") {
        Context "connection is properly made using a dot" {
            BeforeAll {
                $newinstance = $TestConfig.InstanceMulti1.Replace("localhost", ".")
                $server = Connect-DbaInstance -SqlInstance $newinstance
            }

            It "returns the proper name" {
                $server.Name | Should -Be "NP:$newinstance"
            }

            It "returns more than one database" {
                $server.Databases.Name.Count | Should -BeGreaterThan 1
            }

            It "keeps the same database context" {
                $null = $server.Databases["msdb"].Tables.Count
                # This currently fails!
                #$server.ConnectionContext.ExecuteScalar("select db_name()") | Should -Be "tempdb"
            }
        }
    }

    Context "connection is properly made using a connection object" {
        BeforeAll {
            Set-DbatoolsConfig -FullName commands.connect-dbainstance.smo.computername.source -Value "instance.ComputerName"
            [Microsoft.Data.SqlClient.SqlConnection]$sqlconnection = "Data Source=$($TestConfig.InstanceMulti1);Initial Catalog=tempdb;Integrated Security=True;Encrypt=False;Trust Server Certificate=True"
            $server = Connect-DbaInstance -SqlInstance $sqlconnection
            Set-DbatoolsConfig -FullName commands.connect-dbainstance.smo.computername.source -Value $null
        }

        It "returns the proper name" {
            $server.Name | Should -Be $TestConfig.InstanceMulti1
        }

        It "returns more than one database" {
            $server.Databases.Name.Count | Should -BeGreaterThan 1
        }

        It "keeps the same database context" {
            $null = $server.Databases["msdb"].Tables.Count
            # This currently fails!
            #$server.ConnectionContext.ExecuteScalar("select db_name()") | Should -Be "tempdb"
        }
    }

    Context "connection is properly cloned from an existing connection" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti1
        }

        AfterAll {
            $null = $server | Disconnect-DbaInstance
        }

        It "clones when using parameter Database" {
            $serverClone = Connect-DbaInstance -SqlInstance $server -Database tempdb
            $server.ConnectionContext.ExecuteScalar("select db_name()") | Should -Be "master"
            $serverClone.ConnectionContext.ExecuteScalar("select db_name()") | Should -Be "tempdb"
        }

        It "clones when using parameter ApplicationIntent" {
            $serverClone = Connect-DbaInstance -SqlInstance $server -ApplicationIntent ReadOnly
            $server.ConnectionContext.ApplicationIntent | Should -BeNullOrEmpty
            $serverClone.ConnectionContext.ApplicationIntent | Should -Be "ReadOnly"
        }

        It "clones when using parameter NonPooledConnection" {
            $serverClone = Connect-DbaInstance -SqlInstance $server -NonPooledConnection
            $server.ConnectionContext.NonPooledConnection | Should -Be $false
            $serverClone.ConnectionContext.NonPooledConnection | Should -Be $true
        }

        It "clones when using parameter StatementTimeout" {
            $serverClone = Connect-DbaInstance -SqlInstance $server -StatementTimeout 123
            $server.ConnectionContext.StatementTimeout | Should -Be (Get-DbatoolsConfigValue -FullName "sql.execution.timeout")
            $serverClone.ConnectionContext.StatementTimeout | Should -Be 123
        }

        It "clones when using parameter DedicatedAdminConnection" {
            $serverClone = Connect-DbaInstance -SqlInstance $server -DedicatedAdminConnection
            $server.ConnectionContext.ServerInstance | Should -Not -Match "^ADMIN:"
            $serverClone.ConnectionContext.ServerInstance | Should -Match "^ADMIN:"
            $null = $serverClone | Disconnect-DbaInstance
        }

        It "clones when using Backup-DabInstace" {
            $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti1 -Database tempdb
            # The backups have to go to the shared temp folder. Without a path they land in the default
            # backup folder of the instance, which is a path on the SQL Server, so the Remove-Item below
            # runs against a path that does not exist on the machine running the tests and silently does
            # nothing. The backup was then left behind on every remote instance, and because this file
            # runs early in the suite, every later test file reported it as a leftover of its own.
            $results = Backup-DbaDatabase -SqlInstance $server -Database msdb -Path $TestConfig.Temp
            if ($results.FullName) {
                Remove-Item -Path $results.FullName -ErrorAction SilentlyContinue
            }

            $results = Backup-DbaDatabase -SqlInstance $server -Database msdb -Path $TestConfig.Temp -WarningVariable warn
            $warn | Should -BeNullOrEmpty

            if ($results.FullName) {
                Remove-Item -Path $results.FullName -ErrorAction SilentlyContinue
            }
        }
    }

    Context "multiple connections are properly made using strings" {
        It "returns the proper names" {
            $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2
            $server[0].Name | Should -Be $TestConfig.InstanceMulti1
            $server[1].Name | Should -Be $TestConfig.InstanceMulti2
        }
    }

    Context "multiple dedicated admin connections are properly made using strings" {
        It "opens and closes the connections" {
            $instance1 = [DbaInstanceParameter]$TestConfig.InstanceMulti1
            if ($instance1.IsLocalHost) {
                if ($instance1.InstanceName -ne 'MSSQLSERVER') {
                    $name1 = "ADMIN:localhost\$($instance1.InstanceName)"
                } else {
                    $name1 = "ADMIN:localhost"
                }
            } else {
                $name1 = 'ADMIN:' + $instance1.FullName
            }
            $instance2 = [DbaInstanceParameter]$TestConfig.InstanceMulti2
            if ($instance2.IsLocalHost) {
                if ($instance2.InstanceName -ne 'MSSQLSERVER') {
                    $name2 = "ADMIN:localhost\$($instance2.InstanceName)"
                } else {
                    $name2 = "ADMIN:localhost"
                }
            } else {
                $name2 = 'ADMIN:' + $instance2.FullName
            }
            $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2 -DedicatedAdminConnection
            $server[0].Name | Should -Be $name1
            $server[1].Name | Should -Be $name2
            $null = $server | Disconnect-DbaInstance
            # DAC is not reopened in the background
            Start-Sleep -Seconds 10
            $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2 -DedicatedAdminConnection
            $server.Count | Should -Be 2
            $null = $server | Disconnect-DbaInstance
        }
    }

    Context "MinimumVersion decides based on a version it can read" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $versionServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti1
            $smoVersionMajor = $versionServer.VersionMajor
            $connectionVersionMajor = $versionServer.ConnectionContext.ServerVersion.Major
            $productVersionQuery = @"
SELECT SERVERPROPERTY('ProductVersion')
"@
            $tsqlVersionMajor = [int](($versionServer.ConnectionContext.ExecuteScalar($productVersionQuery) -split "\.")[0])

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "returns the connection when the instance meets the minimum" {
            $result = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti1 -MinimumVersion $smoVersionMajor
            $result.VersionMajor | Should -Be $smoVersionMajor
        }

        It "refuses the connection when the instance is below the minimum" {
            { Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti1 -MinimumVersion ($smoVersionMajor + 1) } | Should -Throw "*SQL Server version $($smoVersionMajor + 1) required*"
        }

        It "warns instead of throwing when exceptions are disabled" {
            $splatTooNew = @{
                SqlInstance      = $TestConfig.InstanceMulti1
                MinimumVersion   = $smoVersionMajor + 1
                DisableException = $true
                WarningVariable  = "minimumVersionWarning"
                WarningAction    = "SilentlyContinue"
            }
            $result = Connect-DbaInstance @splatTooNew
            $result | Should -BeNullOrEmpty
            $minimumVersionWarning | Should -Match "SQL Server version $($smoVersionMajor + 1) required"
        }

        It "can read the same major version from the connection as from SMO" {
            # The check falls back to ConnectionContext.ServerVersion where SMO cannot serve
            # VersionMajor, which is every instance below SQL Server 2008. No instance in the
            # matrix is that old, so this guards the fallback source instead: if it ever stops
            # agreeing with SMO, the fallback stops refusing the versions it exists to refuse.
            $connectionVersionMajor | Should -Be $smoVersionMajor
        }

        It "can read the same major version from T-SQL as from SMO" {
            # The last fallback, and the only one proven to answer on SQL Server 2005, where both
            # properties above come back empty. Guarded here for the same reason: the versions it
            # exists to refuse are not in the matrix, but its source is readable everywhere.
            $tsqlVersionMajor | Should -Be $smoVersionMajor
        }
    }
}
