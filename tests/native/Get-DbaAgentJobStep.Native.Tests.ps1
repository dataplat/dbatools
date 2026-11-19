#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaAgentJobStep",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: azure-sqldb N/A -- SQL Server Agent jobs are instance-level msdb objects; Azure SQL Database has no SQL Server Agent and no msdb jobs.

Describe "Native Agent job step behavior" -Tag IntegrationTests {
    BeforeAll {
        $stepServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
        $stepJobName = "native_jobstep_$([Guid]::NewGuid().ToString("N"))"
        $stepName = "native_step"
        $stepBadInstance = "Data Source=tcp:127.0.0.1,1;Integrated Security=True;Connect Timeout=1;Pooling=False"
        $stepListeners = [Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpListeners()
        if (@($stepListeners | Where-Object Port -eq 1).Count) {
            throw "JobStep failure fixture requires no local TCP listener on port 1"
        }
        $stepJob = New-Object Microsoft.SqlServer.Management.Smo.Agent.Job($stepServer.JobServer, $stepJobName)
        $stepJob.IsEnabled = $false
        $stepJob.Create()
        $stepJob.ApplyToTargetServer("(local)")
        $stepFixture = New-Object Microsoft.SqlServer.Management.Smo.Agent.JobStep($stepJob, $stepName)
        $stepFixture.SubSystem = [Microsoft.SqlServer.Management.Smo.Agent.AgentSubSystem]::TransactSql
        $stepFixture.DatabaseName = "master"
        $stepFixture.Command = "SELECT 1;"
        $stepFixture.Create()
        $stepJob.JobSteps.Refresh()
    }

    AfterAll {
        if ($stepServer -and $stepJobName) {
            $stepServer.JobServer.Jobs.Refresh()
            $stepCleanup = $stepServer.JobServer.Jobs[$stepJobName]
            if ($null -ne $stepCleanup) { $stepCleanup.Drop() }
        }
    }

    It "preserves typed input, exact case-insensitive filters and step display metadata" {
        $splatStepInput = @{
            InputObject = $stepJob
            Job = $stepJobName.ToUpperInvariant()
            EnableException = $true
        }
        $stepRows = @(Get-DbaAgentJobStep @splatStepInput)
        $stepRows.Count | Should -Be 1
        $stepRows[0] | Should -BeOfType Microsoft.SqlServer.Management.Smo.Agent.JobStep
        $stepRows[0].Name | Should -BeExactly $stepName
        $stepRows[0].AgentJob | Should -BeExactly $stepJobName
        $stepRows[0].ComputerName | Should -Not -BeNullOrEmpty
        $stepRows[0].InstanceName | Should -BeExactly $stepServer.ServiceName
        $stepRows[0].SqlInstance | Should -BeExactly $stepServer.DomainInstanceName
        ($stepRows[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames -join ",") |
            Should -BeExactly "ComputerName,InstanceName,SqlInstance,AgentJob,Name,SubSystem,LastRunDate,LastRunOutcome,State"
        $splatStepInput.ExcludeJob = $stepJobName.ToUpperInvariant()
        @(Get-DbaAgentJobStep @splatStepInput).Count | Should -Be 0
    }

    It "accumulates multiple instance records and emits their steps only at the end" {
        $stepInputsSeen = New-Object "System.Collections.Generic.List[int]"
        $stepEmissionStages = New-Object "System.Collections.Generic.List[int]"
        $splatStepPipeline = @{
            Job = $stepJobName
            EnableException = $true
        }
        $stepRows = @(
            1, 2 | ForEach-Object {
                $stepInputsSeen.Add($PSItem)
                $stepServer
            } | Get-DbaAgentJobStep @splatStepPipeline | ForEach-Object {
                $stepEmissionStages.Add($stepInputsSeen.Count)
                $PSItem
            }
        )
        $stepRows.Count | Should -Be 2
        foreach ($stepRow in $stepRows) {
            $stepRow.AgentJob | Should -BeExactly $stepJobName
            $stepRow.Name | Should -BeExactly $stepName
        }
        ($stepEmissionStages -join ",") | Should -BeExactly "2,2"
    }

    It "warns for a failed middle instance and retains both successful records" {
        $stepWarnings = @()
        $splatStepContinue = @{
            Job = $stepJobName
            EnableException = $false
            WarningAction = "SilentlyContinue"
            WarningVariable = "stepWarnings"
        }
        $stepRows = @(
            @($stepServer, $stepBadInstance, $stepServer) | Get-DbaAgentJobStep @splatStepContinue
        )
        $stepRows.Count | Should -Be 2
        foreach ($stepRow in $stepRows) {
            $stepRow.AgentJob | Should -BeExactly $stepJobName
            $stepRow.Name | Should -BeExactly $stepName
        }
        ($stepWarnings -join " ") | Should -BeLike "*Failure*"
    }

    It "terminates a failed pipeline with EnableException before end-stage output" {
        $stepEarlierRows = New-Object "System.Collections.Generic.List[object]"
        $stepCaught = $null
        $splatStepTerminate = @{
            Job = $stepJobName
            EnableException = $true
        }
        try {
            @($stepServer, $stepBadInstance, $stepServer) |
                Get-DbaAgentJobStep @splatStepTerminate |
                ForEach-Object { $stepEarlierRows.Add($PSItem) }
        } catch {
            $stepCaught = $PSItem
        }
        $stepEarlierRows.Count | Should -Be 0
        $stepCaught | Should -Not -BeNullOrEmpty
        $stepCaught.CategoryInfo.Category | Should -Be "ConnectionError"
        $stepCaught.TargetObject | Should -BeExactly "TCP:127.0.0.1,1"
    }

    Context "Checklist: pipeline input with several objects" -Tag "NativeChecklist:pipeline-multiple" {
        BeforeAll {
            $pipePrefix = "native_jobstep_pipe_$([Guid]::NewGuid().ToString("N"))"
            $pipeJobNames = @("${pipePrefix}_a", "${pipePrefix}_b", "${pipePrefix}_c")
            $pipeJobs = @()
            foreach ($pipeJobName in $pipeJobNames) {
                $pipeJob = New-Object Microsoft.SqlServer.Management.Smo.Agent.Job($stepServer.JobServer, $pipeJobName)
                $pipeJob.IsEnabled = $false
                $pipeJob.Create()
                $pipeJob.ApplyToTargetServer("(local)")
                $pipeStep = New-Object Microsoft.SqlServer.Management.Smo.Agent.JobStep($pipeJob, "${pipeJobName}_step")
                $pipeStep.SubSystem = [Microsoft.SqlServer.Management.Smo.Agent.AgentSubSystem]::TransactSql
                $pipeStep.DatabaseName = "master"
                $pipeStep.Command = "SELECT 1;"
                $pipeStep.Create()
                $pipeJob.JobSteps.Refresh()
                $pipeJobs += $pipeJob
            }
        }

        AfterAll {
            if ($stepServer -and $pipeJobNames) {
                $stepServer.JobServer.Jobs.Refresh()
                foreach ($pipeCleanupName in $pipeJobNames) {
                    $pipeCleanup = $stepServer.JobServer.Jobs[$pipeCleanupName]
                    if ($null -ne $pipeCleanup) { $pipeCleanup.Drop() }
                }
            }
        }

        It "returns the steps of every piped job, not only the last one" {
            $pipeRows = @($pipeJobs[0], $pipeJobs[1], $pipeJobs[2] | Get-DbaAgentJobStep -EnableException)
            $pipeRows.Count | Should -Be 3
            (($pipeRows.AgentJob | Sort-Object) -join ",") | Should -BeExactly ($pipeJobNames -join ",")
            foreach ($pipeRow in $pipeRows) {
                $pipeRow.Name | Should -BeExactly "$($pipeRow.AgentJob)_step"
            }
        }

        It "returns the steps of every job piped from Get-DbaAgentJob" {
            $splatPipeSource = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Job             = $pipeJobNames[0], $pipeJobNames[1]
                EnableException = $true
            }
            $pipeRows = @(Get-DbaAgentJob @splatPipeSource | Get-DbaAgentJobStep -EnableException)
            $pipeRows.Count | Should -Be 2
            (($pipeRows.AgentJob | Sort-Object) -join ",") | Should -BeExactly (($pipeJobNames[0], $pipeJobNames[1]) -join ",")
        }

        It "keeps piped jobs and collects a command-line SqlInstance once" {
            # Choice: no de-duplication. Each supplied source contributes its jobs once, as the
            # pinned function does for -InputObject with -SqlInstance in a single record, so a job
            # both piped and found on -SqlInstance appears twice. A command-line SqlInstance is
            # collected once, not once per piped record.
            $splatPipeCombined = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Job             = $pipeJobNames
                EnableException = $true
            }
            $pipeRows = @($pipeJobs[0], $pipeJobs[1] | Get-DbaAgentJobStep @splatPipeCombined)
            $pipeRows.Count | Should -Be 5
            $pipeCounts = @{ }
            foreach ($pipeRow in $pipeRows) { $pipeCounts[$pipeRow.AgentJob] = 1 + [int]$pipeCounts[$pipeRow.AgentJob] }
            $pipeCounts[$pipeJobNames[0]] | Should -Be 2
            $pipeCounts[$pipeJobNames[1]] | Should -Be 2
            $pipeCounts[$pipeJobNames[2]] | Should -Be 1
        }

        It "keeps a command-line InputObject once across piped instance records" {
            $splatPipeDirect = @{
                InputObject     = $pipeJobs[0]
                Job             = $pipeJobNames[0]
                EnableException = $true
            }
            $pipeRows = @($stepServer, $stepServer | Get-DbaAgentJobStep @splatPipeDirect)
            $pipeRows.Count | Should -Be 3
            foreach ($pipeRow in $pipeRows) {
                $pipeRow.AgentJob | Should -BeExactly $pipeJobNames[0]
            }
        }
    }

    Context "Documented wildcard job selection" {
        BeforeAll {
            # Pinned help :20 and :24 document wildcards for -Job and -ExcludeJob; :142 and :145 filter
            # with literal -In and -NotIn, so the documented form never took effect.
            $wildcardPrefix = "native_wc_$([Guid]::NewGuid().ToString("N"))"
            $wildcardJobNames = @("${wildcardPrefix}_a", "${wildcardPrefix}_b", "${wildcardPrefix}_[a]")
            $wildcardJobsCreated = New-Object System.Collections.Generic.List[string]
            foreach ($wildcardJobName in $wildcardJobNames) {
                $wildcardJob = New-Object Microsoft.SqlServer.Management.Smo.Agent.Job($stepServer.JobServer, $wildcardJobName)
                $wildcardJob.IsEnabled = $false
                $wildcardJob.Create()
                $wildcardJobsCreated.Add($wildcardJobName)
                $wildcardJob.ApplyToTargetServer("(local)")
                $wildcardStep = New-Object Microsoft.SqlServer.Management.Smo.Agent.JobStep($wildcardJob, "native_wc_step")
                $wildcardStep.SubSystem = [Microsoft.SqlServer.Management.Smo.Agent.AgentSubSystem]::TransactSql
                $wildcardStep.DatabaseName = "master"
                $wildcardStep.Command = "SELECT 1;"
                $wildcardStep.Create()
            }
        }

        AfterAll {
            $stepServer.JobServer.Jobs.Refresh()
            foreach ($wildcardCleanupName in $wildcardJobsCreated) {
                $wildcardCleanup = $stepServer.JobServer.Jobs[$wildcardCleanupName]
                if ($null -ne $wildcardCleanup) { $wildcardCleanup.Drop() }
            }
        }

        It "selects jobs by a documented wildcard pattern" {
            $splatWildcardJob = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Job             = "${wildcardPrefix}_*"
                EnableException = $true
            }
            $wildcardRows = @(Get-DbaAgentJobStep @splatWildcardJob)
            (($wildcardRows.AgentJob | Sort-Object) -join ",") | Should -BeExactly (($wildcardJobNames | Sort-Object) -join ",")
            $splatWildcardJob.Job = "${wildcardPrefix}_?".ToUpperInvariant()
            $wildcardRows = @(Get-DbaAgentJobStep @splatWildcardJob)
            (($wildcardRows.AgentJob | Sort-Object) -join ",") | Should -BeExactly (($wildcardJobNames[0, 1] | Sort-Object) -join ",")
        }

        It "excludes jobs by a documented wildcard pattern" {
            $splatWildcardExclude = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Job             = $wildcardJobNames
                ExcludeJob      = "${wildcardPrefix}_?"
                EnableException = $true
            }
            $wildcardRows = @(Get-DbaAgentJobStep @splatWildcardExclude)
            ($wildcardRows.AgentJob -join ",") | Should -BeExactly $wildcardJobNames[2]
        }

        It "keeps bracket-only and invalid values literal, with exclusion taking precedence" {
            $splatWildcardLiteral = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Job             = $wildcardJobNames[2]
                EnableException = $true
            }
            $wildcardRows = @(Get-DbaAgentJobStep @splatWildcardLiteral)
            ($wildcardRows.AgentJob -join ",") | Should -BeExactly $wildcardJobNames[2]
            $splatWildcardLiteral.Job = "${wildcardPrefix}_[*"
            @(Get-DbaAgentJobStep @splatWildcardLiteral).Count | Should -Be 0
            $splatWildcardLiteral.Job = $wildcardJobNames
            $splatWildcardLiteral.ExcludeJob = @("${wildcardPrefix}_[*", $wildcardJobNames[2])
            $wildcardRows = @(Get-DbaAgentJobStep @splatWildcardLiteral)
            (($wildcardRows.AgentJob | Sort-Object) -join ",") | Should -BeExactly (($wildcardJobNames[0, 1] | Sort-Object) -join ",")
        }
    }

    Context "Real job names containing wildcard characters" {
        BeforeAll {
            # Rule E+: pinned help :20 and :24 document -Job and -ExcludeJob wildcards, but a value equal
            # to a real job name of the instance stays literal; pinned Install-DbaMaintenanceSolution.ps1:803
            # passes a real $job.Name and then rewrites the steps of that job.
            $realPrefix = "native_wc_$([Guid]::NewGuid().ToString("N"))"
            $realJobNames = @("${realPrefix}_*", "${realPrefix}_?", "${realPrefix}_x")
            $realJobsCreated = New-Object System.Collections.Generic.List[string]
            foreach ($realJobName in $realJobNames) {
                $realJob = New-Object Microsoft.SqlServer.Management.Smo.Agent.Job($stepServer.JobServer, $realJobName)
                $realJob.IsEnabled = $false
                $realJob.Create()
                $realJobsCreated.Add($realJobName)
                $realJob.ApplyToTargetServer("(local)")
                $realStep = New-Object Microsoft.SqlServer.Management.Smo.Agent.JobStep($realJob, "native_wc_step")
                $realStep.SubSystem = [Microsoft.SqlServer.Management.Smo.Agent.AgentSubSystem]::TransactSql
                $realStep.DatabaseName = "master"
                $realStep.Command = "SELECT 1;"
                $realStep.Create()
            }
        }

        AfterAll {
            $stepServer.JobServer.Jobs.Refresh()
            foreach ($realCleanupName in $realJobsCreated) {
                $realCleanup = $stepServer.JobServer.Jobs[$realCleanupName]
                if ($null -ne $realCleanup) { $realCleanup.Drop() }
            }
        }

        It "selects a real job whose name contains * or ? alone by its exact name" {
            $splatRealExact = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Job             = $realJobNames[0]
                EnableException = $true
            }
            (@(Get-DbaAgentJobStep @splatRealExact).AgentJob -join ",") | Should -BeExactly $realJobNames[0]
            $splatRealExact.Job = $realJobNames[1].ToUpperInvariant()
            (@(Get-DbaAgentJobStep @splatRealExact).AgentJob -join ",") | Should -BeExactly $realJobNames[1]
            $splatRealExact.Job = $realJobNames[0, 1]
            ((@(Get-DbaAgentJobStep @splatRealExact).AgentJob | Sort-Object) -join ",") | Should -BeExactly (($realJobNames[0, 1] | Sort-Object) -join ",")
        }

        It "expands a non-colliding pattern beside jobs whose names contain * or ?" {
            $splatRealPattern = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Job             = "${realPrefix}*"
                EnableException = $true
            }
            ((@(Get-DbaAgentJobStep @splatRealPattern).AgentJob | Sort-Object) -join ",") | Should -BeExactly (($realJobNames | Sort-Object) -join ",")
            $splatRealPattern.ExcludeJob = $realJobNames[1]
            ((@(Get-DbaAgentJobStep @splatRealPattern).AgentJob | Sort-Object) -join ",") | Should -BeExactly (($realJobNames[0, 2] | Sort-Object) -join ",")
        }

        It "excludes only a real job whose name contains * or ? when its exact name is excluded" {
            $splatRealExclude = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Job             = $realJobNames
                ExcludeJob      = $realJobNames[1]
                EnableException = $true
            }
            ((@(Get-DbaAgentJobStep @splatRealExclude).AgentJob | Sort-Object) -join ",") | Should -BeExactly (($realJobNames[0, 2] | Sort-Object) -join ",")
        }
    }

    Context "Checklist: several instances with one failing" -Tag "NativeChecklist:multi-instance-failure" {
        It "returns output for the good instances and warns for the unreachable one" {
            $stepWarnings = @()
            $splatStepInstances = @{
                SqlInstance     = $TestConfig.InstanceSingle, $stepBadInstance, $TestConfig.InstanceSingle
                Job             = $stepJobName
                EnableException = $false
                WarningAction   = "SilentlyContinue"
                WarningVariable = "stepWarnings"
            }
            $stepRows = @(Get-DbaAgentJobStep @splatStepInstances)
            $stepRows.Count | Should -Be 2
            foreach ($stepRow in $stepRows) {
                $stepRow.AgentJob | Should -BeExactly $stepJobName
                $stepRow.Name | Should -BeExactly $stepName
            }
            ($stepWarnings -join " ") | Should -BeLike "*Failure*"
        }
    }

    Context "Checklist: EnableException on and off for a failing instance" -Tag "NativeChecklist:multi-instance-failure", "NativeChecklist:enable-exception" {
        It "warns and continues when EnableException is off" {
            $stepWarnings = @()
            $stepCaught = $null
            $stepRows = @()
            $splatStepOff = @{
                SqlInstance     = $TestConfig.InstanceSingle, $stepBadInstance
                Job             = $stepJobName
                EnableException = $false
                WarningAction   = "SilentlyContinue"
                WarningVariable = "stepWarnings"
            }
            try {
                $stepRows = @(Get-DbaAgentJobStep @splatStepOff)
            } catch {
                $stepCaught = $PSItem
            }
            $stepCaught | Should -BeNullOrEmpty
            $stepRows.Count | Should -Be 1
            ($stepWarnings -join " ") | Should -BeLike "*Failure*"
        }

        It "throws a connection error and emits nothing when EnableException is on" {
            $stepRows = New-Object "System.Collections.Generic.List[object]"
            $stepCaught = $null
            $splatStepOn = @{
                SqlInstance     = $TestConfig.InstanceSingle, $stepBadInstance
                Job             = $stepJobName
                EnableException = $true
            }
            try {
                Get-DbaAgentJobStep @splatStepOn | ForEach-Object { $stepRows.Add($PSItem) }
            } catch {
                $stepCaught = $PSItem
            }
            $stepRows.Count | Should -Be 0
            $stepCaught | Should -Not -BeNullOrEmpty
            $stepCaught.CategoryInfo.Category | Should -Be "ConnectionError"
            $stepCaught.TargetObject | Should -BeExactly "TCP:127.0.0.1,1"
        }
    }

    Context "Checklist: switches passed explicitly as false" -Tag "NativeChecklist:switch-false" {
        It 'treats -ExcludeDisabledJobs:$false as not excluding the disabled job' {
            $splatStepSwitch = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Job             = $stepJobName
                EnableException = $true
            }
            @(Get-DbaAgentJobStep @splatStepSwitch -ExcludeDisabledJobs).Count | Should -Be 0
            $stepRows = @(Get-DbaAgentJobStep @splatStepSwitch -ExcludeDisabledJobs:$false)
            $stepRows.Count | Should -Be 1
            $stepRows[0].AgentJob | Should -BeExactly $stepJobName
        }

        It 'treats -EnableException:$false as a warning instead of an exception' {
            $stepWarnings = @()
            $splatStepFalse = @{
                SqlInstance     = $stepBadInstance
                WarningAction   = "SilentlyContinue"
                WarningVariable = "stepWarnings"
            }
            $stepCaught = $null
            try {
                $stepRows = @(Get-DbaAgentJobStep @splatStepFalse -EnableException:$false)
            } catch {
                $stepCaught = $PSItem
            }
            $stepCaught | Should -BeNullOrEmpty
            $stepRows.Count | Should -Be 0
            ($stepWarnings -join " ") | Should -BeLike "*Failure*"
        }
    }

    Context "Checklist: WhatIf and Confirm" {
        # NativeChecklist: whatif-confirm N/A -- read-only command; no SupportsShouldProcess.
        # N/A: Get-DbaAgentJobStep is read-only and, like the pinned function, does not support
        # ShouldProcess, so there is no -WhatIf or -Confirm behavior to cover.
        It "exposes no WhatIf or Confirm parameter" {
            $stepParameters = (Get-Command $CommandName).Parameters.Keys
            $stepParameters | Should -Not -Contain "WhatIf"
            $stepParameters | Should -Not -Contain "Confirm"
        }
    }
}

Describe "Native Get-DbaAgentJobStep over SQL authentication" -Tag IntegrationTests {
    Context "SQL login" -Tag NativeChecklist:sql-login {
        BeforeAll {
            $loginInstance = $TestConfig.InstanceSqlLogin
            $loginCred = $TestConfig.SqlLoginCred
            $loginServer = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $loginCred -EnableException
            # Unique per leg and run: the instance is shared.
            $loginJobName = "native_jobstep_sqllogin_" + [Guid]::NewGuid().ToString("N")
            $loginJob = New-Object Microsoft.SqlServer.Management.Smo.Agent.Job -ArgumentList $loginServer.JobServer, $loginJobName
            $loginJob.IsEnabled = $false
            $loginJob.Create()
            $loginStep = New-Object Microsoft.SqlServer.Management.Smo.Agent.JobStep -ArgumentList $loginJob, "native_step_sqllogin"
            $loginStep.SubSystem = [Microsoft.SqlServer.Management.Smo.Agent.AgentSubSystem]::TransactSql
            $loginStep.DatabaseName = "master"
            $loginStep.Command = "SELECT 1;"
            $loginStep.Create()
        }
        AfterAll {
            if ($loginServer -and $loginJobName) {
                $loginServer.JobServer.Jobs.Refresh()
                $loginCleanup = $loginServer.JobServer.Jobs[$loginJobName]
                if ($null -ne $loginCleanup) { $loginCleanup.Drop() }
            }
        }

        It "works with -SqlCredential" {
            $splatLoginStep = @{
                SqlInstance     = $loginInstance
                SqlCredential   = $loginCred
                Job             = $loginJobName
                EnableException = $true
            }
            $loginRows = @(Get-DbaAgentJobStep @splatLoginStep)
            $loginRows.Count | Should -Be 1
            $loginRows[0].AgentJob | Should -BeExactly $loginJobName
            $loginRows[0].Name | Should -BeExactly "native_step_sqllogin"
        }

        It "fails cleanly without the credential: a warning and no output" {
            $loginWarnings = @()
            $splatLoginNoCredential = @{
                SqlInstance     = $loginInstance
                Job             = $loginJobName
                WarningAction   = "SilentlyContinue"
                WarningVariable = "loginWarnings"
            }
            $loginResult = @(Get-DbaAgentJobStep @splatLoginNoCredential)
            $loginResult.Count | Should -Be 0
            ($loginWarnings -join " ") | Should -BeLike "*Failure*"
        }

        It "fails cleanly without the credential: -EnableException throws a connection error" {
            $loginCaught = $null
            try {
                $null = Get-DbaAgentJobStep -SqlInstance $loginInstance -Job $loginJobName -EnableException
            } catch {
                $loginCaught = $PSItem
            }
            $loginCaught | Should -Not -BeNullOrEmpty
            $loginCaught.CategoryInfo.Category | Should -Be "ConnectionError"
        }
    }
}
