#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaCredential",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- The pinned function declares no SupportsShouldProcess and changes nothing; it only reads $server.Credentials.

Describe "Get-DbaCredential native" -Tag IntegrationTests {
    BeforeAll {
        $random = Get-Random
        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
        # Unique server credentials for this run (lane-safe); AfterAll drops them.
        $prefix = "dbatoolsci_cred_$($random)_"
        $nameA = $prefix + "a"
        $nameB = $prefix + "b"
        $nameC = $prefix + "c"
        $identityA = "dbatoolsci_ida_$random"
        $identityB = "dbatoolsci_idb_$random"
        $secret = "dbatools.IO-$random"
        foreach ($pair in @(@($nameA, $identityA), @($nameB, $identityB), @($nameC, $identityA))) {
            $server.ConnectionContext.ExecuteNonQuery("CREATE CREDENTIAL [$($pair[0])] WITH IDENTITY = N'$($pair[1])', SECRET = N'$secret';")
        }
        $badInstance = "TCP:127.0.0.1,1"
        $displaySet = @("ComputerName", "InstanceName", "SqlInstance", "ID", "Name", "Identity", "MappedClassType", "ProviderName")
    }

    AfterAll {
        foreach ($name in @($nameA, $nameB, $nameC)) {
            $server.ConnectionContext.ExecuteNonQuery("IF EXISTS (SELECT 1 FROM sys.credentials WHERE name = N'$name') DROP CREDENTIAL [$name];")
        }
    }

    Context "Name and identity filters" {
        It "returns the named credentials as decorated SMO credentials with the pinned default view" {
            $results = @(Get-DbaCredential -SqlInstance $server -Credential $nameA, $nameB -EnableException)
            $results.Count | Should -Be 2
            ($results.Name | Sort-Object) | Should -Be @($nameA, $nameB)
            foreach ($result in $results) {
                $result | Should -BeOfType Microsoft.SqlServer.Management.Smo.Credential
                $result.ComputerName | Should -Not -BeNullOrEmpty
                $result.InstanceName | Should -Not -BeNullOrEmpty
                $result.SqlInstance | Should -Not -BeNullOrEmpty
                @($result.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames) | Should -Be $displaySet
            }
            ($results | Where-Object Name -eq $nameA).Identity | Should -Be $identityA
        }

        It "compares names case-insensitively and binds the Name alias" {
            @(Get-DbaCredential -SqlInstance $server -Name $nameA.ToUpperInvariant() -EnableException).Name | Should -Be $nameA
        }

        It "excludes credentials by name" {
            $results = @(Get-DbaCredential -SqlInstance $server -ExcludeCredential $nameA -EnableException | Where-Object Name -like "$prefix*")
            ($results.Name | Sort-Object) | Should -Be @($nameB, $nameC)
            $results = @(Get-DbaCredential -SqlInstance $server -ExcludeName $nameB -EnableException | Where-Object Name -like "$prefix*")
            ($results.Name | Sort-Object) | Should -Be @($nameA, $nameC)
        }

        It "filters and excludes credentials by identity" {
            $results = @(Get-DbaCredential -SqlInstance $server -Identity $identityA -EnableException)
            ($results.Name | Sort-Object) | Should -Be @($nameA, $nameC)
            @(Get-DbaCredential -SqlInstance $server -CredentialIdentity $identityB -EnableException).Name | Should -Be $nameB
            $results = @(Get-DbaCredential -SqlInstance $server -ExcludeIdentity $identityA -EnableException | Where-Object Name -like "$prefix*")
            $results.Name | Should -Be $nameB
            $results = @(Get-DbaCredential -SqlInstance $server -Credential $nameA, $nameB -ExcludeCredentialIdentity $identityB -EnableException)
            $results.Name | Should -Be $nameA
        }

        It "matches -Credential wildcards, as the help documents" {
            $results = @(Get-DbaCredential -SqlInstance $server -Credential "$($prefix)*" -EnableException)
            ($results.Name | Sort-Object) | Should -Be @($nameA, $nameB, $nameC)
            $results = @(Get-DbaCredential -SqlInstance $server -Credential "$($prefix)?" -ExcludeCredential $nameC -EnableException)
            ($results.Name | Sort-Object) | Should -Be @($nameA, $nameB)
        }
    }

    Context "Several instances" {
        It "queries every piped instance, decorating the same credential again" -Tag NativeChecklist:pipeline-multiple {
            $results = @(@($server, $server) | Get-DbaCredential -Credential $nameA -EnableException)
            $results.Count | Should -Be 2
            foreach ($result in $results) {
                $result.Name | Should -Be $nameA
                $result.SqlInstance | Should -Not -BeNullOrEmpty
            }
        }

        It "warns 'Failure' for an instance it cannot connect to and still reads the next one" -Tag NativeChecklist:multi-instance-failure {
            $connectWarnings = @()
            $results = @(Get-DbaCredential -SqlInstance $badInstance, $server -Credential $nameA -WarningVariable connectWarnings -WarningAction SilentlyContinue)
            $connectWarnings.Count | Should -Be 1
            "$connectWarnings" | Should -BeLike "*Failure*"
            $results.Name | Should -Be $nameA
        }

        It "stops at the instance it cannot connect to under -EnableException, with category ConnectionError" -Tag NativeChecklist:enable-exception {
            $seen = New-Object System.Collections.ArrayList
            $connectCaught = $null
            try {
                Get-DbaCredential -SqlInstance $badInstance, $server -Credential $nameA -EnableException | ForEach-Object { $null = $seen.Add($PSItem) }
            } catch {
                $connectCaught = $PSItem
            }
            $connectCaught | Should -Not -BeNullOrEmpty
            $connectCaught.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaCredential*"
            $connectCaught.CategoryInfo.Category | Should -Be "ConnectionError"
            $seen.Count | Should -Be 0
        }

        It "warns and moves on for -EnableException:`$false" -Tag NativeChecklist:switch-false {
            $falseWarnings = @()
            $results = @(Get-DbaCredential -SqlInstance $badInstance, $server -Credential $nameA -EnableException:$false -WarningVariable falseWarnings -WarningAction SilentlyContinue)
            $falseWarnings.Count | Should -Be 1
            $results.Name | Should -Be $nameA
        }
    }

    Context "SQL login" -Tag NativeChecklist:sql-login {
        BeforeAll {
            $loginInstance = $TestConfig.InstanceSqlLogin
            $sqlLoginCred = $TestConfig.SqlLoginCred
            $loginServer = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $sqlLoginCred -EnableException
            $loginName = "dbatoolsci_credlogin_$random"
            $loginServer.ConnectionContext.ExecuteNonQuery("CREATE CREDENTIAL [$loginName] WITH IDENTITY = N'$identityA', SECRET = N'$secret';")
        }

        AfterAll {
            $loginServer.ConnectionContext.ExecuteNonQuery("IF EXISTS (SELECT 1 FROM sys.credentials WHERE name = N'$loginName') DROP CREDENTIAL [$loginName];")
        }

        # The missing-credential assertions follow the pinned code quoted below instead of a -Baseline run
        # (watchman 49f13ebb): no commit can run the pinned function, because the base already ships the compiled
        # Get-DbaCredential cmdlet and the pin predates src/ and cannot be built.
        #
        # refs/pins/dbatools-2026-10-22:public/Get-DbaCredential.ps1:113-118
        #         foreach ($instance in $SqlInstance) {
        #             try {
        #                 $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
        #             } catch {
        #                 Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
        #             }
        #
        # Without the credential the connect fails and Stop-Function -Continue warns "Failure" and moves on; under
        # -EnableException the same Stop-Function throws with category ConnectionError.
        It "works with -SqlCredential" {
            $loginWarnings = @()
            $results = @(Get-DbaCredential -SqlInstance $loginInstance -SqlCredential $sqlLoginCred -Credential $loginName -EnableException -WarningVariable loginWarnings)
            $loginWarnings.Count | Should -Be 0
            $results.Name | Should -Be $loginName
        }

        It "fails cleanly without the credential: a warning and no output" {
            $noLoginWarnings = @()
            $results = @(Get-DbaCredential -SqlInstance $loginInstance -Credential $loginName -WarningVariable noLoginWarnings -WarningAction SilentlyContinue)
            $results.Count | Should -Be 0
            ($noLoginWarnings -join " ") | Should -BeLike "*Failure*"
        }

        It "fails cleanly without the credential under -EnableException, as the pinned Stop-Function does" {
            $noLoginCaught = $null
            try {
                $null = Get-DbaCredential -SqlInstance $loginInstance -Credential $loginName -EnableException
            } catch {
                $noLoginCaught = $PSItem
            }
            $noLoginCaught | Should -Not -BeNullOrEmpty
            $noLoginCaught.CategoryInfo.Category | Should -Be "ConnectionError"
        }
    }

    Context "A failed read" {
        BeforeAll {
            # sqlwhale22 is shared: the login, its user in master and the credential are unique per leg and run.
            $faultInstance = $TestConfig.InstanceSqlLogin
            $faultServer = Connect-DbaInstance -SqlInstance $faultInstance -SqlCredential $TestConfig.SqlLoginCred -EnableException
            $deniedName = "dbatoolsci_creddeny_$random"
            $deniedPassword = "Ncr-$([guid]::NewGuid().ToString('N'))"
            $faultCredential = "dbatoolsci_credfault_$random"
            $deniedCred = New-Object System.Management.Automation.PSCredential -ArgumentList $deniedName, (ConvertTo-SecureString -String $deniedPassword -AsPlainText -Force)
            $faultServer.ConnectionContext.ExecuteNonQuery("CREATE LOGIN [$deniedName] WITH PASSWORD = N'$deniedPassword', CHECK_POLICY = OFF;")
            $null = $faultServer.Query("CREATE USER [$deniedName] FOR LOGIN [$deniedName]; DENY SELECT ON OBJECT::sys.credentials TO [$deniedName];", "master")
            $faultServer.ConnectionContext.ExecuteNonQuery("CREATE CREDENTIAL [$faultCredential] WITH IDENTITY = N'$identityA', SECRET = N'$secret';")
            $deniedServer = Connect-DbaInstance -SqlInstance $faultInstance -SqlCredential $deniedCred -EnableException
            $faultMessage = "The following exception occurred while trying to enumerate the collection: `"An exception occurred while executing a Transact-SQL statement or batch.`"."

            function Assert-NativeCredentialFault {
                param($Record)
                $Record.Exception | Should -BeOfType System.Management.Automation.ExtendedTypeSystemException
                $Record.Exception.Message | Should -BeExactly $faultMessage
                $Record.Exception.InnerException.GetType().FullName | Should -BeExactly "Microsoft.SqlServer.Management.Common.ExecutionFailureException"
                $Record.Exception.InnerException.InnerException.GetType().FullName | Should -BeExactly "Microsoft.Data.SqlClient.SqlException"
                $Record.FullyQualifiedErrorId | Should -BeLike "ExceptionInGetEnumerator*"
                $Record.CategoryInfo.Category | Should -Be "NotSpecified"
                $Record.TargetObject | Should -BeNullOrEmpty
            }

            # A Pester It runs its body inside a try, so a call outside any try needs a runspace of its own.
            function Invoke-NativeCredentialCall {
                param([hashtable]$Arguments, [object[]]$Piped, [string]$Script = 'param($Arguments, $Piped) Get-DbaCredential @Arguments | ForEach-Object { "row: " + $PSItem.Name }; "next statement"')
                $callState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
                $callType = (Get-Command Get-DbaCredential -CommandType Cmdlet).ImplementingType
                $callEntry = New-Object System.Management.Automation.Runspaces.SessionStateCmdletEntry -ArgumentList "Get-DbaCredential", $callType, $null
                $callState.Commands.Add($callEntry)
                $callRunspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($callState)
                $callShell = [System.Management.Automation.PowerShell]::Create()
                $callOutput = New-Object "System.Management.Automation.PSDataCollection[psobject]"
                $callStop = $null
                try {
                    $callRunspace.Open()
                    $callShell.Runspace = $callRunspace
                    $null = $callShell.AddScript($Script).AddArgument($Arguments).AddArgument($Piped)
                    try {
                        $null = $callShell.Invoke($null, $callOutput)
                    } catch {
                        # The stop leaves the runspace's script through Invoke, as a method call's exception.
                        $callStop = $PSItem.Exception.InnerException
                    }
                    [pscustomobject]@{
                        Output = @($callOutput | ForEach-Object { "$PSItem" })
                        Errors = @($callShell.Streams.Error)
                        Stop   = $callStop
                    }
                } finally {
                    $callShell.Dispose()
                    $callRunspace.Dispose()
                }
            }
        }

        AfterAll {
            $faultServer.ConnectionContext.ExecuteNonQuery("IF EXISTS (SELECT 1 FROM sys.credentials WHERE name = N'$faultCredential') DROP CREDENTIAL [$faultCredential];")
            $faultServer.ConnectionContext.ExecuteNonQuery("DECLARE @kill nvarchar(max) = N''; SELECT @kill += N'KILL ' + CAST(session_id AS nvarchar(10)) + N';' FROM sys.dm_exec_sessions WHERE login_name = N'$deniedName'; EXEC sys.sp_executesql @kill;")
            $null = $faultServer.Query("IF USER_ID(N'$deniedName') IS NOT NULL DROP USER [$deniedName];", "master")
            $faultServer.ConnectionContext.ExecuteNonQuery("IF SUSER_ID(N'$deniedName') IS NOT NULL DROP LOGIN [$deniedName];")
        }

        It "writes the pinned enumeration record and still reads the next instance" {
            $call = Invoke-NativeCredentialCall -Arguments @{ SqlInstance = @($deniedServer, $faultServer); Credential = $faultCredential; ExcludeIdentity = "nosuchidentity" }
            $call.Stop | Should -BeNullOrEmpty
            ($call.Output -join ",") | Should -BeExactly "row: $faultCredential,next statement"
            # One record for each active filter and one for the foreach, as a plain call of the pin writes them.
            $call.Errors.Count | Should -Be 3
            foreach ($record in $call.Errors) {
                Assert-NativeCredentialFault -Record $record
            }
        }

        It "writes one record without a filter, in input order with the rows" {
            $orderScript = 'param($Arguments, $Piped) Get-DbaCredential @Arguments 2>&1 | ForEach-Object { if ($PSItem -is [System.Management.Automation.ErrorRecord]) { "error: " + $PSItem.FullyQualifiedErrorId } else { "row: " + $PSItem.Name } }; "next statement"'
            $faultFirst = Invoke-NativeCredentialCall -Arguments @{ SqlInstance = @($deniedServer, $faultServer) } -Script $orderScript
            $faultFirst.Stop | Should -BeNullOrEmpty
            $faultFirst.Output[0] | Should -BeLike "error: ExceptionInGetEnumerator*"
            @($faultFirst.Output | Where-Object { $PSItem -like "error: *" }).Count | Should -Be 1
            @($faultFirst.Output | Where-Object { $PSItem -eq "row: $faultCredential" }).Count | Should -Be 1
            $faultFirst.Output[-1] | Should -BeExactly "next statement"

            $faultLast = Invoke-NativeCredentialCall -Arguments @{ SqlInstance = @($faultServer, $deniedServer) } -Script $orderScript
            $faultLast.Stop | Should -BeNullOrEmpty
            $faultLast.Output[-2] | Should -BeLike "error: ExceptionInGetEnumerator*"
            @($faultLast.Output | Where-Object { $PSItem -like "error: *" }).Count | Should -Be 1
            @($faultLast.Output | Where-Object { $PSItem -eq "row: $faultCredential" }).Count | Should -Be 1
            $faultLast.Output[-1] | Should -BeExactly "next statement"
        }

        It "goes on to the next piped instance" -Tag NativeChecklist:multi-instance-failure {
            $pipedScript = 'param($Arguments, $Piped) $Piped | Get-DbaCredential @Arguments | ForEach-Object { "row: " + $PSItem.Name }; "next statement"'
            $call = Invoke-NativeCredentialCall -Arguments @{ Credential = $faultCredential } -Piped @($deniedServer, $faultServer) -Script $pipedScript
            $call.Stop | Should -BeNullOrEmpty
            ($call.Output -join ",") | Should -BeExactly "row: $faultCredential,next statement"
            $call.Errors.Count | Should -Be 2
        }

        It "lets a caller's try catch the record, and the command does not go on" {
            # The pin, inside a caller's try, stops at its first fault with that one record (probe cases try-good-first and
            # try-filter, evidence/pin-credential-faults-20261101.txt, both editions).
            $tryScript = 'param($Arguments, $Piped) $before = $Error.Count; try { Get-DbaCredential @Arguments | ForEach-Object { "row: " + $PSItem.Name }; "after the call" } catch { "caught: " + $PSItem.FullyQualifiedErrorId; "message: " + $PSItem.Exception.Message }; "added: " + ($Error.Count - $before); "next statement"'
            foreach ($tryArguments in @(@{ }, @{ Credential = $faultCredential; ExcludeIdentity = "nosuchidentity" })) {
                $tryArguments.SqlInstance = @($faultServer, $deniedServer, $faultServer)
                $call = Invoke-NativeCredentialCall -Arguments $tryArguments -Script $tryScript
                $call.Stop | Should -BeNullOrEmpty
                $call.Errors.Count | Should -Be 0
                $tail = @($call.Output | Where-Object { $PSItem -notlike "row: *" })
                $tail.Count | Should -Be 4
                $tail[0] | Should -BeLike "caught: ExceptionInGetEnumerator*"
                $tail[1] | Should -BeExactly "message: $faultMessage"
                $tail[2] | Should -BeExactly "added: 1"
                $tail[3] | Should -BeExactly "next statement"
                # The first instance's rows are out; the instance after the fault is never read.
                @($call.Output | Where-Object { $PSItem -eq "row: $faultCredential" }).Count | Should -Be 1
            }
        }

        It "stops at the fault under -EnableException, keeping the rows already out" -Tag NativeChecklist:enable-exception {
            $call = Invoke-NativeCredentialCall -Arguments @{ SqlInstance = @($faultServer, $deniedServer, $faultServer); Credential = $faultCredential; EnableException = $true }
            $call.Stop | Should -BeNullOrEmpty
            $call.Errors.Count | Should -Be 1
            Assert-NativeCredentialFault -Record $call.Errors[0]
            ($call.Output -join ",") | Should -BeExactly "row: $faultCredential,next statement"
        }

        It "stops at the fault under -ErrorAction Stop, keeping the rows already out" {
            $call = Invoke-NativeCredentialCall -Arguments @{ SqlInstance = @($faultServer, $deniedServer, $faultServer); Credential = $faultCredential; ErrorAction = "Stop" }
            $call.Stop | Should -BeOfType System.Management.Automation.ActionPreferenceStopException
            Assert-NativeCredentialFault -Record $call.Stop.ErrorRecord
            ($call.Output -join ",") | Should -BeExactly "row: $faultCredential"
        }

        It "applies every filter when a later read works after a failed one" {
            # Correction recovery-filters. A blocker session holds an uncommitted CREATE CREDENTIAL for 6 s, so each read of
            # the credentials on a Server with StatementTimeout 2 times out until the release and a later read works. The pin
            # leaves each filter whose read faulted unapplied and returns credentials the caller excluded
            # (evidence/pin-credential-recovery-20261112.txt).
            $timedServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -StatementTimeout 2 -EnableException
            $blockServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -NonPooledConnection -EnableException
            $null = $blockServer.Query("SELECT 1 AS one")
            $blockConnection = $blockServer.ConnectionContext.SqlConnectionObject
            if ("$($blockConnection.State)" -ne "Open") {
                $blockConnection.Open()
            }
            $spidCommand = $blockConnection.CreateCommand()
            $spidCommand.CommandText = "SELECT @@SPID;"
            $blockSpid = [int]$spidCommand.ExecuteScalar()
            $lockName = "dbatoolsci_credlock_$random"
            $blockCommand = $blockConnection.CreateCommand()
            $blockCommand.CommandTimeout = 60
            $blockCommand.CommandText = "BEGIN TRAN; CREATE CREDENTIAL [$lockName] WITH IDENTITY = N'dbatoolsci_credlock', SECRET = N'$secret'; WAITFOR DELAY '00:00:06'; ROLLBACK TRAN;"
            $blockTask = $null
            try {
                $blockTask = $blockCommand.ExecuteNonQueryAsync()
                $held = $false
                $poll = [System.Diagnostics.Stopwatch]::StartNew()
                while (-not $held -and $poll.ElapsedMilliseconds -lt 10000 -and -not $blockTask.IsCompleted) {
                    $held = [int]($server.Query("SELECT COUNT(*) AS n FROM sys.dm_exec_requests WHERE session_id = $blockSpid AND wait_type = N'WAITFOR';").n) -eq 1
                    if (-not $held) {
                        Start-Sleep -Milliseconds 50
                    }
                }
                $held | Should -BeTrue
                $call = Invoke-NativeCredentialCall -Arguments @{ SqlInstance = $timedServer; Credential = $nameA; ExcludeCredential = "nosuchname_$random"; Identity = @($identityA, $identityB); ExcludeIdentity = "nosuchidentity_$random" }
            } finally {
                if ($blockTask) {
                    try {
                        $null = $blockTask.Wait(30000)
                    } catch {
                        $null = $PSItem
                    }
                }
                $blockServer.ConnectionContext.Disconnect()
            }
            $call.Stop | Should -BeNullOrEmpty
            # The first read timed out and a later one of the five worked.
            $call.Errors.Count | Should -BeGreaterThan 0
            $call.Errors.Count | Should -BeLessThan 5
            foreach ($record in $call.Errors) {
                $record.FullyQualifiedErrorId | Should -BeLike "ExceptionInGetEnumerator*"
            }
            ($call.Output -join ",") | Should -BeExactly "row: $nameA,next statement"
        }
    }

    Context "Azure SQL Database" -Tag NativeChecklist:azure-sqldb {
        BeforeAll {
            # Server credentials do not exist in Azure SQL Database (Microsoft Learn, "T-SQL differences between SQL
            # Server and Azure SQL Database": server credentials are not supported; use database scoped credentials).
            $azure = $null
            for ($attempt = 0; $attempt -le 6; $attempt++) {
                try {
                    $azure = Connect-DbaInstance -SqlInstance $TestConfig.AzureSqlDbServer -Database $TestConfig.AzureSqlDbName -SqlCredential $TestConfig.AzureSqlDbCred -EnableException
                    break
                } catch {
                    $azureError = $PSItem.Exception
                    $isResuming = $false
                    while ($azureError) {
                        if ($azureError.Number -in 40613, -2 -or $azureError -is [System.TimeoutException]) { $isResuming = $true }
                        $azureError = $azureError.InnerException
                    }
                    if (-not $isResuming -or $attempt -eq 6) { throw }
                    Start-Sleep -Seconds 10
                }
            }
        }

        AfterAll {
            if ($azure) { $azure.ConnectionContext.Disconnect() }
        }

        It "warns that Azure SQL Database is not supported and returns nothing" {
            $azure.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
            $azureWarnings = @()
            @(Get-DbaCredential -SqlInstance $azure -WarningAction SilentlyContinue -WarningVariable azureWarnings).Count | Should -Be 0
            ($azureWarnings -join " ") | Should -Match "Azure SQL Database not supported"
        }

        It "throws that Azure SQL Database is not supported under -EnableException" {
            $azure.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
            { Get-DbaCredential -SqlInstance $azure -EnableException } | Should -Throw "*Azure SQL Database not supported*"
        }
    }
}
