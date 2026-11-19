#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaAgentJob",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- the pinned function declares no SupportsShouldProcess and changes nothing, so it has no -WhatIf or -Confirm
# Azure SQL Database: SQL Server Agent and its msdb jobs do not exist there (https://learn.microsoft.com/azure/azure-sql/database/features-comparison#features-of-sql-database-and-sql-managed-instance, and https://learn.microsoft.com/azure/azure-sql/database/transact-sql-tsql-differences-sql-server#t-sql-syntax-not-supported-in-azure-sql-database); the command refuses Azure SQL Database as Connect-DbaInstance -AzureUnsupported does (correction azure-unsupported), tested below.

Describe "Native Get-DbaAgentJob" -Tag IntegrationTests {
    BeforeAll {
        $jobServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
        $jobToken = "native_agentjob_$([Guid]::NewGuid().ToString("N"))"
        $jobEnabledName = "$($jobToken)_enabled"
        $jobDisabledName = "$($jobToken)_disabled"
        $jobCategoryName = "$($jobToken)_category"
        $jobBadInstance = "Data Source=tcp:127.0.0.1,1;Integrated Security=True;Connect Timeout=1;Pooling=False"
        $jobListeners = [Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpListeners()
        if (@($jobListeners | Where-Object Port -eq 1).Count) {
            throw "Get-DbaAgentJob failure fixture requires no local TCP listener on port 1"
        }

        $jobCategory = New-Object Microsoft.SqlServer.Management.Smo.Agent.JobCategory -ArgumentList $jobServer.JobServer, $jobCategoryName
        $jobCategory.CategoryType = [Microsoft.SqlServer.Management.Smo.Agent.CategoryType]::LocalJob
        $jobCategory.Create()

        $jobEnabled = New-Object Microsoft.SqlServer.Management.Smo.Agent.Job -ArgumentList $jobServer.JobServer, $jobEnabledName
        $jobEnabled.Category = $jobCategoryName
        $jobEnabled.IsEnabled = $true
        $jobEnabled.Create()
        $jobEnabled.ApplyToTargetServer("(local)")
        $jobEnabledStep = New-Object Microsoft.SqlServer.Management.Smo.Agent.JobStep -ArgumentList $jobEnabled, "native_step_tempdb"
        $jobEnabledStep.SubSystem = [Microsoft.SqlServer.Management.Smo.Agent.AgentSubSystem]::TransactSql
        $jobEnabledStep.DatabaseName = "tempdb"
        $jobEnabledStep.Command = "SELECT 1;"
        $jobEnabledStep.Create()

        $jobDisabled = New-Object Microsoft.SqlServer.Management.Smo.Agent.Job -ArgumentList $jobServer.JobServer, $jobDisabledName
        $jobDisabled.IsEnabled = $false
        $jobDisabled.Create()
        $jobDisabled.ApplyToTargetServer("(local)")
        $jobDisabledStep = New-Object Microsoft.SqlServer.Management.Smo.Agent.JobStep -ArgumentList $jobDisabled, "native_step_msdb"
        $jobDisabledStep.SubSystem = [Microsoft.SqlServer.Management.Smo.Agent.AgentSubSystem]::TransactSql
        $jobDisabledStep.DatabaseName = "msdb"
        $jobDisabledStep.Command = "SELECT 1;"
        $jobDisabledStep.Create()
        $jobServer.JobServer.Jobs.Refresh()
    }

    AfterAll {
        if ($jobServer -and $jobToken) {
            $jobServer.JobServer.Jobs.Refresh()
            foreach ($jobCleanupName in @($jobEnabledName, $jobDisabledName)) {
                $jobCleanup = $jobServer.JobServer.Jobs[$jobCleanupName]
                if ($null -ne $jobCleanup) { $jobCleanup.Drop() }
            }
            $jobServer.JobServer.JobCategories.Refresh()
            $jobCategoryCleanup = $jobServer.JobServer.JobCategories[$jobCategoryName]
            if ($null -ne $jobCategoryCleanup) { $jobCategoryCleanup.Drop() }
        }
    }

    It "returns the job with the pinned default display set and aliases" {
        $jobRows = @(Get-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job $jobEnabledName -EnableException)
        $jobRows.Count | Should -Be 1
        $jobRows[0] | Should -BeOfType Microsoft.SqlServer.Management.Smo.Agent.Job
        $jobRows[0].Name | Should -BeExactly $jobEnabledName
        $jobRows[0].Category | Should -BeExactly $jobCategoryName
        $jobRows[0].Enabled | Should -BeTrue
        $jobRows[0].CreateDate | Should -Be $jobRows[0].DateCreated
        $jobRows[0].ComputerName | Should -Not -BeNullOrEmpty
        $jobRows[0].InstanceName | Should -BeExactly $jobServer.ServiceName
        $jobRows[0].SqlInstance | Should -BeExactly $jobServer.DomainInstanceName
        ($jobRows[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames -join ",") |
            Should -BeExactly "ComputerName,InstanceName,SqlInstance,Name,Category,OwnerLoginName,CurrentRunStatus,CurrentRunRetryAttempt,Enabled,LastRunDate,LastRunOutcome,HasSchedule,OperatorToEmail,CreateDate"
    }

    It "matches -Job and -ExcludeJob exactly and case-insensitively, as -in and -notin do" {
        $splatJobNames = @{
            SqlInstance     = $TestConfig.InstanceSingle
            Job             = $jobEnabledName.ToUpperInvariant(), $jobDisabledName
            EnableException = $true
        }
        @(Get-DbaAgentJob @splatJobNames | Sort-Object Name | ForEach-Object Name) | Should -BeExactly @($jobDisabledName, $jobEnabledName)
        $splatJobNames.ExcludeJob = $jobDisabledName.ToUpperInvariant()
        @(Get-DbaAgentJob @splatJobNames | ForEach-Object Name) | Should -BeExactly @($jobEnabledName)
        $splatJobNames.Job = "$($jobToken)*"
        $splatJobNames.Remove("ExcludeJob")
        @(Get-DbaAgentJob @splatJobNames).Count | Should -Be 0
    }

    It "filters by category and excluded category case-insensitively" {
        $splatJobCategory = @{
            SqlInstance     = $TestConfig.InstanceSingle
            Job             = $jobEnabledName, $jobDisabledName
            EnableException = $true
        }
        @(Get-DbaAgentJob @splatJobCategory -Category $jobCategoryName.ToUpperInvariant() | ForEach-Object Name) | Should -BeExactly @($jobEnabledName)
        @(Get-DbaAgentJob @splatJobCategory -ExcludeCategory $jobCategoryName.ToUpperInvariant() | ForEach-Object Name) | Should -BeExactly @($jobDisabledName)
    }

    It "filters by the database of a job step case-insensitively, and ignores a single empty name" {
        $splatJobDatabase = @{
            SqlInstance     = $TestConfig.InstanceSingle
            Job             = $jobEnabledName, $jobDisabledName
            EnableException = $true
        }
        @(Get-DbaAgentJob @splatJobDatabase -Database "TEMPDB" | ForEach-Object Name) | Should -BeExactly @($jobEnabledName)
        @(Get-DbaAgentJob @splatJobDatabase -Database "Msdb", "tempdb" | Sort-Object Name | ForEach-Object Name) | Should -BeExactly @($jobDisabledName, $jobEnabledName)
        @(Get-DbaAgentJob @splatJobDatabase -Database "$($jobToken)_nodb").Count | Should -Be 0
        @(Get-DbaAgentJob @splatJobDatabase -Database "").Count | Should -Be 2
    }

    Context "A -Database name under the Turkish culture" {
        BeforeAll {
            # The database name holds a lowercase i ("native"), so its upper-case form differs from it under tr-TR.
            $cultureDatabaseName = "$($jobToken)_culture"
            $cultureJobName = "$($jobToken)_culturejob"
            $cultureDatabase = New-Object Microsoft.SqlServer.Management.Smo.Database -ArgumentList $jobServer, $cultureDatabaseName
            $cultureDatabase.Create()
            $cultureJob = New-Object Microsoft.SqlServer.Management.Smo.Agent.Job -ArgumentList $jobServer.JobServer, $cultureJobName
            $cultureJob.Create()
            $cultureJob.ApplyToTargetServer("(local)")
            $cultureStep = New-Object Microsoft.SqlServer.Management.Smo.Agent.JobStep -ArgumentList $cultureJob, "native_step_culture"
            $cultureStep.SubSystem = [Microsoft.SqlServer.Management.Smo.Agent.AgentSubSystem]::TransactSql
            $cultureStep.DatabaseName = $cultureDatabaseName
            $cultureStep.Command = "SELECT 1;"
            $cultureStep.Create()
            $jobServer.JobServer.Jobs.Refresh()
        }

        AfterAll {
            $jobServer.JobServer.Jobs.Refresh()
            $cultureJobCleanup = $jobServer.JobServer.Jobs[$cultureJobName]
            if ($null -ne $cultureJobCleanup) { $cultureJobCleanup.Drop() }
            $jobServer.Databases.Refresh()
            if ($null -ne $jobServer.Databases[$cultureDatabaseName]) { $jobServer.KillDatabase($cultureDatabaseName) }
        }

        It "finds the job for the upper-case -Database name when the calling thread runs in tr-TR, ordinally on both editions" {
            # Correction culture-database-match: -Database compares ordinally and case-insensitively on both editions, as
            # PowerShell 7's @{} does, so the upper-case name finds the job under any culture.
            $cultureUpper = $cultureDatabaseName.ToUpperInvariant()
            # A fresh server object, connected before the culture changes: the fixture server cached its job objects before
            # ApplyToTargetServer, so their JobType reads as no type there and the pinned -Type filter leaves them out.
            $cultureServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -NonPooledConnection -EnableException
            # Load the jobs and this job's steps now, so only the -Database comparison runs under tr-TR, not SMO's queries.
            $cultureJobLoaded = $cultureServer.JobServer.Jobs[$cultureJobName]
            @($cultureJobLoaded.JobSteps | ForEach-Object DatabaseName) | Should -BeExactly @($cultureDatabaseName)
            $cultureBefore = [System.Threading.Thread]::CurrentThread.CurrentCulture
            try {
                [System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo("tr-TR")
                $cultureNames = @(Get-DbaAgentJob -SqlInstance $cultureServer -Job $cultureJobName -Database $cultureUpper -EnableException | ForEach-Object Name)
            } finally {
                [System.Threading.Thread]::CurrentThread.CurrentCulture = $cultureBefore
            }
            # Back in the session's culture, the exact-case name finds the job.
            (@(Get-DbaAgentJob -SqlInstance $cultureServer -Job $cultureJobName -Database $cultureDatabaseName -EnableException | ForEach-Object Name) -join ",") | Should -BeExactly $cultureJobName
            $cultureServer.ConnectionContext.Disconnect()
            ($cultureNames -join ",") | Should -BeExactly $cultureJobName
        }

        It "finds the job for the upper-case -Database name when new threads start in tr-TR" {
            # Correction culture-database-match, supplemental test: the process's DefaultThreadCurrentCulture is tr-TR, the
            # culture every new thread starts in (Microsoft Learn, CultureInfo.DefaultThreadCurrentCulture). It is set in
            # this test process only, never as a user or machine setting, and set back in the finally block.
            $cultureUpper = $cultureDatabaseName.ToUpperInvariant()
            $turkish = [System.Globalization.CultureInfo]::GetCultureInfo("tr-TR")
            # The fixture tells the comparers apart: tr-TR ignore-case keeps the name and its upper-case form apart, while
            # ordinal ignore-case treats them as equal.
            $turkishComparer = [System.StringComparer]::Create($turkish, $true)
            $turkishComparer.Equals($cultureDatabaseName, $cultureUpper) | Should -BeFalse
            [System.StringComparer]::OrdinalIgnoreCase.Equals($cultureDatabaseName, $cultureUpper) | Should -BeTrue
            # A fresh non-pooled server, with the job and its steps loaded first, so only the -Database comparison runs
            # under tr-TR.
            $defaultServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -NonPooledConnection -EnableException
            $defaultJobLoaded = $defaultServer.JobServer.Jobs[$cultureJobName]
            @($defaultJobLoaded.JobSteps | ForEach-Object DatabaseName) | Should -BeExactly @($cultureDatabaseName)
            $savedDefaultCulture = [System.Globalization.CultureInfo]::DefaultThreadCurrentCulture
            $savedThreadCulture = [System.Threading.Thread]::CurrentThread.CurrentCulture
            try {
                [System.Globalization.CultureInfo]::DefaultThreadCurrentCulture = $turkish
                [System.Threading.Thread]::CurrentThread.CurrentCulture = $turkish
                [System.Globalization.CultureInfo]::DefaultThreadCurrentCulture.Name | Should -BeExactly "tr-TR"
                $defaultNames = @(Get-DbaAgentJob -SqlInstance $defaultServer -Job $cultureJobName -Database $cultureUpper -EnableException | ForEach-Object Name)
            } finally {
                [System.Globalization.CultureInfo]::DefaultThreadCurrentCulture = $savedDefaultCulture
                [System.Threading.Thread]::CurrentThread.CurrentCulture = $savedThreadCulture
                $defaultServer.ConnectionContext.Disconnect()
            }
            ($defaultNames -join ",") | Should -BeExactly $cultureJobName
        }

        It "finds the job for the upper-case -Database name when the command first runs after the culture switch, in a fresh session" {
            # In this test process Get-DbaAgentJob has run before. A background job is a new process: there the command
            # first runs after the switch to tr-TR, and the upper-case name still finds the job (correction
            # culture-database-match).
            $cultureModuleBase = (Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1).ModuleBase
            $splatCultureJob = @{
                ArgumentList = (Join-Path $cultureModuleBase "dbatools.psd1"), $TestConfig.InstanceSingle, $cultureJobName, $cultureDatabaseName
                ScriptBlock  = {
                    param($ManifestPath, $Instance, $JobName, $DatabaseName)
                    $ErrorActionPreference = "Stop"
                    Import-Module $ManifestPath -Force
                    # Connect and load the job and its steps first, so only the -Database comparison runs under tr-TR.
                    $freshServer = Connect-DbaInstance -SqlInstance $Instance -NonPooledConnection -EnableException
                    $freshJob = $freshServer.JobServer.Jobs[$JobName]
                    $freshSteps = @($freshJob.JobSteps | ForEach-Object DatabaseName)
                    $freshUpper = $DatabaseName.ToUpperInvariant()
                    [System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo("tr-TR")
                    $freshNames = @(Get-DbaAgentJob -SqlInstance $freshServer -Job $JobName -Database $freshUpper -EnableException | ForEach-Object Name)
                    [pscustomobject]@{
                        Steps          = ($freshSteps -join ",")
                        Culture        = [System.Threading.Thread]::CurrentThread.CurrentCulture.Name
                        Names          = ($freshNames -join ",")
                    }
                }
            }
            $cultureBackground = Start-Job @splatCultureJob
            try {
                $null = Wait-Job -Job $cultureBackground -Timeout 600
                $cultureBackground.State | Should -Be "Completed"
                $freshResult = @(Receive-Job -Job $cultureBackground -ErrorAction Stop)
            } finally {
                Remove-Job -Job $cultureBackground -Force
            }
            $freshResult.Count | Should -Be 1
            $freshResult[0].Steps | Should -BeExactly $cultureDatabaseName
            $freshResult[0].Culture | Should -BeExactly "tr-TR"
            $freshResult[0].Names | Should -BeExactly $cultureJobName
        }
    }

    It "filters by job type, accepting the type in any case" {
        $splatJobType = @{
            SqlInstance     = $TestConfig.InstanceSingle
            Job             = $jobEnabledName
            EnableException = $true
        }
        @(Get-DbaAgentJob @splatJobType -Type MultiServer).Count | Should -Be 0
        @(Get-DbaAgentJob @splatJobType -Type local | ForEach-Object Name) | Should -BeExactly @($jobEnabledName)
    }

    It "excludes disabled jobs only with -ExcludeDisabledJobs" {
        $splatJobDisabled = @{
            SqlInstance     = $TestConfig.InstanceSingle
            Job             = $jobEnabledName, $jobDisabledName
            EnableException = $true
        }
        @(Get-DbaAgentJob @splatJobDisabled -ExcludeDisabledJobs | ForEach-Object Name) | Should -BeExactly @($jobEnabledName)
    }

    It "writes the pinned verbose messages for blank -Job and -ExcludeJob values" {
        $jobVerbose = @(Get-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job "", "  " -EnableException -Verbose 4>&1)
        @($jobVerbose | Where-Object { $PSItem -isnot [System.Management.Automation.VerboseRecord] }).Count | Should -Be 0
        ($jobVerbose | Where-Object { $PSItem -is [System.Management.Automation.VerboseRecord] } | ForEach-Object Message) -join " " |
            Should -BeLike "*The -Job parameter was explicitly provided but contains only null, empty, or whitespace values. No jobs will be returned.*"
        $jobExcludeVerbose = @(Get-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job $jobEnabledName -ExcludeJob " " -EnableException -Verbose 4>&1)
        @($jobExcludeVerbose | Where-Object { $PSItem -isnot [System.Management.Automation.VerboseRecord] } | ForEach-Object Name) | Should -BeExactly @($jobEnabledName)
        ($jobExcludeVerbose | Where-Object { $PSItem -is [System.Management.Automation.VerboseRecord] } | ForEach-Object Message) -join " " |
            Should -BeLike "*The -ExcludeJob parameter was explicitly provided but contains only null, empty, or whitespace values. Parameter will be ignored.*"
    }

    Context "A running job with -IncludeExecution" {
        BeforeAll {
            $runName = "$($jobToken)_running"
            $runJob = New-Object Microsoft.SqlServer.Management.Smo.Agent.Job -ArgumentList $jobServer.JobServer, $runName
            $runJob.IsEnabled = $true
            $runJob.Create()
            $runJob.ApplyToTargetServer("(local)")
            $runStep = New-Object Microsoft.SqlServer.Management.Smo.Agent.JobStep -ArgumentList $runJob, "native_step_wait"
            $runStep.SubSystem = [Microsoft.SqlServer.Management.Smo.Agent.AgentSubSystem]::TransactSql
            $runStep.DatabaseName = "master"
            $runStep.Command = "WAITFOR DELAY '00:03:00';"
            $runStep.Create()
            $runJob.Start()
            $runActiveQuery = "SELECT COUNT(*) FROM [msdb].[dbo].[sysjobactivity] WHERE [job_id] = '$($runJob.JobID)' AND [start_execution_date] IS NOT NULL AND [stop_execution_date] IS NULL;"
            $runActive = 0
            for ($runAttempt = 0; $runAttempt -lt 60 -and $runActive -eq 0; $runAttempt++) {
                Start-Sleep -Seconds 1
                $runActive = [int]$jobServer.ConnectionContext.ExecuteScalar($runActiveQuery)
            }
            if ($runActive -eq 0) {
                throw "The fixture job $runName did not start within 60 seconds"
            }
            $runStarted = [datetime]$jobServer.ConnectionContext.ExecuteScalar("SELECT MAX([start_execution_date]) FROM [msdb].[dbo].[sysjobactivity] WHERE [job_id] = '$($runJob.JobID)' AND [start_execution_date] IS NOT NULL AND [stop_execution_date] IS NULL;")
        }

        AfterAll {
            if ($jobServer -and $runName) {
                $jobServer.JobServer.Jobs.Refresh()
                $runCleanup = $jobServer.JobServer.Jobs[$runName]
                if ($null -ne $runCleanup) {
                    try {
                        $runCleanup.Stop()
                    } catch {
                        # The job may already be idle; the drop below is what must succeed.
                        $null = $PSItem
                    }
                    for ($runWait = 0; $runWait -lt 30; $runWait++) {
                        $runCleanup.Refresh()
                        if ($runCleanup.CurrentRunStatus -eq [Microsoft.SqlServer.Management.Smo.Agent.JobExecutionStatus]::Idle) { break }
                        Start-Sleep -Seconds 1
                    }
                    $runCleanup.Drop()
                }
            }
        }

        It "adds the latest StartDate as a DbaDateTime and shows it by default" {
            $runRows = @(Get-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job $runName -IncludeExecution -EnableException)
            $runRows.Count | Should -Be 1
            $runRows[0].StartDate | Should -BeOfType Dataplat.Dbatools.Utility.DbaDateTime
            ([datetime]$runRows[0].StartDate) | Should -Be $runStarted
            ($runRows[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames -join ",") |
                Should -BeExactly "ComputerName,InstanceName,SqlInstance,Name,Category,OwnerLoginName,CurrentRunStatus,CurrentRunRetryAttempt,Enabled,LastRunDate,LastRunOutcome,HasSchedule,OperatorToEmail,CreateDate,StartDate"
        }

        It "adds no StartDate without -IncludeExecution" {
            $runServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -NonPooledConnection -EnableException
            $runRows = @(Get-DbaAgentJob -SqlInstance $runServer -Job $runName -EnableException)
            $runRows.Count | Should -Be 1
            $runRows[0].PSObject.Properties["StartDate"] | Should -BeNullOrEmpty
            ($runRows[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames -join ",") | Should -Not -BeLike "*StartDate*"
            $runServer.ConnectionContext.Disconnect()
        }

        It "adds no StartDate to a job that is not running" {
            $runRows = @(Get-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job $jobEnabledName -IncludeExecution -EnableException)
            $runRows.Count | Should -Be 1
            $runRows[0].PSObject.Properties["StartDate"] | Should -BeNullOrEmpty
        }
    }

    Context "An -IncludeExecution query that fails" {
        BeforeAll {
            # A uniquely named login whose msdb user may not read sysjobactivity, on the shared SQL-login instance;
            # it is removed in AfterAll even when a test fails.
            $denyInstance = $TestConfig.InstanceSqlLogin
            $denyAdmin = Connect-DbaInstance -SqlInstance $denyInstance -SqlCredential $TestConfig.SqlLoginCred -NonPooledConnection -EnableException
            $denyLogin = "dbatoolsci_agentjob_deny_$([Guid]::NewGuid().ToString("N"))"
            $denyPassword = "Aa1!" + [Guid]::NewGuid().ToString("N")
            $null = $denyAdmin.ConnectionContext.ExecuteNonQuery("CREATE LOGIN [$denyLogin] WITH PASSWORD = N'$denyPassword', CHECK_EXPIRATION = OFF, CHECK_POLICY = OFF;")
            $null = $denyAdmin.ConnectionContext.ExecuteNonQuery("USE [msdb]; CREATE USER [$denyLogin] FOR LOGIN [$denyLogin]; DENY SELECT ON [dbo].[sysjobactivity] TO [$denyLogin];")
            $denyCred = New-Object System.Management.Automation.PSCredential($denyLogin, (ConvertTo-SecureString -String $denyPassword -AsPlainText -Force))
        }

        AfterAll {
            $denyDrop = Connect-DbaInstance -SqlInstance $denyInstance -SqlCredential $TestConfig.SqlLoginCred -NonPooledConnection
            $null = $denyDrop.ConnectionContext.ExecuteNonQuery("USE [msdb]; IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'$denyLogin') DROP USER [$denyLogin];")
            # The command's pooled connection may still hold a session of the login, which would block DROP LOGIN.
            $denySessions = $denyDrop.ConnectionContext.ExecuteWithResults("SELECT [session_id] FROM sys.dm_exec_sessions WHERE [login_name] = N'$denyLogin';").Tables[0]
            foreach ($denySession in $denySessions.Rows) {
                $null = $denyDrop.ConnectionContext.ExecuteNonQuery("KILL $([int]$denySession.session_id);")
            }
            $null = $denyDrop.ConnectionContext.ExecuteNonQuery("IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'$denyLogin') DROP LOGIN [$denyLogin];")
            $denyDrop.ConnectionContext.Disconnect()
        }

        It "terminates with the Server.Query error record instead of emitting jobs without StartDate" {
            # caller-try: terminate (harness-edits.md, "Caller-try for statement-terminating faults"): the pinned
            # $server.Query call at public/Get-DbaAgentJob.ps1:172 sits outside any try.
            $denyRows = New-Object "System.Collections.Generic.List[object]"
            $denyCaught = $null
            try {
                Get-DbaAgentJob -SqlInstance $denyInstance -SqlCredential $denyCred -IncludeExecution | ForEach-Object { $denyRows.Add($PSItem) }
            } catch {
                $denyCaught = $PSItem
            }
            $denyRows.Count | Should -Be 0
            $denyCaught | Should -Not -BeNullOrEmpty
            $denyCaught.FullyQualifiedErrorId | Should -BeLike "ScriptMethodRuntimeException*"
            $denyText = @()
            $denyFailure = $denyCaught.Exception
            while ($denyFailure) {
                $denyText += $denyFailure.Message
                $denyFailure = $denyFailure.InnerException
            }
            ($denyText -join " ") | Should -BeLike "*Exception calling `"Query`" with `"1`" argument(s): *denied*"
        }
    }

    Context "Checklist: pipeline input with several objects" -Tag "NativeChecklist:pipeline-multiple" {
        It "returns the jobs of every piped instance" {
            # A fresh server object: the fixture server cached its job objects before ApplyToTargetServer, so their JobType
            # still reads as no type there, and -Type (Local, MultiServer) leaves them out, as the pinned filter does.
            $pipeServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -NonPooledConnection -EnableException
            $pipeRows = @($pipeServer, $TestConfig.InstanceSingle | Get-DbaAgentJob -Job $jobEnabledName -EnableException)
            $pipeServer.ConnectionContext.Disconnect()
            $pipeRows.Count | Should -Be 2
            foreach ($pipeRow in $pipeRows) {
                $pipeRow.Name | Should -BeExactly $jobEnabledName
            }
        }
    }

    Context "Checklist: several instances with one failing" -Tag "NativeChecklist:multi-instance-failure" {
        It "returns output for the good instances and warns for the unreachable one" {
            $multiWarnings = @()
            $splatMultiInstances = @{
                SqlInstance     = $TestConfig.InstanceSingle, $jobBadInstance, $TestConfig.InstanceSingle
                Job             = $jobEnabledName
                EnableException = $false
                WarningAction   = "SilentlyContinue"
                WarningVariable = "multiWarnings"
            }
            $multiRows = @(Get-DbaAgentJob @splatMultiInstances)
            $multiRows.Count | Should -Be 2
            foreach ($multiRow in $multiRows) {
                $multiRow.Name | Should -BeExactly $jobEnabledName
            }
            ($multiWarnings -join " ") | Should -BeLike "*Failure*"
        }
    }

    Context "Checklist: EnableException on and off for a failing instance" -Tag "NativeChecklist:multi-instance-failure", "NativeChecklist:enable-exception" {
        It "warns and continues when EnableException is off" {
            $offWarnings = @()
            $offCaught = $null
            $offRows = @()
            $splatOff = @{
                SqlInstance     = $jobBadInstance, $TestConfig.InstanceSingle
                Job             = $jobEnabledName
                EnableException = $false
                WarningAction   = "SilentlyContinue"
                WarningVariable = "offWarnings"
            }
            try {
                $offRows = @(Get-DbaAgentJob @splatOff)
            } catch {
                $offCaught = $PSItem
            }
            $offCaught | Should -BeNullOrEmpty
            $offRows.Count | Should -Be 1
            ($offWarnings -join " ") | Should -BeLike "*Failure*"
        }

        It "throws a connection error at the failing instance when EnableException is on" {
            $onRows = New-Object "System.Collections.Generic.List[object]"
            $onCaught = $null
            $splatOn = @{
                SqlInstance     = $TestConfig.InstanceSingle, $jobBadInstance, $TestConfig.InstanceSingle
                Job             = $jobEnabledName
                EnableException = $true
            }
            try {
                Get-DbaAgentJob @splatOn | ForEach-Object { $onRows.Add($PSItem) }
            } catch {
                $onCaught = $PSItem
            }
            $onRows.Count | Should -Be 1
            $onCaught | Should -Not -BeNullOrEmpty
            $onCaught.CategoryInfo.Category | Should -Be "ConnectionError"
            $onCaught.TargetObject | Should -BeExactly "TCP:127.0.0.1,1"
        }
    }

    Context "Checklist: switches passed explicitly as false" -Tag "NativeChecklist:switch-false" {
        It 'treats -ExcludeDisabledJobs:$false as not excluding the disabled job' {
            $splatSwitchFalse = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Job             = $jobDisabledName
                EnableException = $true
            }
            @(Get-DbaAgentJob @splatSwitchFalse -ExcludeDisabledJobs).Count | Should -Be 0
            @(Get-DbaAgentJob @splatSwitchFalse -ExcludeDisabledJobs:$false | ForEach-Object Name) | Should -BeExactly @($jobDisabledName)
        }

        It 'treats -EnableException:$false as a warning instead of an exception' {
            $falseWarnings = @()
            $falseCaught = $null
            $falseRows = @()
            $splatEnableFalse = @{
                SqlInstance     = $jobBadInstance
                WarningAction   = "SilentlyContinue"
                WarningVariable = "falseWarnings"
            }
            try {
                $falseRows = @(Get-DbaAgentJob @splatEnableFalse -EnableException:$false)
            } catch {
                $falseCaught = $PSItem
            }
            $falseCaught | Should -BeNullOrEmpty
            $falseRows.Count | Should -Be 0
            ($falseWarnings -join " ") | Should -BeLike "*Failure*"
        }
    }

    Context "Checklist: WhatIf and Confirm" {
        It "exposes no WhatIf or Confirm parameter" {
            $whatIfParameters = (Get-Command $CommandName).Parameters.Keys
            $whatIfParameters | Should -Not -Contain "WhatIf"
            $whatIfParameters | Should -Not -Contain "Confirm"
        }
    }
}

Describe "Native Get-DbaAgentJob over SQL authentication" -Tag IntegrationTests {
    Context "SQL login" -Tag NativeChecklist:sql-login {
        BeforeAll {
            $loginInstance = $TestConfig.InstanceSqlLogin
            $loginCred = $TestConfig.SqlLoginCred
            $loginServer = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $loginCred -EnableException
            # Unique per leg and run: the instance is shared.
            $loginJobName = "native_agentjob_sqllogin_" + [Guid]::NewGuid().ToString("N")
            $loginJob = New-Object Microsoft.SqlServer.Management.Smo.Agent.Job -ArgumentList $loginServer.JobServer, $loginJobName
            $loginJob.IsEnabled = $false
            $loginJob.Create()
            # A job without a target server has no JobType, and the pinned -Type filter leaves it out.
            $loginJob.ApplyToTargetServer("(local)")
        }

        AfterAll {
            if ($loginServer -and $loginJobName) {
                $loginServer.JobServer.Jobs.Refresh()
                $loginCleanup = $loginServer.JobServer.Jobs[$loginJobName]
                if ($null -ne $loginCleanup) { $loginCleanup.Drop() }
            }
        }

        It "works with -SqlCredential" {
            $splatLoginJob = @{
                SqlInstance     = $loginInstance
                SqlCredential   = $loginCred
                Job             = $loginJobName
                EnableException = $true
            }
            $loginRows = @(Get-DbaAgentJob @splatLoginJob)
            $loginRows.Count | Should -Be 1
            $loginRows[0].Name | Should -BeExactly $loginJobName
            $loginRows[0].Enabled | Should -BeFalse
        }

        # The missing-credential assertions follow the pinned code quoted below instead of a -Baseline run
        # (watchman 49f13ebb): no commit can run the pinned function, because the base 12b2d4ca0 already ships the
        # compiled Get-DbaAgentJob cmdlet and the pin predates src/ and cannot be built.
        #
        # refs/pins/dbatools-2026-10-22:public/Get-DbaAgentJob.ps1:157-162
        #         foreach ($instance in $SqlInstance) {
        #             try {
        #                 $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
        #             } catch {
        #                 Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
        #             }
        #
        # The connect is the function's own, with no nested command between: without the credential it fails, and
        # Stop-Function -Continue warns "Failure" and moves on, or throws the ConnectionError under -EnableException.
        It "fails cleanly without the credential: a warning and no output" {
            $loginWarnings = @()
            $splatLoginNoCredential = @{
                SqlInstance     = $loginInstance
                Job             = $loginJobName
                WarningAction   = "SilentlyContinue"
                WarningVariable = "loginWarnings"
            }
            $loginResult = @(Get-DbaAgentJob @splatLoginNoCredential)
            $loginResult.Count | Should -Be 0
            ($loginWarnings -join " ") | Should -BeLike "*Failure*"
        }

        It "fails cleanly without the credential: -EnableException throws a connection error" {
            $loginCaught = $null
            try {
                $null = Get-DbaAgentJob -SqlInstance $loginInstance -Job $loginJobName -EnableException
            } catch {
                $loginCaught = $PSItem
            }
            $loginCaught | Should -Not -BeNullOrEmpty
            $loginCaught.CategoryInfo.Category | Should -Be "ConnectionError"
        }
    }
}

Describe "Native Get-DbaAgentJob refuses Azure SQL Database" -Tag IntegrationTests {
    BeforeAll {
        $splatAzureConnection = @{
            SqlInstance     = $TestConfig.AzureSqlDbServer
            Database        = $TestConfig.AzureSqlDbName
            SqlCredential   = $TestConfig.AzureSqlDbCred
            ConnectTimeout  = 60
            EnableException = $true
        }
        # Only this connect step retries, a fixed number of times; the command under test runs once per test.
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
                    if ($azureError.Number -eq 40613 -or $azureError.Number -eq -2 -or $azureError.NativeErrorCode -eq 258 -or $azureError.Message -like "*timed out*") { $isResuming = $true }
                    $azureError = $azureError.InnerException
                }
                if (-not $isResuming -or $attempt -eq 6) { throw }
                Start-Sleep -Seconds 10
            }
        }
    }

    It "warns that Azure SQL Database is not supported and returns nothing" -Tag NativeChecklist:azure-sqldb {
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $azureWarnings = @()
        $azureRows = @(Get-DbaAgentJob -SqlInstance $azureServer -WarningVariable azureWarnings -WarningAction SilentlyContinue)
        $azureRows.Count | Should -Be 0
        ($azureWarnings -join " ") | Should -BeLike "*Azure SQL Database not supported*"
    }

    It "throws a connection error for Azure SQL Database under -EnableException" -Tag NativeChecklist:azure-sqldb {
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $azureCaught = $null
        try {
            $null = Get-DbaAgentJob -SqlInstance $azureServer -IncludeExecution -EnableException
        } catch {
            $azureCaught = $PSItem
        }
        $azureCaught | Should -Not -BeNullOrEmpty
        $azureCaught.CategoryInfo.Category.ToString() | Should -Be "ConnectionError"
        $azureCaught.Exception.Message | Should -BeLike "*Azure SQL Database not supported*"
    }
}
