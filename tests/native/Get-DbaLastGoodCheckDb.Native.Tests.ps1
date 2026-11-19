#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaLastGoodCheckDb",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- The pinned command has no SupportsShouldProcess, WhatIf or Confirm parameters; it only reads CHECKDB dates.

Describe "Native Get-DbaLastGoodCheckDb" -Tag IntegrationTests {
    BeforeAll {
        # The legs of one SQL version share the instances and run one after the other; every name carries this run's number.
        $instance = $TestConfig.InstanceSingle
        $server = Connect-DbaInstance -SqlInstance $instance -EnableException
        $stamp = Get-Random
        $dbChecked = "dbatoolsci_nlgc_chk_$stamp"
        $dbNew = "dbatoolsci_nlgc_new_$stamp"
        $dbOffline = "dbatoolsci_nlgc_off_$stamp"
        foreach ($name in $dbChecked, $dbNew, $dbOffline) {
            $null = $server.Query("CREATE DATABASE [$name];")
        }
        $null = $server.Query("DBCC CHECKDB ([$dbChecked]) WITH NO_INFOMSGS;")
        $null = $server.Query("ALTER DATABASE [$dbOffline] SET OFFLINE WITH ROLLBACK IMMEDIATE;")
        $server.Databases.Refresh()
        $badInstance = "Data Source=tcp:127.0.0.1,1;Integrated Security=True;Connect Timeout=1;Pooling=False"
        $nestedStem = "^dbatools_Get-DbaDatabase(,|$)"
        $columns = "ComputerName", "InstanceName", "SqlInstance", "Database", "DatabaseCreated", "LastGoodCheckDb", "DaysSinceDbCreated", "DaysSinceLastGoodCheckDb", "Status", "DataPurityEnabled", "CreateVersion", "DbccFlags"

        # What DBCC DBINFO says of a database, read on its own: the newest dbi_dbccLastKnownGood ($null for the 1900 value
        # that means never), dbi_createVersion and dbi_dbccFlags.
        function Get-NativeDbInfo {
            param($Connection, [string]$Name)
            $fields = @($Connection.Query("DBCC DBINFO ([$($Name.Replace(']', ']]'))]) WITH TABLERESULTS;"))
            $lastGood = @($fields | Where-Object Field -eq "dbi_dbccLastKnownGood" | ForEach-Object { [datetime]$PSItem.Value } | Sort-Object -Descending)[0]
            if ($lastGood -eq (New-Object DateTime 1900, 1, 1)) {
                $lastGood = $null
            }
            [pscustomobject]@{
                LastGood      = $lastGood
                CreateVersion = [int]($fields | Where-Object Field -eq "dbi_createVersion").Value
                DbccFlags     = [int]($fields | Where-Object Field -eq "dbi_dbccFlags").Value
            }
        }
    }

    AfterAll {
        # A database just brought back online can still be held by its own startup for a moment ("currently in use"), so
        # each drop takes the database to single user first and is tried again a few times.
        foreach ($name in $dbChecked, $dbNew, $dbOffline) {
            for ($attempt = 1; $attempt -le 6; $attempt++) {
                try {
                    $null = $server.Query("USE [master]; IF DB_ID(N'$name') IS NOT NULL BEGIN ALTER DATABASE [$name] SET ONLINE; ALTER DATABASE [$name] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [$name]; END;")
                    break
                } catch {
                    if ($attempt -eq 6) { throw }
                    Start-Sleep -Seconds 5
                }
            }
        }
    }

    Context "Output" {
        It "reports a checked database as DBCC DBINFO shows it, as sysadmin" {
            $row = @(Get-DbaLastGoodCheckDb -SqlInstance $instance -Database $dbChecked -EnableException)
            $row.Count | Should -Be 1
            @($row[0].PSObject.Properties.Name) | Should -Be $columns
            $info = Get-NativeDbInfo $server $dbChecked
            $info.LastGood | Should -Not -BeNullOrEmpty
            $row[0].Database | Should -BeExactly $dbChecked
            $row[0].SqlInstance | Should -Be $server.DomainInstanceName
            $row[0].InstanceName | Should -Be $server.ServiceName
            $row[0].ComputerName | Should -Not -BeNullOrEmpty
            $row[0].DatabaseCreated | Should -Be $server.Databases[$dbChecked].CreateDate
            $row[0].LastGoodCheckDb | Should -BeOfType [datetime]
            $row[0].LastGoodCheckDb | Should -Be $info.LastGood
            $row[0].DaysSinceLastGoodCheckDb | Should -BeOfType [int]
            $row[0].DaysSinceLastGoodCheckDb | Should -Be ((Get-Date) - $info.LastGood).Days
            $row[0].DaysSinceDbCreated | Should -BeOfType [double]
            $row[0].Status | Should -BeExactly "Ok"
            $row[0].CreateVersion | Should -BeOfType [int]
            $row[0].CreateVersion | Should -Be $info.CreateVersion
            $row[0].DbccFlags | Should -BeOfType [int]
            $row[0].DbccFlags | Should -Be $info.DbccFlags
            $row[0].DataPurityEnabled | Should -Be (-not ($info.CreateVersion -lt 611 -and $info.DbccFlags -eq 0))
        }

        It "reports no LastGoodCheckDb and no days since for a database never checked" {
            $row = @(Get-DbaLastGoodCheckDb -SqlInstance $instance -Database $dbNew -EnableException)
            $row.Count | Should -Be 1
            (Get-NativeDbInfo $server $dbNew).LastGood | Should -BeNullOrEmpty
            $row[0].LastGoodCheckDb | Should -BeNullOrEmpty
            $row[0].DaysSinceLastGoodCheckDb | Should -BeNullOrEmpty
            $row[0].Status | Should -BeExactly "New database, not checked yet"
            $row[0].DataPurityEnabled | Should -BeOfType [bool]
        }

        It "returns the selected databases in the order sys.databases lists them, without the excluded ones" {
            $expected = @($server.Query("SELECT name FROM sys.databases WHERE name IN (N'$dbChecked', N'$dbNew') ORDER BY database_id;") | ForEach-Object { $PSItem.name })
            @(Get-DbaLastGoodCheckDb -SqlInstance $instance -Database $dbNew, $dbChecked -EnableException).Database | Should -Be $expected
            @(Get-DbaLastGoodCheckDb -SqlInstance $instance -Database $dbNew, $dbChecked -ExcludeDatabase $dbNew -EnableException).Database | Should -Be @($dbChecked)
            @(Get-DbaLastGoodCheckDb -SqlInstance $instance -Database $dbChecked.ToUpperInvariant() -EnableException).Database | Should -Be @($dbChecked)
        }

        It "honours a wildcard in -Database" {
            $rows = @(Get-DbaLastGoodCheckDb -SqlInstance $instance -Database "dbatoolsci_nlgc_*_$stamp" -ExcludeDatabase $dbOffline -WarningAction SilentlyContinue)
            ($rows.Database | Sort-Object) | Should -Be (@($dbChecked, $dbNew) | Sort-Object)
        }

        It "honours a wildcard in -ExcludeDatabase" {
            $rows = @(Get-DbaLastGoodCheckDb -SqlInstance $instance -Database $dbChecked, $dbNew -ExcludeDatabase "dbatoolsci_nlgc_new_*" -EnableException)
            $rows.Database | Should -Be @($dbChecked)
        }
    }

    Context "Input objects" {
        It "reads several databases, piped or named" -Tag "NativeChecklist:pipeline-multiple" {
            $databases = @(Get-DbaDatabase -SqlInstance $instance -Database $dbChecked, $dbNew -EnableException)
            ($databases | Get-DbaLastGoodCheckDb -EnableException).Database | Should -Be $databases.Name
            (Get-DbaLastGoodCheckDb -InputObject $databases -EnableException).Database | Should -Be $databases.Name
        }

        It "reads the databases of a server piped in" {
            $rows = @($server | Get-DbaLastGoodCheckDb -Database $dbChecked -EnableException)
            $rows.Database | Should -Be @($dbChecked)
        }

        It "reads the databases of a server object given to -InputObject" {
            $rows = @(Get-DbaLastGoodCheckDb -InputObject $server -Database $dbChecked -WarningAction SilentlyContinue -ErrorAction SilentlyContinue)
            $rows.Database | Should -Be @($dbChecked)
        }

        It "warns for a value that is neither a server nor a database and reads nothing more of that call" {
            $warnings = @()
            $database = Get-DbaDatabase -SqlInstance $instance -Database $dbChecked -EnableException
            @(Get-DbaLastGoodCheckDb -InputObject "notaserver", $database -WarningAction SilentlyContinue -WarningVariable warnings).Count | Should -Be 0
            $warnings.Count | Should -Be 1
            "$($warnings[0])" | Should -Match "\[Get-DbaLastGoodCheckDb\] InputObject is not a server or database\.$"
        }

        It "throws that under -EnableException" -Tag "NativeChecklist:enable-exception" {
            $failure = $null
            try {
                $null = Get-DbaLastGoodCheckDb -InputObject "notaserver" -EnableException
            } catch {
                $failure = $PSItem
            }
            $failure.Exception.Message | Should -BeExactly "InputObject is not a server or database."
            $failure.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaLastGoodCheckDb*"
        }
    }

    # A null element: $input.GetType() fails (InvokeMethodOnNull) and $inputType keeps the element before it, so after an instance the nested
    # Get-DbaDatabase gets -SqlInstance $null and its binder refuses it (harness-edits.md, "binder fault records in every port"; probes
    # pin-lastgood-20261106 and pin-lastgood-binder-20261106, both editions).
    Context "Null elements" {
        BeforeAll {
            $bindingNull = "Cannot bind argument to parameter 'SqlInstance' because it is null."

            # A plain call outside any try runs in a runspace of its own: Pester runs every It inside one.
            function Invoke-NativeOutsideTry {
                param([hashtable]$Arguments, [string]$Script = 'param($Arguments, $Target) Get-DbaLastGoodCheckDb @Arguments; "next statement"')
                $outsideState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
                $outsideType = (Get-Command Get-DbaLastGoodCheckDb -CommandType Cmdlet).ImplementingType
                $outsideState.Commands.Add((New-Object System.Management.Automation.Runspaces.SessionStateCmdletEntry -ArgumentList "Get-DbaLastGoodCheckDb", $outsideType, $null))
                $outsideRunspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($outsideState)
                $outsideShell = [System.Management.Automation.PowerShell]::Create()
                $outsideOutput = New-Object "System.Management.Automation.PSDataCollection[psobject]"
                $outsideStop = $null
                try {
                    $outsideRunspace.Open()
                    $outsideShell.Runspace = $outsideRunspace
                    $null = $outsideShell.AddScript($Script).AddArgument($Arguments).AddArgument($server)
                    try {
                        $null = $outsideShell.Invoke($null, $outsideOutput)
                    } catch {
                        # The stop leaves the runspace's script through Invoke, as a method call's exception.
                        $outsideStop = $PSItem.Exception.InnerException
                    }
                    [pscustomobject]@{
                        Databases = @($outsideOutput | Where-Object { $null -ne $PSItem.psobject.Properties["DbccFlags"] } | ForEach-Object { $PSItem.Database })
                        Next      = @($outsideOutput | Where-Object { "$($PSItem.psobject.BaseObject)" -ceq "next statement" }).Count -gt 0
                        Errors    = @($outsideShell.Streams.Error)
                        Warnings  = @($outsideShell.Streams.Warning)
                        Stop      = $outsideStop
                    }
                } finally {
                    $outsideShell.Dispose()
                    $outsideRunspace.Dispose()
                }
            }

            function Assert-NativeNullElementRecord {
                param($Record)
                $Record.Exception.GetType().FullName | Should -BeExactly "System.Management.Automation.RuntimeException"
                $Record.Exception.Message | Should -BeExactly "You cannot call a method on a null-valued expression."
                $Record.FullyQualifiedErrorId | Should -Match "^InvokeMethodOnNull(,|$)"
                "$($Record.CategoryInfo.Category)" | Should -BeExactly "InvalidOperation"
                $Record.TargetObject | Should -BeNullOrEmpty
            }

            function Assert-NativeBindingRecord {
                param($Record)
                $Record.Exception.GetType().FullName | Should -BeExactly "System.Management.Automation.ParameterBindingException"
                $Record.Exception.Message | Should -BeExactly $bindingNull
                $Record.FullyQualifiedErrorId | Should -Match "^ParameterArgumentValidationErrorNullNotAllowed,"
                "$($Record.CategoryInfo.Category)" | Should -BeExactly "InvalidData"
                $Record.CategoryInfo.Reason | Should -BeExactly "ParameterBindingValidationException"
                $Record.CategoryInfo.Activity | Should -BeExactly "Get-DbaDatabase"
                $Record.TargetObject | Should -BeNullOrEmpty
            }
        }

        It "reads nothing and writes nothing for -SqlInstance <Form>" -ForEach @(
            @{ Form = "`$null"; Value = $null }
            @{ Form = "@()"; Value = @() }
        ) {
            $outside = Invoke-NativeOutsideTry @{ SqlInstance = $Value; Database = $dbChecked }
            $outside.Databases.Count | Should -Be 0
            $outside.Errors.Count | Should -Be 0
            $outside.Warnings.Count | Should -Be 0
            $outside.Next | Should -BeTrue
        }

        It "outside any try, a null first writes its record, warns that it is not a server or database and reads nothing more of that call" {
            $outside = Invoke-NativeOutsideTry @{ SqlInstance = @($null, $server); Database = $dbChecked }
            $outside.Errors.Count | Should -Be 1
            Assert-NativeNullElementRecord -Record $outside.Errors[0]
            $outside.Warnings.Count | Should -Be 1
            "$($outside.Warnings[0])" | Should -Match "\[Get-DbaLastGoodCheckDb\] InputObject is not a server or database\.$"
            $outside.Databases.Count | Should -Be 0
            $outside.Next | Should -BeTrue
        }

        # Correction null-element-repeat.
        It "outside any try, a null after an instance writes its record and the nested binder record and reads that instance once" {
            $outside = Invoke-NativeOutsideTry @{ SqlInstance = @($server, $null); Database = $dbChecked }
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Errors.Count | Should -Be 2
            Assert-NativeNullElementRecord -Record $outside.Errors[0]
            Assert-NativeBindingRecord -Record $outside.Errors[1]
            $outside.Warnings.Count | Should -Be 0
            $outside.Databases | Should -Be @($dbChecked)
            $outside.Next | Should -BeTrue
        }

        # Corrections null-element-repeat and server-input.
        It "outside any try, a null after a server given to -InputObject writes its record and the nested binder record and reads that server once" {
            $outside = Invoke-NativeOutsideTry @{ InputObject = @($server, $null); Database = $dbChecked }
            $outside.Errors.Count | Should -Be 2
            Assert-NativeNullElementRecord -Record $outside.Errors[0]
            Assert-NativeBindingRecord -Record $outside.Errors[1]
            $outside.Databases | Should -Be @($dbChecked)
            $outside.Next | Should -BeTrue
        }

        # Correction null-element-repeat.
        It "outside any try, a piped array holding an instance and a null reads that instance once: <Form>" -ForEach @(
            @{ Form = "alone"; Script = 'param($Arguments, $Target) $record = @($Target, $null); , $record | Get-DbaLastGoodCheckDb @Arguments; "next statement"'; Reads = 1 }
            @{ Form = "first"; Script = 'param($Arguments, $Target) $record = @($Target, $null); $record, $Target | Get-DbaLastGoodCheckDb @Arguments; "next statement"'; Reads = 2 }
            @{ Form = "between instances"; Script = 'param($Arguments, $Target) $record = @($Target, $null); $Target, $record, $Target | Get-DbaLastGoodCheckDb @Arguments; "next statement"'; Reads = 3 }
        ) {
            $outside = Invoke-NativeOutsideTry @{ Database = $dbChecked } -Script $Script
            $outside.Errors.Count | Should -Be 2
            Assert-NativeNullElementRecord -Record $outside.Errors[0]
            Assert-NativeBindingRecord -Record $outside.Errors[1]
            $outside.Databases.Count | Should -Be $Reads
            $outside.Next | Should -BeTrue
        }

        It "outside any try, -EnableException ends the command at the null element's record and the script goes on" -Tag "NativeChecklist:enable-exception" {
            $outside = Invoke-NativeOutsideTry @{ SqlInstance = @($server, $null); Database = $dbChecked; EnableException = $true }
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Errors.Count | Should -Be 1
            Assert-NativeNullElementRecord -Record $outside.Errors[0]
            $outside.Databases | Should -Be @($dbChecked)
            $outside.Next | Should -BeTrue
        }

        It "outside any try, -ErrorAction Stop turns the null element's record into the stop PowerShell gives WriteError" {
            $outside = Invoke-NativeOutsideTry @{ SqlInstance = @($server, $null); Database = $dbChecked; ErrorAction = "Stop" }
            $outside.Stop | Should -BeOfType System.Management.Automation.ActionPreferenceStopException
            Assert-NativeNullElementRecord -Record $outside.Stop.ErrorRecord
            $outside.Databases | Should -Be @($dbChecked)
            $outside.Next | Should -BeFalse
        }

        It "inside a caller's try, the catch receives the null element's record and the command does not go on" {
            $failure = $null
            $rows = New-Object System.Collections.ArrayList
            try {
                Get-DbaLastGoodCheckDb -SqlInstance @($server, $null) -Database $dbChecked -WarningAction SilentlyContinue | ForEach-Object { $null = $rows.Add($PSItem) }
            } catch {
                $failure = $PSItem
            }
            Assert-NativeNullElementRecord -Record $failure
            $rows.Database | Should -Be @($dbChecked)
        }
    }

    Context "An inaccessible database" {
        It "warns that it is skipped and reads the next one" {
            $warnings = @()
            $errors = @()
            $rows = @(Get-DbaLastGoodCheckDb -SqlInstance $instance -Database $dbOffline, $dbChecked -WarningAction SilentlyContinue -WarningVariable warnings -ErrorVariable errors)
            $rows.Database | Should -Be @($dbChecked)
            $warnings.Count | Should -Be 1
            "$($warnings[0])" | Should -Match ("\[Get-DbaLastGoodCheckDb\] The database " + [regex]::Escape($dbOffline) + " is not accessible\. Skipping database\.$")
            $errors.Count | Should -Be 1
            $errors[0].FullyQualifiedErrorId | Should -Match "^dbatools_Get-DbaLastGoodCheckDb(,|$)"
        }

        It "throws at it under -EnableException" -Tag "NativeChecklist:enable-exception" {
            $failure = $null
            $rows = @()
            try {
                $rows = @(Get-DbaLastGoodCheckDb -SqlInstance $instance -Database $dbOffline, $dbChecked -EnableException)
            } catch {
                $failure = $PSItem
            }
            $rows.Count | Should -Be 0
            $failure.Exception.Message | Should -BeExactly "The database $dbOffline is not accessible. Skipping database."
        }
    }

    Context "Failed instances" -Tag "NativeChecklist:multi-instance-failure" {
        It "warns as Get-DbaDatabase for an instance it cannot reach and reads the others, -EnableException or not" -Tag "NativeChecklist:enable-exception" {
            foreach ($enableException in $false, $true) {
                $warnings = @()
                $errors = @()
                $rows = @(Get-DbaLastGoodCheckDb -SqlInstance $instance, $badInstance, $instance -Database $dbChecked -EnableException:$enableException -WarningAction SilentlyContinue -WarningVariable warnings -ErrorVariable errors)
                $rows.Database | Should -Be @($dbChecked, $dbChecked)
                $warnings.Count | Should -Be 1
                "$($warnings[0])" | Should -Match "\[Get-DbaDatabase\] Failure \| "
                # The nested Get-DbaDatabase's Stop-Function record reaches -ErrorVariable (watchman 22dc72e0), nothing else.
                $errors.Count | Should -Be 1
                $errors[0].FullyQualifiedErrorId | Should -Match $nestedStem
                $errors[0].CategoryInfo.Category | Should -Be "ConnectionError"
                "$($errors[0].TargetObject)" | Should -BeExactly ([Dataplat.Dbatools.Parameter.DbaInstanceParameter]$badInstance).FullSmoName
            }
        }
    }

    Context "No input" {
        It "warns that an instance or an input object is needed, under -EnableException:`$false too" -Tag "NativeChecklist:switch-false" {
            $warnings = @()
            @(Get-DbaLastGoodCheckDb -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings).Count | Should -Be 0
            $warnings.Count | Should -Be 1
            "$($warnings[0])" | Should -Match "\[Get-DbaLastGoodCheckDb\] You must specify either a SQL instance or supply an InputObject$"
        }

        It "only warns under -EnableException, as the pinned Write-Message does" -Tag "NativeChecklist:enable-exception" {
            $warnings = @()
            $failure = $null
            try {
                $null = Get-DbaLastGoodCheckDb -EnableException -WarningAction SilentlyContinue -WarningVariable warnings
            } catch {
                $failure = $PSItem
            }
            $failure | Should -BeNullOrEmpty
            $warnings.Count | Should -Be 1
            "$($warnings[0])" | Should -Match "\[Get-DbaLastGoodCheckDb\] You must specify either a SQL instance or supply an InputObject$"
        }
    }

    Context "The caller's database" {
        It "is left as it was when database objects are read" {
            $callerServer = Connect-DbaInstance -SqlInstance $instance -NonPooledConnection -EnableException
            try {
                $before = $callerServer.ConnectionContext.ExecuteScalar("SELECT DB_NAME()")
                $rows = @(Get-DbaLastGoodCheckDb -InputObject $callerServer.Databases[$dbChecked] -EnableException)
                $rows.Database | Should -Be @($dbChecked)
                $callerServer.ConnectionContext.ExecuteScalar("SELECT DB_NAME()") | Should -Be $before
            } finally {
                $null = $callerServer | Disconnect-DbaInstance
            }
        }
    }
}

Describe "Native Get-DbaLastGoodCheckDb over SQL authentication" -Tag IntegrationTests {
    BeforeAll {
        # sqlwhale22 is shared: its login is unique per leg and run. The SQL login is sysadmin there; the one made here has no role.
        $loginInstance = $TestConfig.InstanceSqlLogin
        $loginCred = $TestConfig.SqlLoginCred
        $loginServer = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $loginCred -EnableException
        $lowName = "dbatoolsci_nlgcl_$(Get-Random)"
        $lowPassword = "Nlg-$([guid]::NewGuid().ToString('N'))"
        $lowCred = New-Object System.Management.Automation.PSCredential -ArgumentList $lowName, (ConvertTo-SecureString -String $lowPassword -AsPlainText -Force)
        $null = $loginServer.Query("CREATE LOGIN [$lowName] WITH PASSWORD = N'$lowPassword', CHECK_POLICY = OFF;")
        $masterLastGood = $loginServer.Query("SELECT CAST(DATABASEPROPERTYEX(N'master', 'LastGoodCheckDbTime') AS datetime) AS lastgood;").lastgood
        if ($masterLastGood -eq (New-Object DateTime 1900, 1, 1)) {
            $masterLastGood = $null
        }
    }

    AfterAll {
        $null = $loginServer.Query("DECLARE @kill nvarchar(max) = N''; SELECT @kill += N'KILL ' + CAST(session_id AS nvarchar(10)) + N';' FROM sys.dm_exec_sessions WHERE login_name = N'$lowName'; EXEC sys.sp_executesql @kill;")
        $null = $loginServer.Query("IF SUSER_ID(N'$lowName') IS NOT NULL DROP LOGIN [$lowName];")
    }

    Context "SQL login" -Tag NativeChecklist:sql-login {
        It "works with -SqlCredential" {
            $row = @(Get-DbaLastGoodCheckDb -SqlInstance $loginInstance -SqlCredential $loginCred -Database master -EnableException)
            $row.Database | Should -Be @("master")
            $row[0].SqlInstance | Should -Be $loginServer.DomainInstanceName
            $row[0].CreateVersion | Should -BeOfType [int]
        }

        It "warns without the credential, as the nested Get-DbaDatabase does" {
            $warnings = @()
            @(Get-DbaLastGoodCheckDb -SqlInstance $loginInstance -Database master -WarningAction SilentlyContinue -WarningVariable warnings).Count | Should -Be 0
            $warnings.Count | Should -Be 1
            "$($warnings[0])" | Should -Match "\[Get-DbaDatabase\] Failure \| Login failed"
        }

        It "only warns without the credential under -EnableException, which the pinned function never passes to Get-DbaDatabase" {
            $warnings = @()
            @(Get-DbaLastGoodCheckDb -SqlInstance $loginInstance -Database master -EnableException -WarningAction SilentlyContinue -WarningVariable warnings).Count | Should -Be 0
            "$($warnings[0])" | Should -Match "\[Get-DbaDatabase\] Failure \| Login failed"
        }
    }

    Context "A login that is not sysadmin" {
        It "reads LastGoodCheckDbTime and reports no DBCC DBINFO values" {
            $row = @(Get-DbaLastGoodCheckDb -SqlInstance $loginInstance -SqlCredential $lowCred -Database master -EnableException)
            $row.Database | Should -Be @("master")
            $row[0].LastGoodCheckDb | Should -Be $masterLastGood
            $row[0].DataPurityEnabled | Should -BeNullOrEmpty
            $row[0].CreateVersion | Should -BeNullOrEmpty
            $row[0].DbccFlags | Should -BeNullOrEmpty
        }

        It "reports no CreateVersion or DbccFlags for a database read without sysadmin after one read with it" {
            $lowServer = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $lowCred -EnableException
            $rows = @($loginServer.Databases["master"], $lowServer.Databases["master"] | Get-DbaLastGoodCheckDb -EnableException)
            $rows.Count | Should -Be 2
            $rows[0].CreateVersion | Should -BeOfType [int]
            $rows[1].DataPurityEnabled | Should -BeNullOrEmpty
            $rows[1].CreateVersion | Should -BeNullOrEmpty
            $rows[1].DbccFlags | Should -BeNullOrEmpty
        }
    }
}

Describe "Native Get-DbaLastGoodCheckDb on Azure SQL Database" -Tag IntegrationTests {
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
                # A paused serverless database answers 40613 or times out (-2) while it resumes, and the lab's mobile
                # internet can drop a name lookup (11001, "No such host is known") or a wait ("The wait operation timed out",
                # Win32Exception 258, or a TimeoutException).
                $azureError = $PSItem.Exception
                $isResuming = $false
                while ($azureError) {
                    if ($azureError.Number -in 40613, -2, 11001) { $isResuming = $true }
                    if ($azureError -is [System.ComponentModel.Win32Exception] -and $azureError.NativeErrorCode -eq 258) { $isResuming = $true }
                    if ($azureError -is [System.TimeoutException]) { $isResuming = $true }
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

    # LastGoodCheckDbTime applies to Azure SQL Database (Learn: DATABASEPROPERTYEX, LastGoodCheckDbTime; SMO Database.LastGoodCheckDbTime
    # carries SfcPropertyFlags.SqlAzureDatabase). The connection is not sysadmin there, so DBCC DBINFO is never run.
    It "reads the database's LastGoodCheckDbTime and reports no DBCC DBINFO values" -Tag "NativeChecklist:azure-sqldb" {
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $independent = $azureServer.Query("SELECT CAST(DATABASEPROPERTYEX(DB_NAME(), 'LastGoodCheckDbTime') AS datetime) AS lastgood, create_date FROM sys.databases WHERE name = DB_NAME();")
        $expectedLastGood = $independent.lastgood
        if ($expectedLastGood -is [DBNull] -or $expectedLastGood -eq (New-Object DateTime 1900, 1, 1)) {
            $expectedLastGood = $null
        }
        $row = @(Get-DbaLastGoodCheckDb -SqlInstance $azureServer -Database $TestConfig.AzureSqlDbName -EnableException)
        $row.Count | Should -Be 1
        $row[0].Database | Should -BeExactly $TestConfig.AzureSqlDbName
        $row[0].DatabaseCreated | Should -Be $independent.create_date
        $row[0].LastGoodCheckDb | Should -Be $expectedLastGood
        $row[0].DataPurityEnabled | Should -BeNullOrEmpty
        $row[0].CreateVersion | Should -BeNullOrEmpty
        $row[0].DbccFlags | Should -BeNullOrEmpty
        $expectedStatus = "CheckDB should be performed"
        if ($expectedLastGood -and ((Get-Date) - $expectedLastGood).Days -lt 7) {
            $expectedStatus = "Ok"
        } elseif (((Get-Date) - $independent.create_date).TotalDays -lt 7) {
            $expectedStatus = "New database, not checked yet"
        }
        $row[0].Status | Should -BeExactly $expectedStatus
    }
}
