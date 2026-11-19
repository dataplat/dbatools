#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaRunningJob",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- the pinned function declares no SupportsShouldProcess and changes nothing, so it has no -WhatIf or -Confirm

Describe "Native Get-DbaRunningJob" -Tag IntegrationTests {
    BeforeAll {
        $nativeRjInstance = $TestConfig.InstanceSingle
        $nativeRjAdmin = Connect-DbaInstance -SqlInstance $nativeRjInstance -NonPooledConnection -EnableException
        # Unique names per leg: legs share no instance today, but the logins and jobs must never meet another run's.
        $nativeRjSuffix = [Guid]::NewGuid().ToString("N").Substring(0, 12)
        $nativeRjRunJob = "dbatoolsci_nrj_run_$nativeRjSuffix"
        $nativeRjIdleJob = "dbatoolsci_nrj_idle_$nativeRjSuffix"
        $nativeRjLowLogin = "dbatoolsci_nrj_low_$nativeRjSuffix"
        $nativeRjDenyLogin = "dbatoolsci_nrj_deny_$nativeRjSuffix"
        $nativeRjPassword = "Aa1!" + [Guid]::NewGuid().ToString("N")
        $nativeRjThrownSuffix = ",Dataplat.Dbatools.Commands.GetDbaRunningJobCommand"
        $nativeRjView = @("ComputerName", "InstanceName", "SqlInstance", "Name", "Category", "OwnerLoginName", "CurrentRunStatus", "CurrentRunRetryAttempt", "Enabled", "LastRunDate", "LastRunOutcome", "HasSchedule", "OperatorToEmail", "CreateDate", "StartDate")
        # Port 1 on localhost: nothing listens there, and the one-second timeout keeps the failure quick.
        $nativeRjBadInstance = 'Data Source=localhost,1;Initial Catalog=master;Integrated Security=True;Connect Timeout=1;Encrypt=False'

        $null = New-DbaAgentJob -SqlInstance $nativeRjAdmin -Job $nativeRjRunJob -EnableException
        $splatRunStep = @{
            SqlInstance     = $nativeRjAdmin
            Job             = $nativeRjRunJob
            StepName        = "wait"
            Subsystem       = "TransactSql"
            Command         = "WAITFOR DELAY '00:10:00'"
            EnableException = $true
        }
        $null = New-DbaAgentJobStep @splatRunStep
        $null = New-DbaAgentJob -SqlInstance $nativeRjAdmin -Job $nativeRjIdleJob -EnableException
        $null = Start-DbaAgentJob -SqlInstance $nativeRjAdmin -Job $nativeRjRunJob -EnableException
        # The Agent takes a moment to report the job as executing.
        for ($wait = 0; $wait -lt 30; $wait++) {
            $nativeRjAdmin.JobServer.Jobs.Refresh($true)
            if ($nativeRjAdmin.JobServer.Jobs[$nativeRjRunJob].CurrentRunStatus -ne "Idle") { break }
            Start-Sleep -Seconds 1
        }

        # A login with no SQL Agent role (msdb guest only), and one in SQLAgentReaderRole denied SELECT on sysjobactivity.
        $null = $nativeRjAdmin.ConnectionContext.ExecuteNonQuery("CREATE LOGIN [$nativeRjLowLogin] WITH PASSWORD = N'$nativeRjPassword', CHECK_POLICY = OFF;")
        $null = $nativeRjAdmin.ConnectionContext.ExecuteNonQuery("CREATE LOGIN [$nativeRjDenyLogin] WITH PASSWORD = N'$nativeRjPassword', CHECK_POLICY = OFF;")
        $null = $nativeRjAdmin.ConnectionContext.ExecuteNonQuery("USE [msdb]; CREATE USER [$nativeRjDenyLogin] FOR LOGIN [$nativeRjDenyLogin]; ALTER ROLE [SQLAgentReaderRole] ADD MEMBER [$nativeRjDenyLogin]; DENY SELECT ON [dbo].[sysjobactivity] TO [$nativeRjDenyLogin];")

        # A non-pooled connection impersonating the login, passed as -SqlInstance: the command reuses that connection.
        function New-NativeRjImpersonatedServer([string]$Login) {
            $server = Connect-DbaInstance -SqlInstance $nativeRjInstance -NonPooledConnection -EnableException
            $null = $server.ConnectionContext.ExecuteNonQuery("EXECUTE AS LOGIN = N'$Login';")
            $server
        }
        # An Agent.Job object whose job was deleted after it was read.
        function New-NativeRjDroppedJob {
            $name = "dbatoolsci_nrj_drop_$([Guid]::NewGuid().ToString('N').Substring(0, 12))"
            $null = New-DbaAgentJob -SqlInstance $nativeRjAdmin -Job $name -EnableException
            $job = Get-DbaAgentJob -SqlInstance $nativeRjInstance -Job $name -EnableException
            $null = $nativeRjAdmin.ConnectionContext.ExecuteNonQuery("EXEC [msdb].[dbo].[sp_delete_job] @job_name = N'$name';")
            $job
        }

        # A Pester It runs inside a try, so calls outside any try run in a runspace of their own, with the module loaded there.
        $nativeRjState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
        $nativeRjRunspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($nativeRjState)
        $nativeRjRunspace.Open()
        $nativeRjModulePath = (Get-Module dbatools | Where-Object ModuleType -eq Script | Select-Object -First 1).Path
        $nativeRjImport = [System.Management.Automation.PowerShell]::Create()
        $nativeRjImport.Runspace = $nativeRjRunspace
        $null = $nativeRjImport.AddCommand("Import-Module").AddParameter("Name", $nativeRjModulePath).AddParameter("ErrorAction", "Stop").Invoke()
        $nativeRjImport.Dispose()

        # One call in the given mode. plain, ErrorActionSilentlyContinue, EnableExceptionOutside and ErrorActionStopOutside run
        # outside any try; callerTry, EnableException and ErrorActionStop inside the caller's try. The script runs in the
        # runspace's global scope so its variables survive it.
        $nativeRjScript = @'
param($NativeSplat, $NativeMode)
$nrjHead = if ($global:Error.Count -gt 0) { $global:Error[0] }
$nrjOutput = @()
$nrjWarnings = @()
$nrjErrors = @()
$nrjCaught = $null
$nrjAfter = $false
$nrjAdded = $null
$NativeSplat.WarningAction = "SilentlyContinue"
$NativeSplat.WarningVariable = "nrjWarnings"
$NativeSplat.ErrorVariable = "nrjErrors"
switch ($NativeMode) {
    "EnableException" { $NativeSplat.EnableException = $true }
    "EnableExceptionOutside" { $NativeSplat.EnableException = $true }
    "ErrorActionStop" { $NativeSplat.ErrorAction = "Stop" }
    "ErrorActionStopOutside" { $NativeSplat.ErrorAction = "Stop" }
    "ErrorActionSilentlyContinue" { $NativeSplat.ErrorAction = "SilentlyContinue" }
}
if ($NativeMode -in "plain", "ErrorActionSilentlyContinue", "EnableExceptionOutside", "ErrorActionStopOutside") {
    $nrjOutput = @(Get-DbaRunningJob @NativeSplat)
    $nrjAfter = $true
} else {
    try {
        $nrjOutput = @(Get-DbaRunningJob @NativeSplat)
        $nrjAfter = $true
    } catch {
        $nrjCaught = $PSItem
    }
}
$nrjAdded = New-Object System.Collections.ArrayList
foreach ($entry in $global:Error) {
    if ($null -ne $nrjHead -and [object]::ReferenceEquals($entry, $nrjHead)) { break }
    $null = $nrjAdded.Add($entry)
}
'@
        function Invoke-NativeRjMode([string]$Mode, [hashtable]$Splat) {
            $shell = [System.Management.Automation.PowerShell]::Create()
            $shell.Runspace = $nativeRjRunspace
            try {
                $proxy = $nativeRjRunspace.SessionStateProxy
                $history = $proxy.GetVariable("Error")
                $head = if ($history.Count -gt 0) { $history[0] }
                $null = $shell.AddScript($nativeRjScript, $false).AddArgument($Splat).AddArgument($Mode)
                # A stop outside any try ends the caller's script, and Invoke reports it.
                $stopped = $null
                try {
                    $null = $shell.Invoke()
                } catch {
                    $stopped = $PSItem.Exception
                }
                $added = $proxy.GetVariable("nrjAdded")
                if ($null -eq $added) {
                    # The script ended before its own $Error count: the entries above the head, read here.
                    $added = New-Object System.Collections.ArrayList
                    foreach ($entry in $proxy.GetVariable("Error")) {
                        if ($null -ne $head -and [object]::ReferenceEquals($entry, $head)) { break }
                        $null = $added.Add($entry)
                    }
                }
                [pscustomobject]@{
                    Output   = @($proxy.GetVariable("nrjOutput"))
                    Warnings = @($proxy.GetVariable("nrjWarnings"))
                    Errors   = @($proxy.GetVariable("nrjErrors"))
                    Caught   = $proxy.GetVariable("nrjCaught")
                    After    = $proxy.GetVariable("nrjAfter")
                    Added    = @($added)
                    Stopped  = $stopped
                    Stream   = @($shell.Streams.Error)
                }
            } finally {
                $shell.Dispose()
            }
        }
        function Get-NativeRjEntryText($entries) {
            @($entries | ForEach-Object { "$($PSItem.GetType().Name):$(if ($PSItem -is [System.Management.Automation.ErrorRecord]) { $PSItem.FullyQualifiedErrorId } else { $PSItem.ErrorRecord.FullyQualifiedErrorId })" }) -join ' | '
        }
        # Two records of one fault: the same id, category, target and exception chain, type and text.
        function Assert-NativeRjSameRecord($actual, $expected) {
            $actual.FullyQualifiedErrorId | Should -BeExactly $expected.FullyQualifiedErrorId
            "$($actual.CategoryInfo.Category)" | Should -BeExactly "$($expected.CategoryInfo.Category)"
            "$($actual.TargetObject)" | Should -BeExactly "$($expected.TargetObject)"
            ((Get-NativeRjChain $actual) -join ' <- ') | Should -BeExactly ((Get-NativeRjChain $expected) -join ' <- ')
        }
        function Get-NativeRjChain($record) {
            $messages = @()
            for ($exception = $record.Exception; $exception; $exception = $exception.InnerException) { $messages += "$($exception.GetType().FullName): $($exception.Message)" }
            $messages
        }

        # harness-edits.md, "Engine error records in native ports (operator, 2026-11-12)", point 5: the port's complete
        # -ErrorVariable and $Error sequences for one statement fault, entry by entry; pin and port per mode are listed side by
        # side in the item notes (point 6). A call that goes on (plain, -ErrorAction SilentlyContinue outside a try): the bare
        # record in both, the same object. A call that stops (a caller's try, -EnableException or -ErrorAction Stop in it): the
        # engine's one CmdletInvocationException around the record in -ErrorVariable, the record in $Error and in the catch.
        function Assert-NativeRjFaultSequence($result, [string]$Mode, [string]$Id) {
            $fullId = $Id + $nativeRjThrownSuffix
            if ($Mode -eq "EnableExceptionOutside") {
                # -EnableException outside any try: the command throws, which ends the caller's statement only; the next
                # statement runs. The thrown record reaches the error stream and $Error once, and -ErrorVariable holds the
                # engine's one CmdletInvocationException around it, as in a caller's try.
                $result.Stopped | Should -BeNullOrEmpty
                $result.Caught | Should -BeNullOrEmpty
                $result.After | Should -BeTrue
                @($result.Errors).Count | Should -Be 1 -Because (Get-NativeRjEntryText $result.Errors)
                $result.Errors[0].GetType().FullName | Should -BeExactly "System.Management.Automation.CmdletInvocationException"
                @($result.Added).Count | Should -Be 1 -Because (Get-NativeRjEntryText $result.Added)
                $result.Added[0] | Should -BeOfType System.Management.Automation.ErrorRecord
                $result.Added[0].FullyQualifiedErrorId | Should -BeExactly $fullId
                Assert-NativeRjSameRecord $result.Errors[0].ErrorRecord $result.Added[0]
                @($result.Stream).Count | Should -Be 1 -Because (Get-NativeRjEntryText $result.Stream)
                Assert-NativeRjSameRecord $result.Stream[0] $result.Added[0]
                return $result.Added[0]
            }
            if ($Mode -eq "ErrorActionStopOutside") {
                # -ErrorAction Stop outside any try: the record written under Stop ends the caller's whole script (the next
                # statement does not run) with the engine's ActionPreferenceStopException around it. -ErrorVariable holds that
                # one exception; $Error holds the record, and may hold the escaping stop around the same record as well.
                $result.Caught | Should -BeNullOrEmpty
                $result.After | Should -BeFalse
                $stops = @(for ($exception = $result.Stopped; $exception; $exception = $exception.InnerException) { if ($exception -is [System.Management.Automation.ActionPreferenceStopException]) { $exception } })
                $stops.Count | Should -Be 1 -Because "$($result.Stopped)"
                $record = $stops[0].ErrorRecord
                $record.FullyQualifiedErrorId | Should -BeExactly $fullId
                @($result.Errors).Count | Should -Be 1 -Because (Get-NativeRjEntryText $result.Errors)
                $result.Errors[0].GetType().FullName | Should -BeExactly "System.Management.Automation.ActionPreferenceStopException"
                Assert-NativeRjSameRecord $result.Errors[0].ErrorRecord $record
                $plain = @($result.Added | Where-Object { $PSItem -is [System.Management.Automation.ErrorRecord] })
                $plain.Count | Should -Be 1 -Because (Get-NativeRjEntryText $result.Added)
                Assert-NativeRjSameRecord $plain[0] $record
                foreach ($entry in @($result.Added | Where-Object { $PSItem -isnot [System.Management.Automation.ErrorRecord] })) {
                    $entry.GetType().FullName | Should -BeExactly "System.Management.Automation.ActionPreferenceStopException"
                    Assert-NativeRjSameRecord $entry.ErrorRecord $record
                }
                @($result.Stream).Count | Should -Be 0 -Because (Get-NativeRjEntryText $result.Stream)
                return $record
            }
            if ($Mode -in "plain", "ErrorActionSilentlyContinue") {
                $result.Caught | Should -BeNullOrEmpty
                $result.After | Should -BeTrue
                @($result.Errors).Count | Should -Be 1 -Because (Get-NativeRjEntryText $result.Errors)
                $result.Errors[0] | Should -BeOfType System.Management.Automation.ErrorRecord
                $result.Errors[0].FullyQualifiedErrorId | Should -BeExactly $fullId
                @($result.Added).Count | Should -Be 1 -Because (Get-NativeRjEntryText $result.Added)
                [object]::ReferenceEquals($result.Added[0], $result.Errors[0]) | Should -BeTrue
                return $result.Errors[0]
            }
            $result.After | Should -BeFalse
            $result.Caught | Should -BeOfType System.Management.Automation.ErrorRecord
            $result.Caught.FullyQualifiedErrorId | Should -BeExactly $fullId
            @($result.Errors).Count | Should -Be 1 -Because (Get-NativeRjEntryText $result.Errors)
            $result.Errors[0].GetType().FullName | Should -BeExactly "System.Management.Automation.CmdletInvocationException"
            # The engine hands the catch, -ErrorVariable and $Error records of the same fault that are not one object (red
            # b05f07b7, every leg), so they are compared by content.
            Assert-NativeRjSameRecord $result.Errors[0].ErrorRecord $result.Caught
            @($result.Added).Count | Should -Be 1 -Because (Get-NativeRjEntryText $result.Added)
            $result.Added[0] | Should -BeOfType System.Management.Automation.ErrorRecord
            Assert-NativeRjSameRecord $result.Added[0] $result.Caught
            $result.Caught
        }
    }

    AfterAll {
        if ($nativeRjRunspace) { $nativeRjRunspace.Dispose() }
        try {
            $null = $nativeRjAdmin.ConnectionContext.ExecuteNonQuery("IF EXISTS (SELECT 1 FROM [msdb].[dbo].[sysjobs] WHERE [name] = N'$nativeRjRunJob') BEGIN BEGIN TRY EXEC [msdb].[dbo].[sp_stop_job] @job_name = N'$nativeRjRunJob'; END TRY BEGIN CATCH END CATCH; END")
            Start-Sleep -Seconds 2
            foreach ($job in $nativeRjRunJob, $nativeRjIdleJob) {
                $null = $nativeRjAdmin.ConnectionContext.ExecuteNonQuery("IF EXISTS (SELECT 1 FROM [msdb].[dbo].[sysjobs] WHERE [name] = N'$job') EXEC [msdb].[dbo].[sp_delete_job] @job_name = N'$job';")
            }
        } finally {
            foreach ($login in $nativeRjLowLogin, $nativeRjDenyLogin) {
                $sessions = $nativeRjAdmin.ConnectionContext.ExecuteWithResults("SELECT [session_id] FROM sys.dm_exec_sessions WHERE [login_name] = N'$login' OR [original_login_name] = N'$login';").Tables[0]
                foreach ($row in $sessions.Rows) { $null = $nativeRjAdmin.ConnectionContext.ExecuteNonQuery("KILL $([int]$row.session_id);") }
                $null = $nativeRjAdmin.ConnectionContext.ExecuteNonQuery("USE [msdb]; IF EXISTS (SELECT 1 FROM sys.database_principals WHERE [name] = N'$login') DROP USER [$login];")
                $null = $nativeRjAdmin.ConnectionContext.ExecuteNonQuery("IF EXISTS (SELECT 1 FROM sys.server_principals WHERE [name] = N'$login') DROP LOGIN [$login];")
            }
            $nativeRjAdmin.ConnectionContext.Disconnect()
        }
    }

    It "returns the running job with the nested Get-DbaAgentJob's notes, StartDate and default view, and never an Idle job" {
        $rows = @(Get-DbaRunningJob -SqlInstance $nativeRjInstance -EnableException)
        @($rows | Where-Object { "$($PSItem.CurrentRunStatus)" -eq "Idle" }).Count | Should -Be 0
        @($rows | Where-Object Name -eq $nativeRjIdleJob).Count | Should -Be 0
        $running = @($rows | Where-Object Name -eq $nativeRjRunJob)
        $running.Count | Should -Be 1
        $row = $running[0]
        $row | Should -BeOfType Microsoft.SqlServer.Management.Smo.Agent.Job
        $row.ComputerName | Should -BeExactly $nativeRjAdmin.ComputerName
        $row.InstanceName | Should -BeExactly $nativeRjAdmin.ServiceName
        $row.SqlInstance | Should -BeExactly $nativeRjAdmin.DomainInstanceName
        $row.StartDate | Should -BeOfType Dataplat.Dbatools.Utility.DbaDateTime
        $row.Enabled | Should -Be $row.IsEnabled
        $row.CreateDate | Should -Be $row.DateCreated
        (@($row.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames) -join ',') | Should -BeExactly ($nativeRjView -join ',')
    }

    It "returns each named instance's running job once per name" -Tag "NativeChecklist:pipeline-multiple" {
        $rows = @(Get-DbaRunningJob -SqlInstance $nativeRjInstance, $nativeRjInstance -EnableException)
        @($rows | Where-Object Name -eq $nativeRjRunJob).Count | Should -Be 2
    }

    It "returns the piped running job object itself, refreshed, and drops the idle one" -Tag "NativeChecklist:pipeline-multiple" {
        $jobs = @(Get-DbaAgentJob -SqlInstance $nativeRjInstance -Job $nativeRjRunJob, $nativeRjIdleJob -EnableException)
        $jobs.Count | Should -Be 2
        $rows = @($jobs | Get-DbaRunningJob -EnableException)
        $rows.Count | Should -Be 1
        $expected = $jobs | Where-Object Name -eq $nativeRjRunJob
        [object]::ReferenceEquals($rows[0].psobject.BaseObject, $expected.psobject.BaseObject) | Should -BeTrue
        "$($rows[0].CurrentRunStatus)" | Should -Not -Be "Idle"
    }

    It "warns with one line at a failed connection and goes on to the next instance, in mode <Mode>" -Tag "NativeChecklist:multi-instance-failure", "NativeChecklist:enable-exception", "NativeChecklist:switch-false" -ForEach @(
        @{ Mode = "plain" }
        @{ Mode = "callerTry" }
        @{ Mode = "EnableException" }
        @{ Mode = "ErrorActionStop" }
        @{ Mode = "ErrorActionSilentlyContinue" }
    ) {
        $result = Invoke-NativeRjMode $Mode @{ SqlInstance = @($nativeRjBadInstance, $nativeRjInstance); EnableException = $false }
        @($result.Warnings).Count | Should -Be 1
        "$($result.Warnings[0])" | Should -Match '\[Get-DbaRunningJob\] Failure \| Error connecting to \[[^\]]+\]: '
        @($result.Errors).Count | Should -Be 1 -Because (Get-NativeRjEntryText $result.Errors)
        @($result.Added).Count | Should -Be 1 -Because (Get-NativeRjEntryText $result.Added)
        if ($Mode -eq "EnableException") {
            # The Stop-Function stop: the thrown record, the engine's one CmdletInvocationException in -ErrorVariable, nothing returned.
            $result.After | Should -BeFalse
            $result.Output.Count | Should -Be 0
            $result.Caught.FullyQualifiedErrorId | Should -BeExactly ('dbatools_Get-DbaRunningJob' + $nativeRjThrownSuffix)
            $result.Errors[0].GetType().FullName | Should -BeExactly 'System.Management.Automation.CmdletInvocationException'
            Assert-NativeRjSameRecord $result.Errors[0].ErrorRecord $result.Caught
            $result.Added[0] | Should -BeOfType System.Management.Automation.ErrorRecord
            Assert-NativeRjSameRecord $result.Added[0] $result.Caught
            $record = $result.Caught
        } else {
            # Stop-Function -Continue: the record in -ErrorVariable and $Error, the same object, and the next instance's running job.
            $result.Caught | Should -BeNullOrEmpty
            $result.After | Should -BeTrue
            @($result.Output | Where-Object Name -eq $nativeRjRunJob).Count | Should -Be 1
            $result.Errors[0] | Should -BeOfType System.Management.Automation.ErrorRecord
            $result.Errors[0].FullyQualifiedErrorId | Should -BeExactly 'dbatools_Get-DbaRunningJob'
            [object]::ReferenceEquals($result.Added[0], $result.Errors[0]) | Should -BeTrue
            $record = $result.Errors[0]
        }
        "$($record.CategoryInfo.Category)" | Should -BeExactly 'ConnectionError'
        "$($record.TargetObject)" | Should -Match 'localhost,1'
        $record.Exception.InnerException.GetType().Name | Should -BeExactly 'SqlException'
        $record.Exception.Message | Should -Not -BeLike 'Error connecting to*'
    }

    It "reports the JobServer refresh, execution query and job enumeration faults of a login without SQL Agent rights, in mode <Mode>" -ForEach @(
        @{ Mode = "plain" }
        @{ Mode = "callerTry" }
        @{ Mode = "EnableException" }
        @{ Mode = "ErrorActionStop" }
        @{ Mode = "ErrorActionSilentlyContinue" }
    ) {
        # Probe pin-contract-r4 (evidence/pin-contract-r4-pin-as-20261112.txt, both editions): the pin writes the Refresh fault, then
        # the nested Get-DbaAgentJob's Query and enumeration faults, and returns nothing; a caller's try receives the Refresh fault.
        $lowServer = New-NativeRjImpersonatedServer $nativeRjLowLogin
        try {
            $result = Invoke-NativeRjMode $Mode @{ SqlInstance = $lowServer; EnableException = $false }
        } finally {
            $lowServer.ConnectionContext.Disconnect()
        }
        $result.Output.Count | Should -Be 0
        @($result.Warnings).Count | Should -Be 0
        if ($Mode -in "plain", "ErrorActionSilentlyContinue") {
            # Three statement faults, each written as the bare record, in -ErrorVariable oldest first and in $Error newest first.
            $result.Caught | Should -BeNullOrEmpty
            $result.After | Should -BeTrue
            (Get-NativeRjEntryText $result.Errors) | Should -BeExactly ("ErrorRecord:ExecutionFailureException$nativeRjThrownSuffix | ErrorRecord:ScriptMethodRuntimeException$nativeRjThrownSuffix | ErrorRecord:ExceptionInGetEnumerator$nativeRjThrownSuffix")
            @($result.Added).Count | Should -Be 3 -Because (Get-NativeRjEntryText $result.Added)
            for ($n = 0; $n -lt 3; $n++) { [object]::ReferenceEquals($result.Added[$n], $result.Errors[2 - $n]) | Should -BeTrue }
            $refresh = $result.Errors[0]
            $query = $result.Errors[1]
            $enumeration = $result.Errors[2]
        } else {
            $refresh = Assert-NativeRjFaultSequence $result $Mode "ExecutionFailureException"
        }

        # PS: $server.JobServer.Jobs.Refresh($true)
        $refresh.Exception.GetType().FullName | Should -BeExactly 'System.Management.Automation.MethodInvocationException'
        $refreshInner = $refresh.Exception.InnerException
        $refreshInner.GetType().FullName | Should -BeExactly 'Microsoft.SqlServer.Management.Common.ExecutionFailureException'
        $refresh.Exception.Message | Should -BeExactly ('Exception calling "Refresh" with "1" argument(s): "' + $refreshInner.Message + '"')
        $refreshInner.InnerException.GetType().Name | Should -BeExactly 'SqlException'
        $refreshInner.InnerException.Message | Should -Match 'permission was denied'
        "$($refresh.CategoryInfo.Category)" | Should -BeExactly 'NotSpecified'
        $refresh.CategoryInfo.Reason | Should -BeExactly 'MethodInvocationException'
        $refresh.CategoryInfo.Activity | Should -BeExactly 'Get-DbaRunningJob'
        $refresh.TargetObject | Should -BeNullOrEmpty
        if ($Mode -notin "plain", "ErrorActionSilentlyContinue") { return }

        # PS (Get-DbaAgentJob): $server.Query($query), whose catch joins the failure's messages and throws them.
        $query.Exception.GetType().FullName | Should -BeExactly 'System.Management.Automation.MethodInvocationException'
        $joined = $query.Exception.InnerException.Message
        $joined | Should -Match "^An exception occurred while executing a Transact-SQL statement or batch\.The SELECT permission was denied on the object 'sysjobactivity'"
        $query.Exception.Message | Should -BeExactly ('Exception calling "Query" with "1" argument(s): "' + $joined + '"')
        (@(Get-NativeRjChain $query) -join ' <- ') | Should -BeExactly ("System.Management.Automation.MethodInvocationException: $($query.Exception.Message) <- System.Management.Automation.RuntimeException: $joined <- System.Management.Automation.RuntimeException: $joined")
        "$($query.CategoryInfo.Category)" | Should -BeExactly 'NotSpecified'
        $query.TargetObject | Should -BeNullOrEmpty

        # PS (Get-DbaAgentJob): $server.JobServer.Jobs | Where-Object ..., whose enumeration fails.
        $enumeration.Exception.GetType().FullName | Should -BeExactly 'System.Management.Automation.ExtendedTypeSystemException'
        $enumerationInner = $enumeration.Exception.InnerException
        $enumerationInner.GetType().FullName | Should -BeExactly 'Microsoft.SqlServer.Management.Common.ExecutionFailureException'
        $enumeration.Exception.Message | Should -BeExactly ('The following exception occurred while trying to enumerate the collection: "' + $enumerationInner.Message + '".')
        "$($enumeration.CategoryInfo.Category)" | Should -BeExactly 'NotSpecified'
        $enumeration.CategoryInfo.Reason | Should -BeExactly 'ExtendedTypeSystemException'
    }

    It "reports the execution query fault of a login denied sysjobactivity and returns the running job without a StartDate, in mode <Mode>" -ForEach @(
        @{ Mode = "plain" }
        @{ Mode = "callerTry" }
        @{ Mode = "EnableException" }
        @{ Mode = "ErrorActionStop" }
        @{ Mode = "ErrorActionSilentlyContinue" }
        @{ Mode = "EnableExceptionOutside" }
        @{ Mode = "ErrorActionStopOutside" }
    ) {
        # Probe pin-contract-r4: the pin writes the Query fault and goes on to the jobs, which carry no StartDate; a caller's try
        # receives the fault and nothing is returned. -EnableException and -ErrorAction Stop also run outside any try (review
        # round 2): the command stops there too and returns nothing.
        $denyServer = New-NativeRjImpersonatedServer $nativeRjDenyLogin
        try {
            $result = Invoke-NativeRjMode $Mode @{ SqlInstance = $denyServer; EnableException = $false }
        } finally {
            $denyServer.ConnectionContext.Disconnect()
        }
        @($result.Warnings).Count | Should -Be 0
        $query = Assert-NativeRjFaultSequence $result $Mode "ScriptMethodRuntimeException"
        if ($Mode -in "plain", "ErrorActionSilentlyContinue") {
            $running = @($result.Output | Where-Object Name -eq $nativeRjRunJob)
            $running.Count | Should -Be 1
            $running[0].psobject.Properties["StartDate"] | Should -BeNullOrEmpty
            (@($running[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames) -join ',') | Should -BeExactly (($nativeRjView | Where-Object { $PSItem -ne "StartDate" }) -join ',')
            @($result.Output | Where-Object { "$($PSItem.CurrentRunStatus)" -eq "Idle" }).Count | Should -Be 0
        } else {
            $result.Output.Count | Should -Be 0
        }
        $joined = $query.Exception.InnerException.Message
        $joined | Should -Match "^An exception occurred while executing a Transact-SQL statement or batch\.The SELECT permission was denied on the object 'sysjobactivity'"
        $query.Exception.Message | Should -BeExactly ('Exception calling "Query" with "1" argument(s): "' + $joined + '"')
        (@(Get-NativeRjChain $query) -join ' <- ') | Should -BeExactly ("System.Management.Automation.MethodInvocationException: $($query.Exception.Message) <- System.Management.Automation.RuntimeException: $joined <- System.Management.Automation.RuntimeException: $joined")
        "$($query.CategoryInfo.Category)" | Should -BeExactly 'NotSpecified'
        $query.CategoryInfo.Reason | Should -BeExactly 'MethodInvocationException'
        $query.CategoryInfo.Activity | Should -BeExactly 'Get-DbaRunningJob'
    }

    It "returns nothing for a piped job that was deleted, with no record, in mode plain" -ForEach @(
        @{ Mode = "plain" }
    ) {
        # Correction dropped-job: the pin's $job.Refresh() leaves a deleted job marked dropped without a fault, and its Where-Object
        # reads the status it cannot get as $null, which is not 'Idle', so it reports the deleted job as running (probe
        # pin-contract-r4, every mode). A deleted job is not executing. One It per mode, each named in the corrections record.
        $dropped = New-NativeRjDroppedJob
        $result = Invoke-NativeRjMode $Mode @{ InputObject = $dropped; EnableException = $false }
        $result.Output.Count | Should -Be 0
        $result.Caught | Should -BeNullOrEmpty
        $result.After | Should -BeTrue
        @($result.Errors).Count | Should -Be 0 -Because (Get-NativeRjEntryText $result.Errors)
        @($result.Added).Count | Should -Be 0 -Because (Get-NativeRjEntryText $result.Added)
        @($result.Warnings).Count | Should -Be 0
    }

    It "returns nothing for a piped job that was deleted, with no record, in mode callerTry" -ForEach @(
        @{ Mode = "callerTry" }
    ) {
        # Correction dropped-job, as in mode plain above.
        $dropped = New-NativeRjDroppedJob
        $result = Invoke-NativeRjMode $Mode @{ InputObject = $dropped; EnableException = $false }
        $result.Output.Count | Should -Be 0
        $result.Caught | Should -BeNullOrEmpty
        $result.After | Should -BeTrue
        @($result.Errors).Count | Should -Be 0 -Because (Get-NativeRjEntryText $result.Errors)
        @($result.Added).Count | Should -Be 0 -Because (Get-NativeRjEntryText $result.Added)
        @($result.Warnings).Count | Should -Be 0
    }

    It "returns nothing for a piped job that was deleted, with no record, in mode EnableException" -ForEach @(
        @{ Mode = "EnableException" }
    ) {
        # Correction dropped-job, as in mode plain above.
        $dropped = New-NativeRjDroppedJob
        $result = Invoke-NativeRjMode $Mode @{ InputObject = $dropped; EnableException = $false }
        $result.Output.Count | Should -Be 0
        $result.Caught | Should -BeNullOrEmpty
        $result.After | Should -BeTrue
        @($result.Errors).Count | Should -Be 0 -Because (Get-NativeRjEntryText $result.Errors)
        @($result.Added).Count | Should -Be 0 -Because (Get-NativeRjEntryText $result.Added)
        @($result.Warnings).Count | Should -Be 0
    }

    It "returns nothing for a piped job that was deleted, with no record, in mode ErrorActionStop" -ForEach @(
        @{ Mode = "ErrorActionStop" }
    ) {
        # Correction dropped-job, as in mode plain above.
        $dropped = New-NativeRjDroppedJob
        $result = Invoke-NativeRjMode $Mode @{ InputObject = $dropped; EnableException = $false }
        $result.Output.Count | Should -Be 0
        $result.Caught | Should -BeNullOrEmpty
        $result.After | Should -BeTrue
        @($result.Errors).Count | Should -Be 0 -Because (Get-NativeRjEntryText $result.Errors)
        @($result.Added).Count | Should -Be 0 -Because (Get-NativeRjEntryText $result.Added)
        @($result.Warnings).Count | Should -Be 0
    }

    It "returns nothing for a piped job that was deleted, with no record, in mode ErrorActionSilentlyContinue" -ForEach @(
        @{ Mode = "ErrorActionSilentlyContinue" }
    ) {
        # Correction dropped-job, as in mode plain above.
        $dropped = New-NativeRjDroppedJob
        $result = Invoke-NativeRjMode $Mode @{ InputObject = $dropped; EnableException = $false }
        $result.Output.Count | Should -Be 0
        $result.Caught | Should -BeNullOrEmpty
        $result.After | Should -BeTrue
        @($result.Errors).Count | Should -Be 0 -Because (Get-NativeRjEntryText $result.Errors)
        @($result.Added).Count | Should -Be 0 -Because (Get-NativeRjEntryText $result.Added)
        @($result.Warnings).Count | Should -Be 0
    }
}

Describe "Native Get-DbaRunningJob on Azure SQL Database" -Tag IntegrationTests {
    BeforeAll {
        # SQL Server Agent is not available in Azure SQL Database (https://learn.microsoft.com/azure/azure-sql/database/job-automation-overview),
        # so the connection refuses it as Connect-DbaInstance -AzureUnsupported does: correction azure-unsupported.
        $splatAzureConnection = @{
            SqlInstance     = $TestConfig.AzureSqlDbServer
            Database        = $TestConfig.AzureSqlDbName
            SqlCredential   = $TestConfig.AzureSqlDbCred
            ConnectTimeout  = 60
            EnableException = $true
        }
        # Only this connect step retries, a fixed number of times; the command under test runs once per call.
        $azureServer = $null
        for ($attempt = 0; $attempt -le 6; $attempt++) {
            try {
                $azureServer = Connect-DbaInstance @splatAzureConnection
                break
            } catch {
                # A paused serverless database answers 40613, or lets the login time out, while it resumes.
                $azureError = $PSItem.Exception
                $isResuming = $false
                while ($azureError) {
                    if ($azureError.Number -eq 40613 -or $azureError.Number -eq -2 -or $azureError -is [System.TimeoutException] -or $azureError.Message -match "timed out|timeout|wait operation") { $isResuming = $true }
                    $azureError = $azureError.InnerException
                }
                if (-not $isResuming -or $attempt -eq 6) { throw }
                Start-Sleep -Seconds 10
            }
        }
    }

    AfterAll {
        if ($azureServer) { $azureServer.ConnectionContext.Disconnect() }
    }

    It "warns that Azure SQL Database is not supported and goes on, and stops there with -EnableException" -Tag "NativeChecklist:azure-sqldb" {
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"

        # Without -EnableException: one warning, the command's Stop-Function record, nothing returned, the next statement runs.
        $azureWarnings = @()
        $azureErrors = @()
        $azureHead = if ($global:Error.Count -gt 0) { $global:Error[0] }
        $azureRows = @(Get-DbaRunningJob -SqlInstance $azureServer -EnableException:$false -WarningAction SilentlyContinue -WarningVariable azureWarnings -ErrorVariable azureErrors)
        $azureAdded = New-Object System.Collections.ArrayList
        foreach ($entry in $global:Error) {
            if ($null -ne $azureHead -and [object]::ReferenceEquals($entry, $azureHead)) { break }
            $null = $azureAdded.Add($entry)
        }
        $azureRows.Count | Should -Be 0
        @($azureWarnings).Count | Should -Be 1
        "$($azureWarnings[0])" | Should -Match '\[Get-DbaRunningJob\] Failure \| Azure SQL Database not supported$'
        @($azureErrors).Count | Should -Be 1
        $azureErrors[0] | Should -BeOfType System.Management.Automation.ErrorRecord
        $azureErrors[0].FullyQualifiedErrorId | Should -BeExactly 'dbatools_Get-DbaRunningJob'
        "$($azureErrors[0].CategoryInfo.Category)" | Should -BeExactly 'ConnectionError'
        $azureErrors[0].Exception.Message | Should -BeExactly 'Azure SQL Database not supported'
        $azureAdded.Count | Should -Be 1
        [object]::ReferenceEquals($azureAdded[0], $azureErrors[0]) | Should -BeTrue

        # With -EnableException: the same record thrown, nothing returned.
        $azureCaught = $null
        $azureRows = @()
        $azureErrors = @()
        try {
            $azureRows = @(Get-DbaRunningJob -SqlInstance $azureServer -EnableException -WarningAction SilentlyContinue -ErrorVariable azureErrors)
        } catch {
            $azureCaught = $PSItem
        }
        $azureRows.Count | Should -Be 0
        $azureCaught | Should -BeOfType System.Management.Automation.ErrorRecord
        $azureCaught.FullyQualifiedErrorId | Should -BeExactly 'dbatools_Get-DbaRunningJob,Dataplat.Dbatools.Commands.GetDbaRunningJobCommand'
        $azureCaught.Exception.Message | Should -BeExactly 'Azure SQL Database not supported'
        @($azureErrors).Count | Should -Be 1
        $azureErrors[0].GetType().FullName | Should -BeExactly 'System.Management.Automation.CmdletInvocationException'
    }
}

Describe "Native Get-DbaRunningJob over SQL authentication" -Tag IntegrationTests {
    Context "SQL login" -Tag NativeChecklist:sql-login {
        BeforeAll {
            $loginInstance = $TestConfig.InstanceSqlLogin
            $loginCred = $TestConfig.SqlLoginCred
        }

        It "works with -SqlCredential" {
            $loginServer = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $loginCred -EnableException
            try {
                $loginRows = @(Get-DbaRunningJob -SqlInstance $loginInstance -SqlCredential $loginCred -EnableException)
                @($loginRows | Where-Object { "$($PSItem.CurrentRunStatus)" -eq "Idle" }).Count | Should -Be 0
                @($loginRows | Where-Object { $PSItem.SqlInstance -ne $loginServer.DomainInstanceName }).Count | Should -Be 0
            } finally {
                $loginServer.ConnectionContext.Disconnect()
            }
        }

        It "fails cleanly without the credential, with EnableException <EnableException>" -ForEach @(
            @{ EnableException = $false }
            @{ EnableException = $true }
        ) {
            $loginWarnings = @()
            $loginCaught = $null
            $loginRows = @()
            $splatLoginDenied = @{
                SqlInstance     = $loginInstance
                EnableException = $EnableException
                WarningAction   = "SilentlyContinue"
                WarningVariable = "loginWarnings"
            }
            try {
                $loginRows = @(Get-DbaRunningJob @splatLoginDenied)
            } catch {
                $loginCaught = $PSItem
            }
            $loginRows.Count | Should -Be 0
            @($loginWarnings).Count | Should -Be 1
            "$($loginWarnings[0])" | Should -Match ('\[Get-DbaRunningJob\] Failure \| Error connecting to \[' + [regex]::Escape("$loginInstance") + '\]: .*Login failed')
            if ($EnableException) {
                $loginCaught.FullyQualifiedErrorId | Should -BeExactly 'dbatools_Get-DbaRunningJob,Dataplat.Dbatools.Commands.GetDbaRunningJobCommand'
                $loginCaught.Exception.Message | Should -Match 'Login failed'
            } else {
                $loginCaught | Should -BeNullOrEmpty
            }
        }
    }
}
