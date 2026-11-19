#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaDbMirrorMonitor",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- The pinned command has no SupportsShouldProcess, WhatIf or Confirm parameters; it reads the monitor rows and -Update only asks the engine's own procedure to add one.

Describe "Native Get-DbaDbMirrorMonitor" -Tag IntegrationTests {
    BeforeAll {
        # The legs of one SQL version take the instance one after the other, so this file may drop and create the monitor table.
        # A table already here may hold real history, and sp_rename refuses this shipped table: its rows wait in a copy, and AfterAll gives
        # the table the procedure makes again those rows and the grants it had, which the procedure does not make again.
        # Pester runs AfterAll even when this block fails, so AfterAll touches the table only once $tableOwned says the table was absent
        # or its rows and grants are saved; until then a failure leaves the table as it was.
        $tableOwned = $false
        $instance = $TestConfig.InstanceSingle
        $server = Connect-DbaInstance -SqlInstance $instance -EnableException
        $tableAtStart = -not (@($server.Query("SELECT OBJECT_ID(N'msdb.dbo.dbm_monitor_data') AS id;"))[0].id -is [System.DBNull])
        $suffix = Get-Random
        $savedRows = "msdb.dbo.dbatoolsci_saved_monitor_$suffix"
        $savedGrants = @()
        if ($tableAtStart) {
            $savedGrants = @($server.Query("SELECT pe.state_desc, pe.permission_name, pr.name AS grantee FROM msdb.sys.database_permissions AS pe JOIN msdb.sys.database_principals AS pr ON pr.principal_id = pe.grantee_principal_id WHERE pe.major_id = OBJECT_ID(N'msdb.dbo.dbm_monitor_data') AND pe.class = 1 AND pe.minor_id = 0;"))
            $null = $server.Query("SELECT * INTO $savedRows FROM msdb.dbo.dbm_monitor_data;")
        }
        $tableOwned = $true
        $plainName = "dbatoolsci_mm_plain_$suffix"
        $rateName = "dbatoolsci_ma_rate_$suffix"
        $quoteName = "dbatoolsci_mm'quote_$suffix"
        $bracketName = "dbatoolsci_mm]bracket_$suffix"
        $badInstance = "TCP:127.0.0.1,1"
        $notFound = "msdb.dbo.dbm_monitor_data not found. Please run Add-DbaDbMirrorMonitor then you can get monitor stats."
        $notFoundPattern = "\[Get-DbaDbMirrorMonitor\] " + [regex]::Escape($notFound) + "$"
        $nullArray = "Cannot index into a null array."
        $nullCallPattern = "\[Get-DbaDbMirrorMonitor\] Failure \| You cannot call a method on a null-valued expression\.$"
        $notMirrored = "An exception occurred while executing a Transact-SQL statement or batch.The database '{0}' is not being mirrored. No update of the base table was done."

        # A Pester It runs its body inside a try, so a call outside any try needs a runspace of its own.
        function Invoke-NativeOutsideTry {
            param([hashtable]$Arguments)
            $outsideState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
            $outsideType = (Get-Command Get-DbaDbMirrorMonitor -CommandType Cmdlet).ImplementingType
            $outsideEntry = New-Object System.Management.Automation.Runspaces.SessionStateCmdletEntry -ArgumentList "Get-DbaDbMirrorMonitor", $outsideType, $null
            $outsideState.Commands.Add($outsideEntry)
            $outsideRunspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($outsideState)
            $outsideShell = [System.Management.Automation.PowerShell]::Create()
            $outsideOutput = New-Object "System.Management.Automation.PSDataCollection[psobject]"
            $outsideStop = $null
            try {
                $outsideRunspace.Open()
                $outsideShell.Runspace = $outsideRunspace
                $null = $outsideShell.AddScript('param($Arguments) Get-DbaDbMirrorMonitor @Arguments; "next statement"').AddArgument($Arguments)
                try {
                    $null = $outsideShell.Invoke($null, $outsideOutput)
                } catch {
                    # The stop leaves the runspace's script through Invoke, as a method call's exception.
                    $outsideStop = $PSItem.Exception.InnerException
                }
                [pscustomobject]@{
                    Output   = @($outsideOutput)
                    Errors   = @($outsideShell.Streams.Error)
                    Warnings = @($outsideShell.Streams.Warning)
                    Stop     = $outsideStop
                }
            } finally {
                $outsideShell.Dispose()
                $outsideRunspace.Dispose()
            }
        }
    }

    AfterAll {
        if ($tableOwned) {
            $null = $server.Query("IF OBJECT_ID(N'msdb.dbo.dbm_monitor_data') IS NOT NULL DROP TABLE msdb.dbo.dbm_monitor_data;")
            if ($tableAtStart) {
                # One call per statement, because a failed call throws: the copy goes only after the rows and grants are back.
                $null = $server.Query("EXEC msdb.sys.sp_dbmmonitorupdate;")
                $null = $server.Query("DELETE FROM msdb.dbo.dbm_monitor_data;")
                $null = $server.Query("INSERT INTO msdb.dbo.dbm_monitor_data SELECT * FROM $savedRows;")
                foreach ($savedGrant in $savedGrants) {
                    # state_desc GRANT_WITH_GRANT_OPTION is a GRANT statement that ends WITH GRANT OPTION; GRANT and DENY are their own statements.
                    $grantVerb, $grantOption = $savedGrant.state_desc, ""
                    if ($savedGrant.state_desc -eq "GRANT_WITH_GRANT_OPTION") {
                        $grantVerb, $grantOption = "GRANT", " WITH GRANT OPTION"
                    }
                    $null = $server.Query("$grantVerb $($savedGrant.permission_name) ON dbo.dbm_monitor_data TO [$($savedGrant.grantee -replace "\]", "]]")]$grantOption;", "msdb")
                }
                $null = $server.Query("DROP TABLE $savedRows;")
            }
        }
    }

    Context "Without the monitor table" {
        BeforeAll {
            $null = $server.Query("IF OBJECT_ID(N'msdb.dbo.dbm_monitor_data') IS NOT NULL DROP TABLE msdb.dbo.dbm_monitor_data;")
            $master = Get-DbaDatabase -SqlInstance $instance -Database master -EnableException
        }

        It "warns for each database and reads on" {
            $warnings = @()
            @(Get-DbaDbMirrorMonitor -SqlInstance $instance -Database master, msdb -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings).Count | Should -Be 0
            $warnings.Count | Should -Be 2
            foreach ($warning in $warnings) {
                "$warning" | Should -Match $notFoundPattern
            }
        }

        It "throws the pinned record at the first database under -EnableException" -Tag "NativeChecklist:enable-exception" {
            $warnings = @()
            $failure = $null
            try {
                $null = Get-DbaDbMirrorMonitor -SqlInstance $instance -Database master, msdb -EnableException -WarningAction SilentlyContinue -WarningVariable warnings
            } catch {
                $failure = $PSItem
            }
            $failure.Exception.Message | Should -BeExactly $notFound
            $failure.Exception.GetType().FullName | Should -BeExactly "System.Exception"
            $failure.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaDbMirrorMonitor*"
            $failure.CategoryInfo.Category | Should -Be "NotSpecified"
            $failure.TargetObject | Should -BeNullOrEmpty
            $warnings.Count | Should -Be 1
        }

        It "only warns under -ErrorAction Stop, as Stop-Function does" {
            $warnings = @()
            @(Get-DbaDbMirrorMonitor -SqlInstance $instance -Database master, msdb -ErrorAction Stop -WarningAction SilentlyContinue -WarningVariable warnings).Count | Should -Be 0
            $warnings.Count | Should -Be 2
        }

        It "reads every database for an empty -Database" {
            $expected = @(Get-DbaDatabase -SqlInstance $instance -EnableException).Count
            foreach ($form in @(@{ Database = "" }, @{ Database = $null }, @{ Database = @() })) {
                $warnings = @()
                @(Get-DbaDbMirrorMonitor -SqlInstance $instance @form -WarningAction SilentlyContinue -WarningVariable warnings).Count | Should -Be 0
                $warnings.Count | Should -Be $expected
            }
        }

        It "compares -Database as -in does: without regard to case, once, and no patterns" {
            foreach ($case in @(
                    @{ Value = "MASTER"; Expected = 1 },
                    @{ Value = @("master", "master"); Expected = 1 },
                    @{ Value = "mas*"; Expected = 0 },
                    @{ Value = "nosuchdb"; Expected = 0 }
                )) {
                $warnings = @()
                @(Get-DbaDbMirrorMonitor -SqlInstance $instance -Database $case.Value -WarningAction SilentlyContinue -WarningVariable warnings).Count | Should -Be 0
                $warnings.Count | Should -Be $case.Expected
            }
        }

        It "does nothing without a database to read" {
            foreach ($call in @(
                    { Get-DbaDbMirrorMonitor },
                    { Get-DbaDbMirrorMonitor -SqlInstance @() },
                    { Get-DbaDbMirrorMonitor -InputObject $null },
                    { $null | Get-DbaDbMirrorMonitor }
                )) {
                @(& $call 3>&1).Count | Should -Be 0
            }
        }

        It "refuses a value outside the pinned set of -LimitResults" {
            { Get-DbaDbMirrorMonitor -SqlInstance $instance -LimitResults Everything } | Should -Throw -ErrorId "ParameterArgumentValidationError*"
            { Get-DbaDbMirrorMonitor -SqlInstance $instance -LimitResults "" } | Should -Throw -ErrorId "ParameterArgumentValidationError*"
        }

        It "outside any try, a null element writes the pinned record, warns and reads the other databases" {
            $outside = Invoke-NativeOutsideTry @{ InputObject = @($null, $master) }
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Errors.Count | Should -Be 1
            $outside.Errors[0].Exception | Should -BeOfType System.Management.Automation.RuntimeException
            $outside.Errors[0].Exception.Message | Should -BeExactly $nullArray
            $outside.Errors[0].FullyQualifiedErrorId | Should -BeLike "NullArray,*"
            $outside.Errors[0].CategoryInfo.Category | Should -Be "InvalidOperation"
            $outside.Errors[0].TargetObject | Should -BeNullOrEmpty
            $outside.Warnings.Count | Should -Be 2
            $outside.Warnings[0].Message | Should -Match $nullCallPattern
            $outside.Warnings[1].Message | Should -Match $notFoundPattern
            ($outside.Output -join ",") | Should -BeExactly "next statement"

            $outside = Invoke-NativeOutsideTry @{ InputObject = @($master, $null) }
            $outside.Errors.Count | Should -Be 1
            $outside.Warnings.Count | Should -Be 2
            $outside.Warnings[0].Message | Should -Match $notFoundPattern
            $outside.Warnings[1].Message | Should -Match $nullCallPattern
            ($outside.Output -join ",") | Should -BeExactly "next statement"

            $outside = Invoke-NativeOutsideTry @{ InputObject = @($null, $master); ErrorAction = "SilentlyContinue" }
            $outside.Errors.Count | Should -Be 0
            $outside.Warnings.Count | Should -Be 2
            ($outside.Output -join ",") | Should -BeExactly "next statement"
        }

        It "inside a caller's try, a null element is caught there, with no warning and no other database read" {
            $caught = $null
            $reached = $false
            $warnings = $null
            try {
                $null = Get-DbaDbMirrorMonitor -InputObject @($null, $master) -WarningVariable warnings -WarningAction SilentlyContinue
                $reached = $true
            } catch {
                $caught = $PSItem
            }
            $reached | Should -BeFalse
            $caught.Exception.Message | Should -BeExactly $nullArray
            $caught.FullyQualifiedErrorId | Should -BeLike "NullArray,*"
            $caught.CategoryInfo.Category | Should -Be "InvalidOperation"
            $warnings | Should -BeNullOrEmpty
        }

        It "outside any try, -EnableException ends the command at a null element and the script goes on" -Tag "NativeChecklist:enable-exception" {
            $outside = Invoke-NativeOutsideTry @{ InputObject = @($null, $master); EnableException = $true }
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Errors.Count | Should -Be 1
            $outside.Errors[0].Exception.Message | Should -BeExactly $nullArray
            $outside.Errors[0].FullyQualifiedErrorId | Should -BeLike "NullArray,*"
            $outside.Warnings.Count | Should -Be 0
            ($outside.Output -join ",") | Should -BeExactly "next statement"
        }

        It "outside any try, -ErrorAction Stop turns a null element into the stop PowerShell gives WriteError" {
            $outside = Invoke-NativeOutsideTry @{ InputObject = @($null, $master); ErrorAction = "Stop" }
            $outside.Stop | Should -BeOfType System.Management.Automation.ActionPreferenceStopException
            $outside.Stop.ErrorRecord.Exception.Message | Should -BeExactly $nullArray
            $outside.Stop.ErrorRecord.FullyQualifiedErrorId | Should -BeLike "NullArray,*"
            $outside.Warnings.Count | Should -Be 0
            $outside.Output.Count | Should -Be 0
        }
    }

    Context "With the monitor table" {
        BeforeAll {
            # The first update creates the table. Rows go straight into it: the procedure reads them by database id, mirrored or not.
            $null = $server.Query("EXEC msdb.sys.sp_dbmmonitorupdate;")
            $null = $server.Query("CREATE DATABASE [$plainName];")
            $null = $server.Query("CREATE DATABASE [$rateName];")
            $null = $server.Query("CREATE DATABASE [$quoteName];")
            $null = $server.Query("CREATE DATABASE [$($bracketName.Replace("]", "]]"))];")
            $insert = "INSERT INTO msdb.dbo.dbm_monitor_data (database_id, role, status, witness_status, log_flush_rate, send_queue_size, send_rate, redo_queue_size, redo_rate, transaction_delay, transactions_per_sec, time, end_of_log_lsn, failover_lsn, local_time)"

            # One row inside each time limit, then enough older ones to tell every row limit apart: 1103 rows give 1102 results.
            $null = $server.Query("$insert SELECT DB_ID(N'$plainName'), 0, 4, 1, 0, 0, 0, 0, 0, 0, 0, DATEADD(MINUTE, -age.minutes, GETUTCDATE()), 0, 0, DATEADD(MINUTE, -age.minutes, GETDATE()) FROM (VALUES (10), (30), (180), (360), (720), (2160), (4320)) AS age (minutes);")
            $null = $server.Query("$insert SELECT TOP (1096) DB_ID(N'$plainName'), 0, 4, 1, 0, 0, 0, 0, 0, 0, 0, DATEADD(MINUTE, -4321 - number, GETUTCDATE()), 0, 0, DATEADD(MINUTE, -4321 - number, GETDATE()) FROM master.dbo.spt_values WHERE type = N'P' ORDER BY number;")

            foreach ($name in $quoteName, $bracketName) {
                $null = $server.Query("$insert SELECT DB_ID(N'$($name.Replace("'", "''"))'), 0, 4, 1, 0, 0, 0, 0, 0, 0, 0, DATEADD(MINUTE, -age.minutes, GETUTCDATE()), 0, 0, DATEADD(MINUTE, -age.minutes, GETDATE()) FROM (VALUES (10), (30)) AS age (minutes);")
            }

            # Counters 100 seconds apart and a role change, so each computed column has a known value.
            $now = [datetime]@($server.Query("SELECT CONVERT(datetime, CONVERT(char(19), GETUTCDATE(), 126), 126) AS now;"))[0].now
            $stamp = $now.AddMinutes(-10)
            $localStamp = $stamp.AddMinutes(90)
            $format = "yyyy-MM-ddTHH:mm:ss"
            $rows = @(
                @{ Age = 0; Role = 0; Status = 4; Witness = 1; Flush = 2048000; SendQueue = 5; Send = 1024000; RedoQueue = 7; Redo = 512000; Delay = 3000; Rate = 1500; Lsn = 200 },
                @{ Age = 100; Role = 0; Status = 2; Witness = 2; Flush = 1024000; SendQueue = 11; Send = 512000; RedoQueue = 13; Redo = 256000; Delay = 1000; Rate = 500; Lsn = 100 },
                @{ Age = 200; Role = 1; Status = 2; Witness = 2; Flush = 0; SendQueue = 0; Send = 0; RedoQueue = 0; Redo = 0; Delay = 0; Rate = 0; Lsn = 50 }
            )
            foreach ($row in $rows) {
                $time = $stamp.AddSeconds(-$row.Age).ToString($format, [System.Globalization.CultureInfo]::InvariantCulture)
                $local = $localStamp.AddSeconds(-$row.Age).ToString($format, [System.Globalization.CultureInfo]::InvariantCulture)
                $null = $server.Query("$insert VALUES (DB_ID(N'$rateName'), $($row.Role), $($row.Status), $($row.Witness), $($row.Flush), $($row.SendQueue), $($row.Send), $($row.RedoQueue), $($row.Redo), $($row.Delay), $($row.Rate), '$time', $($row.Lsn), $($row.Lsn), '$local');")
            }

            $plainDb = Get-DbaDatabase -SqlInstance $instance -Database $plainName -EnableException
            $rateDb = Get-DbaDatabase -SqlInstance $instance -Database $rateName -EnableException
        }

        AfterAll {
            foreach ($name in $plainName, $rateName, $quoteName, $bracketName) {
                $text = $name.Replace("'", "''")
                $identifier = $name.Replace("]", "]]")
                $null = $server.Query("DELETE FROM msdb.dbo.dbm_monitor_data WHERE database_id = DB_ID(N'$text');")
                $null = $server.Query("USE [master]; IF DB_ID(N'$text') IS NOT NULL BEGIN ALTER DATABASE [$identifier] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [$identifier]; END;")
            }
        }

        It "returns each row of the procedure with the pinned columns and values" {
            $identity = @($server.Query("SELECT SERVERPROPERTY('MachineName') AS ComputerName, ISNULL(SERVERPROPERTY('InstanceName'), 'MSSQLSERVER') AS InstanceName, SERVERPROPERTY('ServerName') AS SqlInstance;"))[0]
            $result = @(Get-DbaDbMirrorMonitor -SqlInstance $instance -Database $rateName -EnableException | Sort-Object TimeRecorded -Descending)
            $result.Count | Should -Be 2
            $result[0] | Should -BeOfType System.Management.Automation.PSCustomObject
            (@($result[0].PSObject.Properties.Name) -join ",") |
                Should -BeExactly "ComputerName,InstanceName,SqlInstance,DatabaseName,Role,MirroringState,WitnessStatus,LogGenerationRate,UnsentLog,SendRate,UnrestoredLog,RecoveryRate,TransactionDelay,TransactionsPerSecond,AverageDelay,TimeRecorded,TimeBehind,LocalTime"
            $result[0].ComputerName | Should -Be $identity.ComputerName
            $result[0].InstanceName | Should -Be $identity.InstanceName
            $result[0].SqlInstance | Should -Be $identity.SqlInstance
            $result[0].DatabaseName | Should -BeExactly $rateName
            $result[0].Role | Should -Be 1
            $result[0].MirroringState | Should -Be 4
            $result[0].WitnessStatus | Should -Be 1
            $result[0].LogGenerationRate | Should -Be 10
            $result[0].UnsentLog | Should -Be 5
            $result[0].SendRate | Should -Be 5
            $result[0].UnrestoredLog | Should -Be 7
            $result[0].RecoveryRate | Should -Be 2
            $result[0].TransactionDelay | Should -Be 20
            $result[0].TransactionsPerSecond | Should -Be 10
            $result[0].AverageDelay | Should -Be 2
            $result[0].TimeRecorded | Should -Be $stamp
            $result[0].TimeBehind | Should -Be $stamp
            $result[0].LocalTime | Should -Be $localStamp
        }

        It "keeps a value the engine leaves NULL as DBNull" {
            $result = @(Get-DbaDbMirrorMonitor -SqlInstance $instance -Database $rateName -EnableException | Sort-Object TimeRecorded -Descending)
            $result[1].MirroringState | Should -Be 2
            $result[1].UnsentLog | Should -Be 11
            foreach ($property in "LogGenerationRate", "SendRate", "RecoveryRate", "TransactionDelay", "TransactionsPerSecond", "AverageDelay") {
                $result[1].$property | Should -BeOfType System.DBNull
            }
        }

        It "returns no row and no warning for a database without monitor rows" {
            $warnings = @()
            @(Get-DbaDbMirrorMonitor -SqlInstance $instance -Database master -EnableException -WarningAction SilentlyContinue -WarningVariable warnings).Count | Should -Be 0
            $warnings.Count | Should -Be 0
        }

        It "reads the last two hours by default" {
            @(Get-DbaDbMirrorMonitor -SqlInstance $instance -Database $plainName -EnableException).Count | Should -Be 2
        }

        It "selects the rows of each limit up to Last500Rows, without regard to case" {
            foreach ($case in @(
                    @{ Limit = "LastRow"; Expected = 1 },
                    @{ Limit = "lastrow"; Expected = 1 },
                    @{ Limit = "LastTwoHours"; Expected = 2 },
                    @{ Limit = "LastFourHours"; Expected = 3 },
                    @{ Limit = "LastEightHours"; Expected = 4 },
                    @{ Limit = "LastDay"; Expected = 5 },
                    @{ Limit = "LastTwoDays"; Expected = 6 },
                    @{ Limit = "Last100Rows"; Expected = 100 },
                    @{ Limit = "Last500Rows"; Expected = 500 }
                )) {
                @(Get-DbaDbMirrorMonitor -SqlInstance $instance -Database $plainName -LimitResults $case.Limit -EnableException).Count | Should -Be $case.Expected
            }
        }

        It "returns the last thousand rows for Last1000Rows" {
            @(Get-DbaDbMirrorMonitor -SqlInstance $instance -Database $plainName -LimitResults Last1000Rows -EnableException).Count | Should -Be 1000
        }

        It "returns every row up to a million for Last1000000Rows" {
            @(Get-DbaDbMirrorMonitor -SqlInstance $instance -Database $plainName -LimitResults Last1000000Rows -EnableException).Count | Should -Be 1102
        }

        It "reads a database whose name holds a quote" {
            $warnings = @()
            $result = @(Get-DbaDbMirrorMonitor -SqlInstance $instance -Database $quoteName -LimitResults LastRow -EnableException -WarningAction SilentlyContinue -WarningVariable warnings)
            $warnings.Count | Should -Be 0
            $result.Count | Should -Be 1
            $result[0].DatabaseName | Should -BeExactly $quoteName
        }

        It "reads a database whose name holds a closing bracket" {
            $warnings = @()
            $result = @(Get-DbaDbMirrorMonitor -SqlInstance $instance -Database $bracketName -LimitResults LastRow -EnableException -WarningAction SilentlyContinue -WarningVariable warnings)
            $warnings.Count | Should -Be 0
            $result.Count | Should -Be 1
            $result[0].DatabaseName | Should -BeExactly $bracketName
        }

        It "reads the databases of -Database in the order of sys.databases" {
            $result = @(Get-DbaDbMirrorMonitor -SqlInstance $instance -Database $rateName, $plainName -LimitResults LastRow -EnableException)
            ($result.DatabaseName -join ",") | Should -BeExactly "$plainName,$rateName"
        }

        It "takes the pinned positions" {
            $result = @(Get-DbaDbMirrorMonitor $instance $null $plainName $null LastRow -EnableException)
            $result.Count | Should -Be 1
            $result[0].DatabaseName | Should -BeExactly $plainName
        }

        It "reads piped databases, record by record or as one array" -Tag "NativeChecklist:pipeline-multiple" {
            ($(@($plainDb, $rateDb | Get-DbaDbMirrorMonitor -LimitResults LastRow -EnableException).DatabaseName) -join ",") | Should -BeExactly "$plainName,$rateName"
            ($(@(Get-DbaDbMirrorMonitor -InputObject $plainDb, $rateDb -LimitResults LastRow -EnableException).DatabaseName) -join ",") | Should -BeExactly "$plainName,$rateName"
        }

        It "reads a named instance once, after the first record's piped databases" {
            $result = @($plainDb, $plainDb | Get-DbaDbMirrorMonitor -SqlInstance $instance -Database $rateName -LimitResults LastRow -EnableException)
            ($result.DatabaseName -join ",") | Should -BeExactly "$plainName,$rateName,$plainName"
        }

        It "warns for an instance it cannot reach and reads the next, also under -EnableException" -Tag "NativeChecklist:multi-instance-failure" {
            foreach ($form in @(@{ }, @{ EnableException = $true })) {
                $warnings = @()
                $result = @(Get-DbaDbMirrorMonitor -SqlInstance $badInstance, $instance -Database $plainName -LimitResults LastRow @form -WarningAction SilentlyContinue -WarningVariable warnings)
                ($warnings -join " ") | Should -Match "\[Get-DbaDatabase\] Failure"
                $result.Count | Should -Be 1
                $result[0].DatabaseName | Should -BeExactly $plainName
            }
        }

        It "reads without updating for a false -Update switch, and goes on for a false -EnableException switch" -Tag "NativeChecklist:switch-false" {
            $before = @($server.Query("SELECT COUNT(*) AS total FROM msdb.dbo.dbm_monitor_data WHERE database_id = DB_ID(N'$plainName');"))[0].total
            $warnings = @()
            $result = @(Get-DbaDbMirrorMonitor -SqlInstance $instance -Database $plainName -Update:$false -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings)
            $warnings.Count | Should -Be 0
            $result.Count | Should -Be 2
            @($server.Query("SELECT COUNT(*) AS total FROM msdb.dbo.dbm_monitor_data WHERE database_id = DB_ID(N'$plainName');"))[0].total | Should -Be $before
        }

        It "reports what the procedure answers when -Update meets a database that is not mirrored, and reads on" {
            $message = $notMirrored -f $rateName
            $warnings = @()
            @(Get-DbaDbMirrorMonitor -SqlInstance $instance -Database $plainName, $rateName -Update -WarningAction SilentlyContinue -WarningVariable warnings).Count | Should -Be 0
            $warnings.Count | Should -Be 2
            "$($warnings[0])" | Should -Match ("\[Get-DbaDbMirrorMonitor\] Failure \| " + [regex]::Escape($notMirrored -f $plainName) + "$")
            "$($warnings[1])" | Should -Match ("\[Get-DbaDbMirrorMonitor\] Failure \| " + [regex]::Escape($message) + "$")
        }

        It "throws the pinned Query record for that answer under -EnableException" -Tag "NativeChecklist:enable-exception" {
            $message = $notMirrored -f $plainName
            $failure = $null
            try {
                $null = Get-DbaDbMirrorMonitor -SqlInstance $instance -Database $plainName, $rateName -Update -EnableException -WarningAction SilentlyContinue
            } catch {
                $failure = $PSItem
            }
            $failure.Exception.Message | Should -BeExactly $message
            $failure.Exception.InnerException | Should -BeOfType System.Management.Automation.MethodInvocationException
            $failure.Exception.InnerException.Message | Should -BeExactly "Exception calling `"Query`" with `"1`" argument(s): `"$message`""
            $failure.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaDbMirrorMonitor*"
            $failure.CategoryInfo.Category | Should -Be "NotSpecified"
        }

        It "stops quietly when downstream takes only the first row" {
            @(Get-DbaDbMirrorMonitor -SqlInstance $instance -Database $plainName -LimitResults Last100Rows -EnableException | Select-Object -First 1).Count | Should -Be 1
        }
    }
}

Describe "Native Get-DbaDbMirrorMonitor over SQL authentication" -Tag IntegrationTests {
    BeforeAll {
        # sqlwhale22 serves the legs that run at the same time, so nothing is written there. It has no monitor table, and the warning that says so shows the login read the instance.
        $loginInstance = $TestConfig.InstanceSqlLogin
        $loginCred = $TestConfig.SqlLoginCred
        $notFound = "msdb.dbo.dbm_monitor_data not found. Please run Add-DbaDbMirrorMonitor then you can get monitor stats."
    }

    Context "SQL login" -Tag NativeChecklist:sql-login {
        It "reads the instance with -SqlCredential" {
            $warnings = @()
            @(Get-DbaDbMirrorMonitor -SqlInstance $loginInstance -SqlCredential $loginCred -Database master -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings).Count | Should -Be 0
            $warnings.Count | Should -Be 1
            "$($warnings[0])" | Should -Match ("\[Get-DbaDbMirrorMonitor\] " + [regex]::Escape($notFound) + "$")
        }

        It "throws what it reads with -SqlCredential under -EnableException" {
            { Get-DbaDbMirrorMonitor -SqlInstance $loginInstance -SqlCredential $loginCred -Database master -EnableException -WarningAction SilentlyContinue } | Should -Throw -ExpectedMessage $notFound
        }

        It "warns without the credential, under -EnableException too, as the nested Get-DbaDatabase does" {
            foreach ($form in @(@{ EnableException = $false }, @{ EnableException = $true })) {
                $warnings = @()
                @(Get-DbaDbMirrorMonitor -SqlInstance $loginInstance -Database master @form -WarningAction SilentlyContinue -WarningVariable warnings).Count | Should -Be 0
                ($warnings -join " ") | Should -Match "\[Get-DbaDatabase\] Failure \| Login failed"
            }
        }
    }
}

Describe "Native Get-DbaDbMirrorMonitor on a mirrored database" -Tag IntegrationTests {
    BeforeAll {
        # A real session between the pair, set up in T-SQL. The monitor table is created first, because the command asks for it before it calls the procedure.
        $principalInstance = $TestConfig.InstanceCopy1
        $mirrorInstance = $TestConfig.InstanceCopy2
        $principal = Connect-DbaInstance -SqlInstance $principalInstance -EnableException
        $mirror = Connect-DbaInstance -SqlInstance $mirrorInstance -EnableException
        $suffix = Get-Random
        $sessionName = "dbatoolsci_mms_$suffix"
        $endpointName = "dbatoolsci_mms_$suffix"
        $backupStem = "$($TestConfig.Temp)\$sessionName"
        $tableAtStart = @{ }
        $endpoints = @{ }

        function Set-NativeEndpoint {
            param($Server, [int]$Port, [string]$PartnerLogin)
            $existing = @($Server.Query("SELECT e.name, t.port FROM sys.database_mirroring_endpoints AS e JOIN sys.tcp_endpoints AS t ON t.endpoint_id = e.endpoint_id;"))
            $useName = $endpointName
            $usePort = $Port
            if ($existing.Count -gt 0) {
                $useName = $existing[0].name
                $usePort = [int]$existing[0].port
            } else {
                $null = $Server.Query("CREATE ENDPOINT [$endpointName] STATE = STARTED AS TCP (LISTENER_PORT = $Port) FOR DATABASE_MIRRORING (ROLE = PARTNER, AUTHENTICATION = WINDOWS NEGOTIATE, ENCRYPTION = REQUIRED ALGORITHM AES);")
            }
            $newLogin = @($Server.Query("SELECT SUSER_ID(N'$PartnerLogin') AS id;"))[0].id -is [System.DBNull]
            if ($newLogin) {
                $null = $Server.Query("CREATE LOGIN [$PartnerLogin] FROM WINDOWS;")
            }
            $null = $Server.Query("GRANT CONNECT ON ENDPOINT::[$useName] TO [$PartnerLogin];")
            [pscustomobject]@{ Port = $usePort; Created = ($useName -eq $endpointName); Login = $PartnerLogin; NewLogin = $newLogin }
        }

        foreach ($pair in @(@{ Name = "principal"; Server = $principal }, @{ Name = "mirror"; Server = $mirror })) {
            $tableAtStart[$pair.Name] = -not (@($pair.Server.Query("SELECT OBJECT_ID(N'msdb.dbo.dbm_monitor_data') AS id;"))[0].id -is [System.DBNull])
            $null = $pair.Server.Query("EXEC msdb.sys.sp_dbmmonitorupdate;")
        }

        $serviceSql = "SELECT service_account FROM sys.dm_server_services WHERE servicename LIKE N'SQL Server [(]%';"
        $principalLogin = [string]@($principal.Query($serviceSql))[0].service_account
        $mirrorLogin = [string]@($mirror.Query($serviceSql))[0].service_account
        $null = $principal.Query("CREATE DATABASE [$sessionName]; ALTER DATABASE [$sessionName] SET RECOVERY FULL;")
        $endpoints.principal = Set-NativeEndpoint -Server $principal -Port 5022 -PartnerLogin $mirrorLogin
        $endpoints.mirror = Set-NativeEndpoint -Server $mirror -Port 5023 -PartnerLogin $principalLogin
        $null = $principal.Query("BACKUP DATABASE [$sessionName] TO DISK = N'$backupStem.bak' WITH INIT;")
        $null = $principal.Query("BACKUP LOG [$sessionName] TO DISK = N'$backupStem.trn' WITH INIT;")
        $dataPath = [string]@($mirror.Query("SELECT CAST(SERVERPROPERTY('InstanceDefaultDataPath') AS nvarchar(512)) AS p;"))[0].p
        $logPath = [string]@($mirror.Query("SELECT CAST(SERVERPROPERTY('InstanceDefaultLogPath') AS nvarchar(512)) AS p;"))[0].p
        $null = $mirror.Query("RESTORE DATABASE [$sessionName] FROM DISK = N'$backupStem.bak' WITH NORECOVERY, REPLACE, MOVE N'$sessionName' TO N'$dataPath$sessionName.mdf', MOVE N'$($sessionName)_log' TO N'$logPath$($sessionName)_log.ldf';")
        $null = $mirror.Query("RESTORE LOG [$sessionName] FROM DISK = N'$backupStem.trn' WITH NORECOVERY;")
        $null = $mirror.Query("ALTER DATABASE [$sessionName] SET PARTNER = N'TCP://$($principal.ComputerName):$($endpoints.principal.Port)';")
        $null = $principal.Query("ALTER DATABASE [$sessionName] SET PARTNER = N'TCP://$($mirror.ComputerName):$($endpoints.mirror.Port)';")
        $state = ""
        for ($attempt = 0; $attempt -lt 30 -and $state -ne "SYNCHRONIZED"; $attempt++) {
            Start-Sleep -Seconds 2
            $state = [string]@($principal.Query("SELECT mirroring_state_desc FROM sys.database_mirroring WHERE database_id = DB_ID(N'$sessionName');"))[0].mirroring_state_desc
        }
        $state | Should -BeExactly "SYNCHRONIZED"

        # Each result row takes two table rows, and the procedure adds one at most every 15 seconds. The engine's own procedure adds
        # the first here, so that this block does not depend on the command under test.
        $countSql = "SELECT COUNT(*) AS total FROM msdb.dbo.dbm_monitor_data WHERE database_id = DB_ID(N'$sessionName');"
        $null = $principal.Query("EXEC msdb.sys.sp_dbmmonitorupdate @database_name = N'$sessionName';")
        $null = $mirror.Query("EXEC msdb.sys.sp_dbmmonitorupdate @database_name = N'$sessionName';")
        Start-Sleep -Seconds 17
    }

    AfterAll {
        # Each step on its own, so that one failure leaves the next to run.
        foreach ($step in @(
                { $null = $principal.Query("IF EXISTS (SELECT 1 FROM sys.database_mirroring WHERE database_id = DB_ID(N'$sessionName') AND mirroring_guid IS NOT NULL) ALTER DATABASE [$sessionName] SET PARTNER OFF;") },
                { $null = $mirror.Query("IF EXISTS (SELECT 1 FROM sys.database_mirroring WHERE database_id = DB_ID(N'$sessionName') AND mirroring_guid IS NOT NULL) ALTER DATABASE [$sessionName] SET PARTNER OFF;") },
                { $null = $mirror.Query("IF DB_ID(N'$sessionName') IS NOT NULL DROP DATABASE [$sessionName];") },
                { $null = $principal.Query("USE [master]; IF DB_ID(N'$sessionName') IS NOT NULL BEGIN ALTER DATABASE [$sessionName] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [$sessionName]; END;") },
                { if ($endpoints.principal.Created) { $null = $principal.Query("DROP ENDPOINT [$endpointName];") } },
                { if ($endpoints.mirror.Created) { $null = $mirror.Query("DROP ENDPOINT [$endpointName];") } },
                { foreach ($pair in @(@{ Endpoint = $endpoints.principal; Server = $principal }, @{ Endpoint = $endpoints.mirror; Server = $mirror })) {
                        if ($pair.Endpoint.NewLogin) {
                            # SQL Agent logs in as the service account once a login exists for it, so its sessions go first.
                            $login = $pair.Endpoint.Login
                            $null = $pair.Server.Query("DECLARE @kill nvarchar(max) = N''; SELECT @kill += N'KILL ' + CAST(session_id AS nvarchar(10)) + N';' FROM sys.dm_exec_sessions WHERE login_name = N'$login'; EXEC sys.sp_executesql @kill; DROP LOGIN [$login];")
                        }
                    } },
                # Only a table this block saw absent is dropped: when BeforeAll failed before it looked, the table stays as it was.
                { if ($false -eq $tableAtStart.principal) { $null = $principal.Query("IF OBJECT_ID(N'msdb.dbo.dbm_monitor_data') IS NOT NULL DROP TABLE msdb.dbo.dbm_monitor_data;") } },
                { if ($false -eq $tableAtStart.mirror) { $null = $mirror.Query("IF OBJECT_ID(N'msdb.dbo.dbm_monitor_data') IS NOT NULL DROP TABLE msdb.dbo.dbm_monitor_data;") } },
                { Get-ChildItem -Path "$backupStem*" -ErrorAction SilentlyContinue | Remove-Item -ErrorAction SilentlyContinue }
            )) {
            try {
                & $step
            } catch {
                Write-Warning "Cleanup: $PSItem"
            }
        }
    }

    It "adds a monitor row through -Update and returns the session's rows on the principal" {
        $rowsBefore = @($principal.Query($countSql))[0].total
        $result = @(Get-DbaDbMirrorMonitor -SqlInstance $principalInstance -Database $sessionName -Update -EnableException)
        @($principal.Query($countSql))[0].total | Should -Be ($rowsBefore + 1)
        $result.Count | Should -BeGreaterOrEqual 1
        $result[0].DatabaseName | Should -BeExactly $sessionName
        $result[0].Role | Should -Be 1
        $result[0].MirroringState | Should -Be 4
    }

    It "adds a monitor row through -Update and returns the session's rows on the mirror" {
        $rowsBefore = @($mirror.Query($countSql))[0].total
        $result = @(Get-DbaDbMirrorMonitor -SqlInstance $mirrorInstance -Database $sessionName -Update -EnableException)
        @($mirror.Query($countSql))[0].total | Should -Be ($rowsBefore + 1)
        $result.Count | Should -BeGreaterOrEqual 1
        $result[0].DatabaseName | Should -BeExactly $sessionName
        $result[0].Role | Should -Be 2
    }

    It "finds the session's rows without -Database, with no warning for the other databases" {
        $warnings = @()
        $result = @(Get-DbaDbMirrorMonitor -SqlInstance $principalInstance -EnableException -WarningAction SilentlyContinue -WarningVariable warnings)
        $warnings.Count | Should -Be 0
        @($result | Where-Object DatabaseName -eq $sessionName).Count | Should -BeGreaterOrEqual 1
    }

    It "reads a database piped from Get-DbaDatabase on the mirror" {
        $piped = Get-DbaDatabase -SqlInstance $mirrorInstance -Database $sessionName -EnableException
        $result = @($piped | Get-DbaDbMirrorMonitor -LimitResults LastRow -EnableException)
        $result.Count | Should -Be 1
        $result[0].DatabaseName | Should -BeExactly $sessionName
        $result[0].Role | Should -Be 2
    }

    It "warns for a database that is not mirrored and reads the mirrored one after it" {
        $warnings = @()
        $result = @(Get-DbaDbMirrorMonitor -SqlInstance $principalInstance -Database master, $sessionName -Update -WarningAction SilentlyContinue -WarningVariable warnings)
        $warnings.Count | Should -Be 1
        "$($warnings[0])" | Should -Match "\[Get-DbaDbMirrorMonitor\] Failure \| .*'master' is not being mirrored\. No update of the base table was done\.$"
        $result.Count | Should -BeGreaterOrEqual 1
        @($result.DatabaseName | Select-Object -Unique) | Should -BeExactly $sessionName
    }
}

Describe "Native Get-DbaDbMirrorMonitor on Azure SQL Database" -Tag IntegrationTests {
    BeforeAll {
        $splatAzureConnection = @{
            SqlInstance     = $TestConfig.AzureSqlDbServer
            Database        = $TestConfig.AzureSqlDbName
            SqlCredential   = $TestConfig.AzureSqlDbCred
            EnableException = $true
        }
        $azureServer = $null
        for ($attempt = 0; $attempt -le 6; $attempt++) {
            try {
                $azureServer = Connect-DbaInstance @splatAzureConnection
                break
            } catch {
                # A paused serverless database answers 40613 or times out while it resumes (-2, or "The wait operation timed out",
                # a Win32Exception with NativeErrorCode 258), and the lab's mobile internet can drop a name lookup (11001, "No such host is known").
                $azureError = $PSItem.Exception
                $isResuming = $false
                while ($azureError) {
                    if ($azureError.Number -in 40613, -2, 11001 -or $azureError.NativeErrorCode -eq 258 -or $azureError -is [System.TimeoutException] -or $azureError.Message -like "*timed out*" -or $azureError.Message -like "*No such host is known*") { $isResuming = $true }
                    $azureError = $azureError.InnerException
                }
                if (-not $isResuming -or $attempt -eq 6) { throw }
                Start-Sleep -Seconds 10
            }
        }
    }

    AfterAll {
        if ($azureServer) {
            $azureServer.ConnectionContext.Disconnect()
        }
    }

    # Database mirroring and msdb are absent from Azure SQL Database, and sp_dbmmonitorresults applies to SQL Server only:
    # https://learn.microsoft.com/azure/azure-sql/database/transact-sql-tsql-differences-sql-server#transact-sql-syntax-not-supported-in-azure-sql-database
    It "refuses Azure SQL Database, which has no database mirroring" -Tag "NativeChecklist:azure-sqldb" {
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $warnings = @()
        @(Get-DbaDbMirrorMonitor -SqlInstance $azureServer -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings).Count | Should -Be 0
        $warnings.Count | Should -Be 1
        "$($warnings[0])" | Should -BeLike "*Failure | *Azure SQL Database not supported*"
        { Get-DbaDbMirrorMonitor -SqlInstance $azureServer -EnableException } | Should -Throw "*Azure SQL Database not supported*"
    }

    It "refuses a database piped from Azure SQL Database the same way" -Tag "NativeChecklist:azure-sqldb" {
        $azureDatabase = $azureServer.Databases[$TestConfig.AzureSqlDbName]
        $warnings = @()
        @($azureDatabase | Get-DbaDbMirrorMonitor -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings).Count | Should -Be 0
        $warnings.Count | Should -Be 1
        "$($warnings[0])" | Should -BeLike "*Failure | *Azure SQL Database not supported*"
        { $azureDatabase | Get-DbaDbMirrorMonitor -EnableException } | Should -Throw "*Azure SQL Database not supported*"
    }
}
