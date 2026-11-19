#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Copy-DbaAgentSchedule",
    $PSDefaultParameterValues = $TestConfig.Defaults
)
# NativeChecklist: azure-sqldb N/A -- SQL Agent shared schedules are unavailable on Azure SQL Database; refuse with AzureUnsupported. https://learn.microsoft.com/data-migration/sql-server/database/assessment-rules#sql-agent-jobs

Describe "Native Copy-DbaAgentSchedule" -Tag IntegrationTests {
    BeforeAll {
        $source = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy1 -EnableException
        $destination = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy2 -EnableException
        $prefix = 'nativeschedule_' + [guid]::NewGuid().ToString('N')
        $names = @(($prefix + '_a'), ($prefix + '_b'))
        $schedules = @()
        foreach ($name in $names) {
            $schedule = New-Object Microsoft.SqlServer.Management.Smo.Agent.JobSchedule -ArgumentList $source.JobServer, $name
            $schedule.FrequencyTypes = 'Daily'
            $schedule.FrequencyInterval = 1
            $schedule.ActiveStartTimeOfDay = [timespan]::FromHours(2)
            $schedule.Create()
            $schedules += $schedule
        }
    }
    AfterEach {
        $destination.JobServer.SharedSchedules.Refresh()
        foreach ($name in $names) {
            if ($destination.JobServer.SharedSchedules[$name]) { $destination.JobServer.SharedSchedules[$name].Drop() }
        }
    }
    AfterAll {
        $source.JobServer.SharedSchedules.Refresh()
        foreach ($name in $names) {
            if ($source.JobServer.SharedSchedules[$name]) { $source.JobServer.SharedSchedules[$name].Drop() }
        }
    }
    It "honors documented Schedule wildcard filters" {
        $copy = @{
            Source = $source
            Destination = $destination
            Schedule = "$prefix*"
            Confirm = $false
            EnableException = $true
        }
        $results = @(Copy-DbaAgentSchedule @copy)
        $results.Count | Should -Be 2
        @($results | Where-Object Status -ne Successful).Count | Should -Be 0
        $destination.JobServer.SharedSchedules.Refresh()
        foreach ($name in $names) {
            $destination.JobServer.SharedSchedules[$name].ActiveStartTimeOfDay | Should -Be ([timespan]::FromHours(2))
        }
    }
    It "uses Id to refine the supplied Schedule filter" {
        $copy = @{
            Source = $source
            Destination = $destination
            Schedule = $names[0]
            Id = $schedules[1].ID
            Confirm = $false
            EnableException = $true
        }
        @(Copy-DbaAgentSchedule @copy).Count | Should -Be 0
        $destination.JobServer.SharedSchedules.Refresh()
        foreach ($name in $names) { $destination.JobServer.SharedSchedules[$name] | Should -BeNullOrEmpty }
    }
    It "copies multiple piped schedules with false switches" -Tag NativeChecklist:pipeline-multiple, NativeChecklist:switch-false {
        $copy = @{
            Destination = $destination
            Force = $false
            Confirm = $false
            EnableException = $false
        }
        $results = @($schedules | Copy-DbaAgentSchedule @copy)
        $results.Count | Should -Be 2
        @($results | Where-Object Status -ne Successful).Count | Should -Be 0
    }
    It "does not create schedules under WhatIf" -Tag NativeChecklist:whatif-confirm {
        $copy = @{
            Destination = $destination
            Force = $true
            WhatIf = $true
            Confirm = $false
        }
        @($schedules | Copy-DbaAgentSchedule @copy).Count | Should -Be 0
        $destination.JobServer.SharedSchedules.Refresh()
        foreach ($name in $names) { $destination.JobServer.SharedSchedules[$name] | Should -BeNullOrEmpty }
    }
    It "continues after a failed destination" -Tag NativeChecklist:multi-instance-failure, NativeChecklist:enable-exception {
        $copy = @{
            Destination = @('tcp:127.0.0.1,1', $destination)
            InputObject = $schedules[0]
            EnableException = $false
            Confirm = $false
            WarningVariable = 'warnings'
            WarningAction = 'SilentlyContinue'
        }
        $results = @(Copy-DbaAgentSchedule @copy)
        $results.Count | Should -Be 1
        $results[0].Status | Should -Be Successful
        ($warnings -join ' ') | Should -Match Failure
    }
    It "refuses an Azure destination and continues copying to the next destination" -Tag NativeChecklist:multi-instance-failure {
        $azureConnection = @{
            SqlInstance = $TestConfig.AzureSqlDbServer
            Database = $TestConfig.AzureSqlDbName
            SqlCredential = $TestConfig.AzureSqlDbCred
            EnableException = $true
        }
        $azureServer = $null
        for ($attempt = 0; $attempt -le 6; $attempt++) {
            try {
                $azureServer = Connect-DbaInstance @azureConnection
                break
            } catch {
                $azureError = $_.Exception
                $isResuming = $false
                while ($azureError) {
                    if ($azureError.Number -in 40613, -2 -or $azureError -is [System.TimeoutException]) { $isResuming = $true }
                    $azureError = $azureError.InnerException
                }
                if (-not $isResuming -or $attempt -eq 6) { throw }
                Start-Sleep -Seconds 10
            }
        }
        try {
            $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly 'SqlDatabase'
            $azureWarnings = @()
            $copy = @{
                Destination = @($azureServer, $destination)
                InputObject = $schedules[0]
                EnableException = $false
                Confirm = $false
                WarningVariable = 'azureWarnings'
                WarningAction = 'SilentlyContinue'
            }
            $results = @(Copy-DbaAgentSchedule @copy)
            $results.Count | Should -Be 1
            $results[0].Status | Should -Be Successful
            ($azureWarnings -join ' ') | Should -Match ([regex]::Escape('Azure SQL Database not supported'))
            $destination.JobServer.SharedSchedules.Refresh()
            $destination.JobServer.SharedSchedules[$names[0]].ActiveStartTimeOfDay | Should -Be ([timespan]::FromHours(2))
        } finally { $azureServer.ConnectionContext.Disconnect() }
    }
    It "throws on connection failure with EnableException" -Tag NativeChecklist:enable-exception {
        $copy = @{
            Destination = 'tcp:127.0.0.1,1'
            InputObject = $schedules[0]
            EnableException = $true
            Confirm = $false
        }
        { Copy-DbaAgentSchedule @copy } | Should -Throw
    }
}

Describe 'Copy-DbaAgentSchedule destination read faults' -Tag IntegrationTests {
    BeforeAll {
        $sourceAdmin = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy1 -EnableException
        # The denied reader is a SQL login; pool instances are not guaranteed to allow SQL authentication.
        $targetAdmin = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSqlLogin -SqlCredential $TestConfig.SqlLoginCred -EnableException
        $targetAdmin.ConnectionContext.ExecuteScalar("SELECT CONVERT(int, SERVERPROPERTY('IsIntegratedSecurityOnly'));") | Should -Be 0
        $token = 'native_schedule_read_' + [guid]::NewGuid().ToString('N')
        $password = 'Ns!' + [guid]::NewGuid().ToString('N')
        $readers = New-Object 'System.Collections.Generic.List[object]'
        $null = $targetAdmin.ConnectionContext.ExecuteNonQuery("CREATE LOGIN [$token] WITH PASSWORD=N'$password', CHECK_POLICY=OFF; GRANT VIEW ANY DEFINITION TO [$token]; USE msdb; CREATE USER [$token] FOR LOGIN [$token]; ALTER ROLE SQLAgentReaderRole ADD MEMBER [$token];")
        foreach ($admin in $sourceAdmin, $targetAdmin) {
            $null = $admin.ConnectionContext.ExecuteNonQuery("EXEC msdb.dbo.sp_add_schedule @schedule_name=N'$token', @enabled=0, @freq_type=4, @freq_interval=1;")
        }
        $sourceAdmin.JobServer.SharedSchedules.Refresh()
        $inputSchedule = $sourceAdmin.JobServer.SharedSchedules[$token]

        function Invoke-ScheduleOutsideTry([hashtable]$arguments) {
            $state = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
            $type = (Get-Command Copy-DbaAgentSchedule -CommandType Cmdlet).ImplementingType
            $entry = New-Object System.Management.Automation.Runspaces.SessionStateCmdletEntry -ArgumentList 'Copy-DbaAgentSchedule', $type, $null
            $state.Commands.Add($entry)
            $runspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($state)
            $shell = [System.Management.Automation.PowerShell]::Create()
            $output = New-Object 'System.Management.Automation.PSDataCollection[psobject]'
            try {
                $runspace.Open()
                $shell.Runspace = $runspace
                $body = {
                    param($copyArguments)
                    $copyErrors = @()
                    Copy-DbaAgentSchedule @copyArguments -ErrorVariable copyErrors
                    $scheduleNextStatement = $true
                }
                $null = $shell.AddScript($body.ToString()).AddArgument($arguments)
                $stop = $null
                try { $null = $shell.Invoke($null, $output) } catch { $stop = $PSItem }
                [pscustomobject]@{ Output = @($output); Errors = @($shell.Streams.Error); ErrorVariable = @($runspace.SessionStateProxy.GetVariable('copyErrors')); Stop = $stop; NextStatement = $runspace.SessionStateProxy.GetVariable('scheduleNextStatement') }
            } finally { $shell.Dispose(); $runspace.Dispose(); $output.Dispose() }
        }
        function Assert-ScheduleRefreshRecord($actual, $expected) {
            $actual.FullyQualifiedErrorId | Should -BeExactly 'ExecutionFailureException,Dataplat.Dbatools.Commands.CopyDbaAgentScheduleCommand'
            $actual.CategoryInfo.Category | Should -Be $expected.CategoryInfo.Category
            $actual.CategoryInfo.Reason | Should -BeExactly $expected.CategoryInfo.Reason
            $actual.TargetObject | Should -Be $expected.TargetObject
            $actualFailure = $actual.Exception
            for ($expectedFailure = $expected.Exception; $null -ne $expectedFailure; $expectedFailure = $expectedFailure.InnerException) {
                $actualFailure | Should -Not -BeNullOrEmpty
                $actualFailure.GetType().FullName | Should -BeExactly $expectedFailure.GetType().FullName
                $actualFailure.Message | Should -BeExactly $expectedFailure.Message
                $actualFailure.HResult | Should -Be $expectedFailure.HResult
                $actualFailure = $actualFailure.InnerException
            }
            $actualFailure | Should -BeNullOrEmpty
        }
    }
    AfterAll {
        $cleanupFailures = New-Object 'System.Collections.Generic.List[string]'
        foreach ($reader in $readers) {
            try { $reader.ConnectionContext.Disconnect() } catch { $cleanupFailures.Add($PSItem.ToString()) }
        }
        foreach ($admin in $sourceAdmin, $targetAdmin) {
            if (-not $admin) { continue }
            try {
                $ids = @($admin.ConnectionContext.ExecuteWithResults("SELECT schedule_id FROM msdb.dbo.sysschedules WHERE name=N'$token';").Tables[0].Rows)
                foreach ($row in $ids) { $null = $admin.ConnectionContext.ExecuteNonQuery("EXEC msdb.dbo.sp_delete_schedule @schedule_id=$([int]$row.schedule_id), @force_delete=1;") }
                $admin.ConnectionContext.ExecuteScalar("SELECT COUNT(*) FROM msdb.dbo.sysschedules WHERE name=N'$token';") | Should -Be 0
            } catch { $cleanupFailures.Add($PSItem.ToString()) }
        }
        if ($targetAdmin) {
            try {
                $null = $targetAdmin.ConnectionContext.ExecuteNonQuery("USE msdb; IF USER_ID(N'$token') IS NOT NULL DROP USER [$token]; USE master; IF SUSER_ID(N'$token') IS NOT NULL DROP LOGIN [$token];")
                $targetAdmin.ConnectionContext.ExecuteScalar("SELECT COUNT(*) FROM sys.server_principals WHERE name=N'$token';") | Should -Be 0
            } catch { $cleanupFailures.Add($PSItem.ToString()) }
        }
        if ($cleanupFailures.Count) { throw ($cleanupFailures -join [Environment]::NewLine) }
    }

    It 'surfaces the causal source refresh record and honors caller and explicit stop modes' -Tag NativeChecklist:enable-exception {
        foreach ($mode in 'Plain', 'CallerTry', 'EnableException', 'ErrorAction') {
            $null = $targetAdmin.ConnectionContext.ExecuteNonQuery("USE msdb; REVOKE CONNECT TO [$token];")
            $connection = New-Object Microsoft.SqlServer.Management.Common.ServerConnection -ArgumentList $targetAdmin.Name, $token, $password
            $connection.DatabaseName = 'master'
            $connection.NonPooledConnection = $true
            $connection.TrustServerCertificate = $true
            $connection.Connect()
            $reader = New-Object Microsoft.SqlServer.Management.Smo.Server -ArgumentList $connection
            $readers.Add($reader)
            $boundReader = New-Object Dataplat.Dbatools.Parameter.DbaInstanceParameter -ArgumentList $reader
            $connection.ExecuteScalar('SELECT SUSER_SNAME();') | Should -BeExactly $token
            $null = $targetAdmin.ConnectionContext.ExecuteNonQuery("USE msdb; DENY CONNECT TO [$token];")
            $arguments = @{ Source = $boundReader; Destination = $sourceAdmin; Schedule = $token; Confirm = $false; EnableException = ($mode -eq 'EnableException'); ErrorAction = $(if ($mode -eq 'ErrorAction') { 'Stop' } else { 'Continue' }) }
            $rows = New-Object 'System.Collections.Generic.List[object]'
            $errors = @()
            if ($mode -eq 'CallerTry') {
                try { Copy-DbaAgentSchedule @arguments | ForEach-Object { $rows.Add($PSItem) } }
                catch { $errors = @($PSItem) }
            } else {
                $invocation = Invoke-ScheduleOutsideTry $arguments
                foreach ($row in $invocation.Output) { $rows.Add($row) }
                if ($mode -eq 'ErrorAction') {
                    $invocation.Stop.Exception.InnerException | Should -BeOfType System.Management.Automation.ActionPreferenceStopException
                    $errors = @($invocation.Stop.Exception.InnerException.ErrorRecord)
                } else { $errors = $invocation.Errors }
            }
            $expected = $null
            try { $reader.JobServer.SharedSchedules.Refresh() } catch { $expected = $PSItem }
            $expected | Should -Not -BeNullOrEmpty
            $errors.Count | Should -Be 1
            Assert-ScheduleRefreshRecord $errors[0] $expected
            $rows.Count | Should -Be 0
            if ($mode -eq 'Plain') {
                $invocation.Stop | Should -BeNullOrEmpty
                $invocation.NextStatement | Should -BeTrue
            }
            foreach ($admin in $sourceAdmin, $targetAdmin) {
                $admin.ConnectionContext.ExecuteScalar("SELECT COUNT(*) FROM msdb.dbo.sysschedules WHERE name=N'$token';") | Should -Be 1
            }
            $connection.Disconnect()
        }
    }

    It 'surfaces the destination refresh failure, continues in plain calls and honors stop modes' -Tag NativeChecklist:multi-instance-failure, NativeChecklist:enable-exception {
        # Pin evidence: refresh-bound-modes-20261107, both editions. The two subsequent child-owned records are omitted under keep-going point 2.
        foreach ($mode in 'Plain', 'CallerTry', 'EnableException', 'ErrorAction') {
            $null = $targetAdmin.ConnectionContext.ExecuteNonQuery("USE msdb; REVOKE CONNECT TO [$token];")
            $connection = New-Object Microsoft.SqlServer.Management.Common.ServerConnection -ArgumentList $targetAdmin.Name, $token, $password
            $connection.DatabaseName = 'master'
            $connection.NonPooledConnection = $true
            $connection.TrustServerCertificate = $true
            $connection.Connect()
            $reader = New-Object Microsoft.SqlServer.Management.Smo.Server -ArgumentList $connection
            $readers.Add($reader)
            $boundReader = New-Object Dataplat.Dbatools.Parameter.DbaInstanceParameter -ArgumentList $reader
            $connection.ExecuteScalar('SELECT SUSER_SNAME();') | Should -BeExactly $token
            # Bind before denial, but never pre-load the collection that must fail inside the command.
            $null = $targetAdmin.ConnectionContext.ExecuteNonQuery("USE msdb; DENY CONNECT TO [$token];")
            $arguments = @{ InputObject = $inputSchedule; Destination = @($boundReader, $sourceAdmin); Confirm = $false; EnableException = ($mode -eq 'EnableException'); ErrorAction = $(if ($mode -eq 'ErrorAction') { 'Stop' } else { 'Continue' }) }
            $rows = New-Object 'System.Collections.Generic.List[object]'
            $errors = @()
            if ($mode -eq 'CallerTry') {
                try { Copy-DbaAgentSchedule @arguments | ForEach-Object { $rows.Add($PSItem) } }
                catch { $errors = @($PSItem) }
            } else {
                $invocation = Invoke-ScheduleOutsideTry $arguments
                foreach ($row in $invocation.Output) { $rows.Add($row) }
                if ($mode -eq 'ErrorAction') {
                    $invocation.Stop.Exception.InnerException | Should -BeOfType System.Management.Automation.ActionPreferenceStopException
                    $errors = @($invocation.Stop.Exception.InnerException.ErrorRecord)
                } else { $errors = $invocation.Errors }
            }
            $expected = $null
            try { $reader.JobServer.SharedSchedules.Refresh() } catch { $expected = $PSItem }
            $expected | Should -Not -BeNullOrEmpty
            $errors.Count | Should -Be 1
            Assert-ScheduleRefreshRecord $errors[0] $expected
            if ($mode -eq 'Plain') {
                $invocation.Stop | Should -BeNullOrEmpty
                $rows.Count | Should -Be 2
                $rows[0].Status | Should -BeExactly 'Failed'
                $rows[0].Notes | Should -BeNullOrEmpty
                $rows[0].Name | Should -BeExactly $token
                $rows[0].DestinationServer | Should -BeExactly $targetAdmin.Name
                $rows[1].Status | Should -BeExactly 'Skipped'
                $rows[1].Notes | Should -BeExactly 'Already exists on destination'
            } else { $rows.Count | Should -Be 0 }
            foreach ($admin in $sourceAdmin, $targetAdmin) {
                $admin.ConnectionContext.ExecuteScalar("SELECT COUNT(*) FROM msdb.dbo.sysschedules WHERE name=N'$token';") | Should -Be 1
            }
            $connection.Disconnect()
        }
    }
}
