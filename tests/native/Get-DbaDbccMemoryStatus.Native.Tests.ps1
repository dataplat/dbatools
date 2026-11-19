#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaDbccMemoryStatus",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- The pinned command has no SupportsShouldProcess, WhatIf or Confirm parameters; it only reads DBCC MEMORYSTATUS.

Describe "Native Get-DbaDbccMemoryStatus" -Tag IntegrationTests {
    BeforeAll {
        $instance = $TestConfig.InstanceSingle
        # The fixture's connection is never given to the command.
        $server = Connect-DbaInstance -SqlInstance $instance -NonPooledConnection -EnableException
    }

    AfterAll {
        $server.ConnectionContext.Disconnect()
    }

    Context "Output" {
        It "returns one plain object per row of every result set, with the pinned properties in their order and the sections DBCC MEMORYSTATUS names" {
            $engine = $server.Databases["master"].ExecuteWithResults("DBCC MEMORYSTATUS").Tables
            $result = @(Get-DbaDbccMemoryStatus -SqlInstance $instance)

            $result.Count | Should -BeGreaterThan 0
            $result[0].PSObject.TypeNames[0] | Should -BeExactly "System.Management.Automation.PSCustomObject"
            $result[0].PSObject.Properties.Name | Should -BeExactly @("ComputerName", "InstanceName", "SqlInstance", "RecordSet", "RowId", "RecordSetId", "Type", "Name", "Value", "ValueType")
            $result[0].ComputerName | Should -BeExactly $server.ComputerName
            $result[0].InstanceName | Should -BeExactly $server.ServiceName
            $result[0].SqlInstance | Should -BeExactly $server.DomainInstanceName

            # A live memory report can move between two reads, so only what does not move is compared with the independent read.
            $result[0].Type | Should -BeExactly $engine[0].Columns[0].ColumnName
            $result[0].ValueType | Should -BeExactly $engine[0].Columns[1].ColumnName
            $result[0].Name | Should -BeExactly $engine[0].Rows[0][0]
            $result[0].Name | Should -BeOfType [string]
            $result[0].Value.GetType().FullName | Should -BeExactly $engine[0].Rows[0][1].GetType().FullName
            $result[-1].Type | Should -BeExactly $engine[$engine.Count - 1].Columns[0].ColumnName
            $result[-1].ValueType | Should -BeExactly $engine[$engine.Count - 1].Columns[1].ColumnName
        }

        It "counts rows across the result sets, and rows and result sets from one" {
            $result = @(Get-DbaDbccMemoryStatus -SqlInstance $instance)
            $result[0].RecordSet | Should -BeOfType [int]
            $result[0].RowId | Should -BeOfType [int]
            $result[0].RecordSetId | Should -BeOfType [int]
            @($result.RowId) -join "," | Should -BeExactly ((1..$result.Count) -join ",")

            $result[0].RecordSet | Should -Be 1
            $result[-1].RecordSet | Should -BeGreaterThan 1
            foreach ($group in @($result | Group-Object -Property RecordSet)) {
                @($group.Group.RecordSetId) -join "," | Should -BeExactly ((1..$group.Count) -join ",")
                @($group.Group.Type | Select-Object -Unique).Count | Should -Be 1
                @($group.Group.ValueType | Select-Object -Unique).Count | Should -Be 1
            }
        }

        It "leaves the caller's connection in its database" {
            $caller = Connect-DbaInstance -SqlInstance $instance -NonPooledConnection -EnableException
            try {
                $null = $caller.ConnectionContext.ExecuteNonQuery("USE [tempdb];")
                @(Get-DbaDbccMemoryStatus -SqlInstance $caller).Count | Should -BeGreaterThan 0
                $caller.ConnectionContext.ExecuteScalar("SELECT DB_NAME();") | Should -BeExactly "tempdb"
            } finally {
                $caller.ConnectionContext.Disconnect()
            }
        }
    }

    Context "Instances" {
        It "reads each piped instance and starts its counters again" -Tag "NativeChecklist:pipeline-multiple" {
            $result = @($instance, $instance | Get-DbaDbccMemoryStatus)
            @($result | Where-Object RowId -eq 1).Count | Should -Be 2
        }

        It "warns of a failed instance and goes on, and throws it under -EnableException" -Tag "NativeChecklist:multi-instance-failure", "NativeChecklist:enable-exception", "NativeChecklist:switch-false" {
            $result = @(Get-DbaDbccMemoryStatus -SqlInstance "127.0.0.1,1", $instance -EnableException:$false -WarningVariable warnings -WarningAction SilentlyContinue)
            $result.Count | Should -BeGreaterThan 0
            @($warnings).Count | Should -Be 1
            "$($warnings[0])" | Should -Match "\[Get-DbaDbccMemoryStatus\] Failure \| Error connecting to \[[^\]]*127\.0\.0\.1,1[^\]]*\]: .*refused"

            { Get-DbaDbccMemoryStatus -SqlInstance "127.0.0.1,1", $instance -EnableException } | Should -Throw -ExpectedMessage "*refused*" -ErrorId "dbatools_Get-DbaDbccMemoryStatus*"
        }

        # The one connect warning line under -EnableException: harness-edits.md, "Script-scope preferences and the one-line connect warning", points 5 and 6.
        It "keeps that one line in -WarningVariable under -EnableException, and the caught record is the server's own message" -Tag "NativeChecklist:enable-exception" {
            $caught = $null
            $warnings = $null
            try {
                $null = Get-DbaDbccMemoryStatus -SqlInstance "127.0.0.1,1" -EnableException -WarningVariable warnings -WarningAction SilentlyContinue
            } catch {
                $caught = $PSItem
            }
            @($warnings).Count | Should -Be 1
            "$($warnings[0])" | Should -Match "\[Get-DbaDbccMemoryStatus\] Failure \| Error connecting to \[[^\]]*127\.0\.0\.1,1[^\]]*\]: .*refused"
            $caught.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaDbccMemoryStatus*"
            $caught.Exception.Message | Should -Not -BeLike "*Error connecting to*"
        }
    }
}

Describe "Native Get-DbaDbccMemoryStatus on Azure SQL Database" -Tag IntegrationTests {
    BeforeAll {
        $azureDatabase = $TestConfig.AzureSqlDbName
        $splatAzureConnection = @{
            SqlInstance     = $TestConfig.AzureSqlDbServer
            Database        = $azureDatabase
            SqlCredential   = $TestConfig.AzureSqlDbCred
            EnableException = $true
        }
        $azureServer = $null
        for ($attempt = 0; $attempt -le 6; $attempt++) {
            try {
                $azureServer = Connect-DbaInstance @splatAzureConnection
                break
            } catch {
                # A paused serverless database answers 40613 or times out (-2) while it resumes, and the lab's mobile
                # internet can drop a name lookup (11001, "No such host is known").
                $azureError = $PSItem.Exception
                $isResuming = $false
                while ($azureError) {
                    if ($azureError.Number -in 40613, -2, 11001) { $isResuming = $true }
                    $azureError = $azureError.InnerException
                }
                if (-not $isResuming -or $attempt -eq 6) { throw }
                Start-Sleep -Seconds 10
            }
        }
    }

    # Read-only. As the pin measured on both editions: evidence/pin-memorystatus-20261103.txt, azure-to-database and azure-by-name.
    It "returns the report, connected to a database and by name, and leaves the connection in its database" -Tag "NativeChecklist:azure-sqldb" {
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $engine = $azureServer.Databases["master"].ExecuteWithResults("DBCC MEMORYSTATUS").Tables

        $result = @(Get-DbaDbccMemoryStatus -SqlInstance $azureServer -WarningVariable warnings -WarningAction SilentlyContinue)
        $warnings | Should -BeNullOrEmpty
        $result.Count | Should -BeGreaterThan 0
        $result[0].Type | Should -BeExactly $engine[0].Columns[0].ColumnName
        $result[0].ValueType | Should -BeExactly $engine[0].Columns[1].ColumnName
        $result[0].ComputerName | Should -BeExactly $azureServer.ComputerName
        $result[0].SqlInstance | Should -BeExactly $azureServer.DomainInstanceName
        $azureServer.ConnectionContext.CurrentDatabase | Should -BeExactly $azureDatabase

        $byName = @(Get-DbaDbccMemoryStatus -SqlInstance $TestConfig.AzureSqlDbServer -SqlCredential $TestConfig.AzureSqlDbCred -WarningVariable warnings -WarningAction SilentlyContinue)
        $warnings | Should -BeNullOrEmpty
        $byName.Count | Should -BeGreaterThan 0
    }
}

# Measured on the pin, both editions: evidence/pin-memorystatus-20261103.txt. A login that is not sysadmin runs as guest in master and may not run the DBCC, so these
# forms have no rows, with or without VIEW SERVER STATE.
Describe "Native Get-DbaDbccMemoryStatus over SQL authentication" -Tag IntegrationTests {
    BeforeAll {
        $loginInstance = $TestConfig.InstanceSqlLogin
        $loginCred = $TestConfig.SqlLoginCred
        # Unique per leg and run: the instance is shared.
        $stamp = Get-Random
        $homeName = "dbatoolsci_nms_home_$stamp"
        $lowName = "dbatoolsci_nms_low_$stamp"
        $lowPassword = "Nms-$([guid]::NewGuid().ToString('N'))"
        $lowCred = New-Object System.Management.Automation.PSCredential -ArgumentList $lowName, (ConvertTo-SecureString -String $lowPassword -AsPlainText -Force)
        $denied = "Execute with results failed for Database 'master'. An exception occurred while executing a Transact-SQL statement or batch.User 'guest' does not have permission to run DBCC MEMORYSTATUS."
        $restoreWarning = "The database context could not be restored to [$homeName]: Exception calling ""ExecuteNonQuery"" with ""1"" argument(s): ""An exception occurred while executing a Transact-SQL statement or batch."""
        $emptyFault = "Exception calling ""query"" with ""3"" argument(s): """""
        $loginServer = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $loginCred -EnableException
        $null = $loginServer.Query("CREATE DATABASE [$homeName];")
        $null = $loginServer.Query("CREATE LOGIN [$lowName] WITH PASSWORD = '$lowPassword', CHECK_POLICY = OFF;")
        $loginServer.Databases.Refresh()
        $null = $loginServer.Databases[$homeName].ExecuteNonQuery("CREATE USER [$lowName] FOR LOGIN [$lowName];")

        # A fresh connection of the low login in the home database. -Deny denies CONNECT there afterwards; -ReadMaster reads the master object first.
        function New-LowCaller {
            param([switch]$Deny, [switch]$ReadMaster)
            $null = $loginServer.Databases[$homeName].ExecuteNonQuery("GRANT CONNECT TO [$lowName];")
            $caller = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $lowCred -Database $homeName -NonPooledConnection -EnableException
            $null = $caller.ConnectionContext.ExecuteScalar("SELECT 1;")
            if ($ReadMaster) {
                $null = $caller.Databases["master"].Name
            }
            if ($Deny) {
                $null = $loginServer.Databases[$homeName].ExecuteNonQuery("DENY CONNECT TO [$lowName];")
            }
            $caller
        }

        # The session does not feel a DENY at one fixed step. In Get-DbaDbVirtualLogFile's red 20261103T0219026629709Z one call of 72 on this shared instance showed no sign of
        # it. In this command's result 20261103T0300241982607Z one call on 2017 5.1 failed earlier, with the server's "not able to access the database" as its message, most
        # likely at the connection step's own SELECT. Why it varies is not measured. So this takes a fresh connection and tries again, at most six times, until the call shows
        # the state its test is about, and the tests assert that call. A port that never reaches that state still fails them, on the last try.
        function Invoke-OnDeniedCaller {
            param([switch]$ReadMaster, [switch]$EnableException)
            $ending = if ($ReadMaster) { $restoreWarning } else { $emptyFault }
            for ($attempt = 1; $attempt -le 6; $attempt++) {
                $caller = New-LowCaller -Deny -ReadMaster:$ReadMaster
                $all = New-Object System.Collections.ArrayList
                $record = $null
                try {
                    Get-DbaDbccMemoryStatus -SqlInstance $caller -EnableException:$EnableException 3>&1 | ForEach-Object { $null = $all.Add($PSItem) }
                } catch {
                    $record = $PSItem
                }
                $context = $caller.ConnectionContext.CurrentDatabase
                $caller.ConnectionContext.Disconnect()
                if (@($all | Where-Object { "$($PSItem.Message)".EndsWith($ending, [System.StringComparison]::Ordinal) }).Count -gt 0) {
                    break
                }
                if ($null -ne $record -and $record.Exception.Message -ceq $ending) {
                    break
                }
                Start-Sleep -Seconds 2
            }
            [pscustomobject]@{ All = @($all); Record = $record; Context = $context }
        }
    }

    AfterAll {
        foreach ($row in @($loginServer.Query("SELECT session_id FROM sys.dm_exec_sessions WHERE login_name = N'$lowName';"))) {
            $null = $loginServer.Query("KILL $($row.session_id);")
        }
        $null = $loginServer.Query("IF DB_ID(N'$homeName') IS NOT NULL ALTER DATABASE [$homeName] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;")
        $null = $loginServer.Query("IF DB_ID(N'$homeName') IS NOT NULL DROP DATABASE [$homeName];")
        $null = $loginServer.Query("IF SUSER_ID(N'$lowName') IS NOT NULL DROP LOGIN [$lowName];")
    }

    Context "SQL login" -Tag NativeChecklist:sql-login {
        It "works with -SqlCredential" {
            $result = @(Get-DbaDbccMemoryStatus -SqlInstance $loginInstance -SqlCredential $loginCred -EnableException)
            $result.Count | Should -BeGreaterThan 0
        }

        It "fails cleanly without the credential: a warning and no output" {
            $result = Get-DbaDbccMemoryStatus -SqlInstance $loginInstance -WarningVariable warnings -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
            ($warnings -join " ") | Should -BeLike "*Failure*Login failed*"
        }

        # The connection is the command's own, so the failure throws.
        It "throws the connection failure under -EnableException" {
            { Get-DbaDbccMemoryStatus -SqlInstance $loginInstance -EnableException } | Should -Throw -ExpectedMessage "*Login failed*" -ErrorId "dbatools_Get-DbaDbccMemoryStatus*"
        }
    }

    Context "A login that may not run the DBCC" {
        It "warns with the joined server messages and goes on to the next instance" {
            $result = @(Get-DbaDbccMemoryStatus -SqlInstance $loginInstance, $loginServer -SqlCredential $lowCred -WarningVariable warnings -WarningAction SilentlyContinue)
            @($warnings).Count | Should -Be 1
            "$warnings".EndsWith("Failure Executing DBCC MEMORYSTATUS | $denied", [System.StringComparison]::Ordinal) | Should -BeTrue
            $result.Count | Should -BeGreaterThan 0
        }

        It "throws the same text under -EnableException, with the instance as its target" -Tag "NativeChecklist:enable-exception" {
            $record = $null
            try {
                $null = Get-DbaDbccMemoryStatus -SqlInstance $loginInstance -SqlCredential $lowCred -EnableException -WarningAction SilentlyContinue
            } catch {
                $record = $PSItem
            }
            $record | Should -Not -BeNullOrEmpty
            $record.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaDbccMemoryStatus*"
            "$($record.CategoryInfo.Category)" | Should -BeExactly "NotSpecified"
            "$($record.TargetObject)" | Should -BeExactly $loginInstance
            $record.Exception.Message | Should -BeExactly $denied
            $record.Exception.InnerException | Should -BeOfType System.Management.Automation.MethodInvocationException
            $record.Exception.InnerException.Message | Should -BeExactly "Exception calling ""query"" with ""3"" argument(s): ""$denied"""
        }

        It "leaves the caller's connection in its database when the DBCC fails" {
            $caller = New-LowCaller
            try {
                $null = Get-DbaDbccMemoryStatus -SqlInstance $caller -WarningAction SilentlyContinue
                $caller.ConnectionContext.CurrentDatabase | Should -BeExactly $homeName
            } finally {
                $caller.ConnectionContext.Disconnect()
            }
        }
    }

    # caller-denied-read-master and caller-denied-read-master-ee.
    Context "A connection that read the master object and cannot go back to its database" {
        It "writes the restore warning, then the query's, with the connection left in master" {
            $outcome = Invoke-OnDeniedCaller -ReadMaster
            $outcome.Record | Should -BeNullOrEmpty
            $outcome.All.Count | Should -Be 2
            $outcome.All[0].Message | Should -BeExactly $restoreWarning
            $outcome.All[1].Message.EndsWith("Failure Executing DBCC MEMORYSTATUS | $denied", [System.StringComparison]::Ordinal) | Should -BeTrue
            $outcome.Context | Should -BeExactly "master"
        }

        It "writes the restore warning and throws the query's error under -EnableException" -Tag "NativeChecklist:enable-exception" {
            $outcome = Invoke-OnDeniedCaller -ReadMaster -EnableException
            $outcome.All[0].Message | Should -BeExactly $restoreWarning
            $outcome.Record.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaDbccMemoryStatus*"
            $outcome.Record.Exception.Message | Should -BeExactly $denied
            $outcome.Context | Should -BeExactly "master"
        }
    }

    # caller-denied and caller-denied-ee. Kept as the pin: the script method's catch has nothing to join there, so the text names no reason.
    Context "A connection that cannot read the master object" {
        It "warns with the empty method fault and stays in its database" {
            $outcome = Invoke-OnDeniedCaller
            $outcome.Record | Should -BeNullOrEmpty
            $outcome.All.Count | Should -Be 1
            $outcome.All[0].Message.EndsWith("Failure Executing DBCC MEMORYSTATUS | $emptyFault", [System.StringComparison]::Ordinal) | Should -BeTrue
            $outcome.Context | Should -BeExactly $homeName
        }

        It "throws the method fault under -EnableException" -Tag "NativeChecklist:enable-exception" {
            $outcome = Invoke-OnDeniedCaller -EnableException
            $outcome.Record.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaDbccMemoryStatus*"
            $outcome.Record.Exception.Message | Should -BeExactly $emptyFault
            $outcome.Context | Should -BeExactly $homeName
        }
    }
}

# Only sysadmin gets rows from the DBCC (evidence/pin-memorystatus-rows-20261104.txt), and a DENY does not bind sysadmin. So the caller sits in a database of this file's own while a second
# session waits in ALTER DATABASE ... SET OFFLINE with no termination clause. That finishes once the caller moves to master, so its USE back fails, with the rows already read. Measured on the pin,
# both editions, every form below: evidence/pin-memorystatus-offline-20261104.txt. Watchman d6e69b969c33c917 asks for the -Debug form; the rest are the record's other forms.
# A runspace of its own: Streams.Warning shows what the host line wrote, 3>&1 shows what reached stream 3, and no prompt can be answered, so a prompt shows as a HostException.
Describe "Native Get-DbaDbccMemoryStatus when the caller's database goes offline during the read" -Tag IntegrationTests {
    BeforeAll {
        $offlineInstance = $TestConfig.InstanceSingle
        $offlineName = "dbatoolsci_nms_off_$(Get-Random)"
        $offlineServer = Connect-DbaInstance -SqlInstance $offlineInstance -NonPooledConnection -EnableException
        $null = $offlineServer.Query("CREATE DATABASE [$offlineName];")
        $offlineWarning = "The database context could not be restored to [$offlineName]: Exception calling ""ExecuteNonQuery"" with ""1"" argument(s): ""An exception occurred while executing a Transact-SQL statement or batch."""
        $offlineFirstType = $offlineServer.Databases["master"].ExecuteWithResults("DBCC MEMORYSTATUS").Tables[0].Columns[0].ColumnName

        function Invoke-WhileGoingOffline {
            param([hashtable]$Arguments, [string]$Preference)
            $null = $offlineServer.Query("ALTER DATABASE [$offlineName] SET ONLINE;")
            $caller = Connect-DbaInstance -SqlInstance $offlineInstance -Database $offlineName -NonPooledConnection -EnableException
            $holder = Connect-DbaInstance -SqlInstance $offlineInstance -NonPooledConnection -EnableException
            $command = $null
            $task = $null
            $offlineState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
            $offlineType = (Get-Command Get-DbaDbccMemoryStatus -CommandType Cmdlet).ImplementingType
            $offlineEntry = New-Object System.Management.Automation.Runspaces.SessionStateCmdletEntry -ArgumentList "Get-DbaDbccMemoryStatus", $offlineType, $null
            $offlineState.Commands.Add($offlineEntry)
            $offlineRunspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($offlineState)
            $offlineShell = [System.Management.Automation.PowerShell]::Create()
            $offlineOutput = New-Object "System.Management.Automation.PSDataCollection[psobject]"
            $offlineStop = $null
            try {
                $null = $caller.ConnectionContext.ExecuteScalar("SELECT 1;")
                $null = $caller.Databases["master"].Name
                $holderSession = $holder.ConnectionContext.ExecuteScalar("SELECT @@SPID;")
                $holderConnection = $holder.ConnectionContext.SqlConnectionObject
                if ("$($holderConnection.State)" -ne "Open") {
                    $holderConnection.Open()
                    $command = $holderConnection.CreateCommand()
                    $command.CommandText = "SELECT @@SPID;"
                    $holderSession = $command.ExecuteScalar()
                } else {
                    $command = $holderConnection.CreateCommand()
                }
                $command.CommandTimeout = 30
                $command.CommandText = "ALTER DATABASE [$offlineName] SET OFFLINE;"
                $task = $command.ExecuteNonQueryAsync()
                for ($look = 0; $look -lt 40; $look++) {
                    if (@($offlineServer.Query("SELECT session_id FROM sys.dm_exec_requests WHERE session_id = $holderSession;") | Where-Object { $null -ne $PSItem }).Count -gt 0) {
                        break
                    }
                    Start-Sleep -Milliseconds 250
                }

                $offlineRunspace.Open()
                $offlineShell.Runspace = $offlineRunspace
                $callArguments = $Arguments + @{ SqlInstance = $caller }
                $null = $offlineShell.AddScript('param($Arguments, $Preference) if ($Preference) { $WarningPreference = $Preference }; Get-DbaDbccMemoryStatus @Arguments -WarningVariable offlineCaught 3>&1; "next statement"; foreach ($caught in $offlineCaught) { "variable " + $caught.Message }').AddArgument($callArguments).AddArgument($Preference)
                try {
                    $null = $offlineShell.Invoke($null, $offlineOutput)
                } catch {
                    # A stop leaves the runspace's script through Invoke, as a method call's exception.
                    $offlineStop = $PSItem.Exception.InnerException
                }
                [pscustomobject]@{
                    Rows       = @($offlineOutput | Where-Object { $null -ne $PSItem.PSObject.Properties["RecordSetId"] })
                    InStream   = @($offlineOutput | Where-Object { $PSItem.PSObject.BaseObject -is [System.Management.Automation.WarningRecord] } | ForEach-Object { $PSItem.Message })
                    OnHost     = @($offlineShell.Streams.Warning | ForEach-Object { $PSItem.Message })
                    Errors     = @($offlineShell.Streams.Error)
                    Stop       = $offlineStop
                    Next       = @($offlineOutput | Where-Object { "$PSItem" -ceq "next statement" }).Count
                    Variable   = @($offlineOutput | Where-Object { "$PSItem" -clike "variable *" } | ForEach-Object { "$PSItem".Substring(9) })
                    Context    = $caller.ConnectionContext.CurrentDatabase
                }
            } finally {
                $offlineShell.Dispose()
                $offlineRunspace.Dispose()
                if ($null -ne $task -and -not $task.Wait(45000)) {
                    $command.Cancel()
                }
                if ($null -ne $command) {
                    $command.Dispose()
                }
                $holder.ConnectionContext.Disconnect()
                $caller.ConnectionContext.Disconnect()
            }
        }
    }

    AfterAll {
        $null = $offlineServer.Query("IF DB_ID(N'$offlineName') IS NOT NULL ALTER DATABASE [$offlineName] SET ONLINE;")
        $null = $offlineServer.Query("IF DB_ID(N'$offlineName') IS NOT NULL ALTER DATABASE [$offlineName] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;")
        $null = $offlineServer.Query("IF DB_ID(N'$offlineName') IS NOT NULL DROP DATABASE [$offlineName];")
        $offlineServer.ConnectionContext.Disconnect()
    }

    # The restore warning is the cmdlet's own WriteWarning, and the engine applies the caller's preference: harness-edits.md, "Database-context restore warning: ports follow the
    # compiled cmdlet's warning preference (operator, 2026-11-15)", points 1, 3 and 5; recorded as restore-warning-engine-preference. Part 1 of pin-memorystatus-rows-20261104.txt:
    # with a bound Continue, -Debug does not prompt.
    It "writes the warning to its stream, then every row, and leaves the connection in master: <Name>" -ForEach @(
        @{ Name = "no preference"; Extra = @{ } }
        @{ Name = "-WarningAction Continue"; Extra = @{ WarningAction = "Continue" } }
        @{ Name = "-Debug -WarningAction Continue"; Extra = @{ Debug = $true; WarningAction = "Continue" } }
        @{ Name = "-EnableException"; Extra = @{ EnableException = $true } }
    ) {
        $outcome = Invoke-WhileGoingOffline -Arguments $Extra
        $outcome.Stop | Should -BeNullOrEmpty
        @($outcome.Errors).Count | Should -Be 0
        @($outcome.InStream).Count | Should -Be 1
        $outcome.InStream[0] | Should -BeExactly $offlineWarning
        @($outcome.OnHost).Count | Should -Be 0
        $outcome.Rows.Count | Should -BeGreaterThan 100
        $outcome.Rows[0].Type | Should -BeExactly $offlineFirstType
        $outcome.Next | Should -Be 1
        $outcome.Context | Should -BeExactly "master"
    }

    # offline-silent, offline-debug-silent and offline-global-silent.
    It "writes no warning, then every row: <Name>" -ForEach @(
        @{ Name = "-WarningAction SilentlyContinue"; Extra = @{ WarningAction = "SilentlyContinue" }; Preference = "" }
        @{ Name = "-Debug -WarningAction SilentlyContinue"; Extra = @{ Debug = $true; WarningAction = "SilentlyContinue" }; Preference = "" }
        @{ Name = "`$WarningPreference SilentlyContinue"; Extra = @{ }; Preference = "SilentlyContinue" }
    ) {
        $outcome = Invoke-WhileGoingOffline -Arguments $Extra -Preference $Preference
        $outcome.Stop | Should -BeNullOrEmpty
        @($outcome.Errors).Count | Should -Be 0
        @($outcome.InStream).Count | Should -Be 0
        @($outcome.OnHost).Count | Should -Be 0
        $outcome.Rows.Count | Should -BeGreaterThan 100
        $outcome.Next | Should -Be 1
        $outcome.Context | Should -BeExactly "master"
    }

    # Point 3(c): under a bound Ignore nothing is shown and nothing reaches stream 3; -WarningVariable holds the text (point 3(d)).
    It "writes nothing to its stream under -WarningAction Ignore, keeps the text in -WarningVariable, then every row" {
        $outcome = Invoke-WhileGoingOffline -Arguments @{ WarningAction = "Ignore" }
        $outcome.Stop | Should -BeNullOrEmpty
        @($outcome.Errors).Count | Should -Be 0
        @($outcome.InStream).Count | Should -Be 0
        @($outcome.OnHost).Count | Should -Be 0
        @($outcome.Variable).Count | Should -Be 1
        $outcome.Variable[0] | Should -BeExactly $offlineWarning
        $outcome.Rows.Count | Should -BeGreaterThan 100
        $outcome.Rows[0].Type | Should -BeExactly $offlineFirstType
        $outcome.Next | Should -Be 1
        $outcome.Context | Should -BeExactly "master"
    }

    # Point 3(a): under Stop the warning ends the call with ActionPreferenceStopException carrying its text, before any row, and the next statement does not run.
    It "ends the call at the warning, before any row: <Name>" -ForEach @(
        @{ Name = "-WarningAction Stop"; Extra = @{ WarningAction = "Stop" }; Preference = "" }
        @{ Name = "`$WarningPreference Stop"; Extra = @{ }; Preference = "Stop" }
    ) {
        $outcome = Invoke-WhileGoingOffline -Arguments $Extra -Preference $Preference
        $outcome.Stop | Should -BeOfType [System.Management.Automation.ActionPreferenceStopException]
        $outcome.Stop.Message | Should -BeLike "*$([System.Management.Automation.WildcardPattern]::Escape($offlineWarning))"
        $outcome.Rows.Count | Should -Be 0
        $outcome.Next | Should -Be 0
        $outcome.Context | Should -BeExactly "master"
    }

    # Point 3(b): under Inquire, or -Debug with no bound -WarningAction, the engine asks; this runspace cannot, so the write raises HostException at once and the call's rows
    # are lost. Where the HostException surfaces (the call's error or the script's stop) is not asserted: neither the probe nor a run measured it for this cmdlet.
    It "raises the engine's HostException at the warning, before any row: <Name>" -ForEach @(
        @{ Name = "-WarningAction Inquire"; Extra = @{ WarningAction = "Inquire" }; Preference = "" }
        @{ Name = "`$WarningPreference Inquire"; Extra = @{ }; Preference = "Inquire" }
        @{ Name = "-Debug"; Extra = @{ Debug = $true }; Preference = "" }
    ) {
        $outcome = Invoke-WhileGoingOffline -Arguments $Extra -Preference $Preference
        $raised = @(@($outcome.Stop) + @($outcome.Errors | ForEach-Object { $PSItem.Exception }) | Where-Object { $null -ne $PSItem } | ForEach-Object {
                $current = $PSItem
                while ($null -ne $current) {
                    if ($current -is [System.Management.Automation.Host.HostException]) { $current }
                    $current = $current.InnerException
                }
            })
        $raised.Count | Should -BeGreaterThan 0
        $outcome.Rows.Count | Should -Be 0
        $outcome.Context | Should -BeExactly "master"
    }
}
