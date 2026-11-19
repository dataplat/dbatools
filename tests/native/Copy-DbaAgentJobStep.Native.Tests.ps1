#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Copy-DbaAgentJobStep",
    $PSDefaultParameterValues = $TestConfig.Defaults
)
# Azure SQL Database has no SQL Agent; the native refusal test covers both connection roles.
# https://learn.microsoft.com/azure/azure-sql/database/job-automation-overview
# NativeChecklist: sql-login N/A -- The pinned command has SourceSqlCredential and DestinationSqlCredential, not a SqlCredential parameter.

Describe "Native Copy-DbaAgentJobStep" -Tag IntegrationTests {
    BeforeAll {
        $source = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy1 -EnableException
        $destination = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy2 -EnableException
        $prefix = "nativestep_" + [guid]::NewGuid().ToString("N")
        $names = @(($prefix + '-keep_$&'), ($prefix + '-skip'))
        $jobs = @()
        foreach ($server in @($source, $destination)) {
            foreach ($name in $names) {
                $job = New-Object Microsoft.SqlServer.Management.Smo.Agent.Job -ArgumentList $server.JobServer, $name
                $job.IsEnabled = $false
                $job.Create()
                $job.ApplyToTargetServer([string]::Empty)
                $job.Refresh()
                $job.JobType.ToString() | Should -BeExactly 'Local'
                if ($server -eq $source) {
                    $jobs += $job
                    $step = New-Object Microsoft.SqlServer.Management.Smo.Agent.JobStep -ArgumentList $job, 'copyme'
                    $step.SubSystem = 'TransactSql'
                    $step.Command = "SELECT N'unchanged job step text'"
                    $step.DatabaseName = 'master'
                    $step.RetryAttempts = 2
                    $step.RetryInterval = 3
                    $step.Create()
                }
            }
        }
    }
    AfterEach {
        foreach ($name in $names) {
            $destination.JobServer.Jobs[$name].JobSteps.Refresh()
            foreach ($step in @($destination.JobServer.Jobs[$name].JobSteps)) { $step.Drop() }
        }
    }
    AfterAll {
        foreach ($server in @($source, $destination)) {
            $server.JobServer.Jobs.Refresh()
            foreach ($name in $names) {
                if ($server.JobServer.Jobs[$name]) { $server.JobServer.Jobs[$name].Drop() }
            }
        }
    }
    It "copies a job name containing regex replacement text literally" {
        $copy = @{
            Source = $source
            Destination = $destination
            Job = $names[0]
            Confirm = $false
            EnableException = $true
        }
        $result = @(Copy-DbaAgentJobStep @copy)
        $result.Count | Should -Be 1
        $result[0].Status | Should -Be Successful
        $destination.JobServer.Jobs[$names[0]].JobSteps.Refresh()
        $copied = $destination.JobServer.Jobs[$names[0]].JobSteps['copyme']
        $copied.Command | Should -Be $jobs[0].JobSteps['copyme'].Command
        $copied.RetryAttempts | Should -Be 2
        $copied.RetryInterval | Should -Be 3
    }
    It "honors documented job wildcard inclusion and exclusion" {
        $copy = @{
            Source = $source
            Destination = $destination
            Job = "$prefix-*"
            ExcludeJob = "$prefix-s*"
            Confirm = $false
            EnableException = $true
        }
        $result = @(Copy-DbaAgentJobStep @copy)
        $result.Count | Should -Be 1
        $result[0].Name | Should -Be $names[0]
        $result[0].Status | Should -Be Successful
        $destination.JobServer.Jobs[$names[1]].JobSteps.Refresh()
        $destination.JobServer.Jobs[$names[1]].JobSteps.Count | Should -Be 0
    }
    It "keeps existing job names containing wildcard characters literal" {
        $literalName = $prefix + '-literal[ab]'
        $matchingName = $prefix + '-literala'
        try {
            foreach ($server in @($source, $destination)) {
                foreach ($name in @($literalName, $matchingName)) {
                    $literalJob = New-Object Microsoft.SqlServer.Management.Smo.Agent.Job -ArgumentList $server.JobServer, $name
                    $literalJob.IsEnabled = $false
                    $literalJob.Create()
                    $literalJob.ApplyToTargetServer([string]::Empty)
                    $literalJob.Refresh()
                    $literalJob.JobType.ToString() | Should -BeExactly 'Local'
                    if ($server -eq $source) {
                        $literalStep = New-Object Microsoft.SqlServer.Management.Smo.Agent.JobStep -ArgumentList $literalJob, 'literalstep'
                        $literalStep.SubSystem = 'TransactSql'
                        $literalStep.Command = 'SELECT 1'
                        $literalStep.DatabaseName = 'master'
                        $literalStep.Create()
                    }
                }
                $server.JobServer.Jobs.Refresh()
            }
            $literalResult = @(Copy-DbaAgentJobStep -Source $source -Destination $destination -Job $literalName -Confirm:$false -EnableException)
            $literalResult.Count | Should -Be 1
            $literalResult[0].Name | Should -BeExactly $literalName
            $literalResult[0].Status | Should -BeExactly 'Successful'
            $destination.JobServer.Jobs[$literalName].JobSteps.Refresh()
            $destination.JobServer.Jobs[$literalName].JobSteps.Count | Should -Be 1
            $destination.JobServer.Jobs[$matchingName].JobSteps.Refresh()
            $destination.JobServer.Jobs[$matchingName].JobSteps.Count | Should -Be 0
        } finally {
            foreach ($server in @($source, $destination)) {
                $server.JobServer.Jobs.Refresh()
                foreach ($name in @($literalName, $matchingName)) {
                    if ($server.JobServer.Jobs.Contains($name)) { $server.JobServer.Jobs[$name].Drop() }
                }
            }
        }
    }
    It "keeps literal wildcard precedence after source filtering and across pipeline records" {
        $collisionPrefix = "native_step_collision_" + [guid]::NewGuid().ToString("N")
        $collisionNames = @(($collisionPrefix + "-literal*"), ($collisionPrefix + "-literal1"))
        $collisionSourceJobs = @()
        try {
            foreach ($collisionServer in @($source, $destination)) {
                foreach ($collisionName in $collisionNames) {
                    $collisionJob = New-Object Microsoft.SqlServer.Management.Smo.Agent.Job -ArgumentList $collisionServer.JobServer, $collisionName
                    $collisionJob.IsEnabled = $false
                    $collisionJob.Create()
                    $collisionJob.ApplyToTargetServer([string]::Empty)
                    $collisionJob.Refresh()
                    $collisionJob.JobType.ToString() | Should -BeExactly "Local"
                    if ($collisionServer -eq $source) {
                        $collisionSourceJobs += $collisionJob
                        $collisionStep = New-Object Microsoft.SqlServer.Management.Smo.Agent.JobStep -ArgumentList $collisionJob, "collision_step"
                        $collisionStep.SubSystem = "TransactSql"
                        $collisionStep.DatabaseName = "master"
                        $collisionStep.Command = "SELECT 42 AS collision_value"
                        $collisionStep.Create()
                    }
                }
                $collisionServer.JobServer.Jobs.Refresh()
            }
            $splatCollisionSource = @{
                Source          = $source
                Destination     = $destination
                Job             = $collisionNames
                ExcludeJob      = $collisionNames[0]
                Confirm         = $false
                EnableException = $true
            }
            $collisionSourceResult = @(Copy-DbaAgentJobStep @splatCollisionSource)
            $collisionSourceResult.Count | Should -Be 1
            $collisionSourceResult[0].Name | Should -BeExactly $collisionNames[1]
            $collisionSourceResult[0].Status | Should -BeExactly "Successful"
            $destination.JobServer.Jobs[$collisionNames[0]].JobSteps.Refresh()
            $destination.JobServer.Jobs[$collisionNames[0]].JobSteps.Count | Should -Be 0
            $destination.JobServer.Jobs[$collisionNames[1]].JobSteps.Refresh()
            $destination.JobServer.Jobs[$collisionNames[1]].JobSteps["collision_step"].Command | Should -BeExactly "SELECT 42 AS collision_value"
            foreach ($collisionResetName in $collisionNames) {
                foreach ($collisionResetStep in @($destination.JobServer.Jobs[$collisionResetName].JobSteps)) {
                    $collisionResetStep.Drop()
                }
                $destination.JobServer.Jobs[$collisionResetName].JobSteps.Refresh()
            }
            $splatCollisionPipeline = @{
                Destination     = $destination
                Job             = $collisionNames[0]
                Confirm         = $false
                EnableException = $true
            }
            $collisionPipelineResult = @($collisionSourceJobs | Copy-DbaAgentJobStep @splatCollisionPipeline)
            $collisionPipelineResult.Count | Should -Be 1
            $collisionPipelineResult[0].Name | Should -BeExactly $collisionNames[0]
            $collisionPipelineResult[0].Status | Should -BeExactly "Successful"
            $destination.JobServer.Jobs[$collisionNames[0]].JobSteps.Refresh()
            $destination.JobServer.Jobs[$collisionNames[0]].JobSteps["collision_step"].Command | Should -BeExactly "SELECT 42 AS collision_value"
            $destination.JobServer.Jobs[$collisionNames[1]].JobSteps.Refresh()
            $destination.JobServer.Jobs[$collisionNames[1]].JobSteps.Count | Should -Be 0
        } finally {
            foreach ($collisionCleanupServer in @($source, $destination)) {
                $collisionCleanupServer.JobServer.Jobs.Refresh()
                foreach ($collisionCleanupName in $collisionNames) {
                    if ($collisionCleanupServer.JobServer.Jobs.Contains($collisionCleanupName)) {
                        $collisionCleanupServer.JobServer.Jobs[$collisionCleanupName].Drop()
                    }
                }
            }
        }
    }
    It "refuses Azure step operations and continues to a supported destination" -Tag NativeChecklist:azure-sqldb {
        $azureStepServer = $null
        try {
            for ($attempt = 0; $attempt -le 6; $attempt++) {
                try {
                    $azureStepServer = Connect-DbaInstance -SqlInstance $TestConfig.AzureSqlDbServer -Database $TestConfig.AzureSqlDbName -SqlCredential $TestConfig.AzureSqlDbCred -EnableException
                    break
                } catch {
                    $azureError = $_.Exception
                    $resuming = $false
                    while ($azureError) {
                        if ($azureError.Number -in 40613, -2 -or $azureError -is [System.TimeoutException]) { $resuming = $true }
                        $azureError = $azureError.InnerException
                    }
                    if (-not $resuming -or $attempt -eq 6) { throw }
                    Start-Sleep -Seconds 10
                }
            }
            $azureStepServer.DatabaseEngineEdition.ToString() | Should -BeExactly 'SqlDatabase'
            $azureStepWarnings = @()
            $azureStepResult = @(Copy-DbaAgentJobStep -InputObject $jobs[1] -Destination @($azureStepServer, $destination) -Confirm:$false -EnableException:$false -WarningAction SilentlyContinue -WarningVariable azureStepWarnings)
            $azureStepResult.Count | Should -Be 1
            $azureStepResult[0].Status | Should -BeExactly 'Successful'
            ($azureStepWarnings -join ' ') | Should -BeLike '*Azure SQL Database not supported*'
            { Copy-DbaAgentJobStep -InputObject $jobs[1] -Destination $azureStepServer -Confirm:$false -EnableException } | Should -Throw '*Azure SQL Database not supported*'
            # The nested Get-DbaAgentJob source call does not receive the outer EnableException switch.
            foreach ($outerEnableException in @($false, $true)) {
                $azureStepWarnings = @()
                @(Copy-DbaAgentJobStep -Source $azureStepServer -Destination $destination -Job $names[1] -Confirm:$false -EnableException:$outerEnableException -WarningAction SilentlyContinue -WarningVariable azureStepWarnings).Count | Should -Be 0
                ($azureStepWarnings -join ' ') | Should -BeLike '*Azure SQL Database not supported*'
            }
        } finally {
            if ($azureStepServer) { $azureStepServer.ConnectionContext.Disconnect() }
        }
    }
    It "preserves the nested source warning with either EnableException value" -Tag NativeChecklist:enable-exception {
        # Copy-DbaAgentJobStep:121-131 omits EnableException; Get-DbaAgentJob:158-161 warns locally.
        foreach ($outerEnableException in @($false, $true)) {
            $sourceWarnings = @()
            $sourceErrors = @()
            @(Copy-DbaAgentJobStep -Source 'tcp:127.0.0.1,1' -InputObject $jobs[1] -Destination $destination -Confirm:$false -EnableException:$outerEnableException -WarningAction SilentlyContinue -WarningVariable sourceWarnings -ErrorVariable sourceErrors).Count | Should -Be 0
            $sourceErrors.Count | Should -Be 0
            $sourceWarnings.Count | Should -Be 1
            $sourceWarnings[0].Message | Should -Match '\[Get-DbaAgentJob\] Failure \| The remote computer refused the network connection\.?$'
        }
    }
    It "copies multiple pipeline jobs with explicit false switches" -Tag NativeChecklist:pipeline-multiple, NativeChecklist:switch-false {
        $copy = @{
            Destination = $destination
            Confirm = $false
            EnableException = $false
        }
        $results = @($jobs | Copy-DbaAgentJobStep @copy)
        $results.Count | Should -Be 2
        @($results | Where-Object Status -ne Successful).Count | Should -Be 0
    }
    It "leaves destination steps unchanged under WhatIf" -Tag NativeChecklist:whatif-confirm {
        $copy = @{
            Destination = $destination
            WhatIf = $true
            Confirm = $false
        }
        @($jobs | Copy-DbaAgentJobStep @copy).Count | Should -Be 0
        foreach ($name in $names) {
            $destination.JobServer.Jobs[$name].JobSteps.Refresh()
            $destination.JobServer.Jobs[$name].JobSteps.Count | Should -Be 0
        }
    }
    It "continues to a valid destination after connection failure" -Tag NativeChecklist:multi-instance-failure, NativeChecklist:enable-exception {
        $copy = @{
            Destination = @('tcp:127.0.0.1,1', $destination)
            InputObject = $jobs[1]
            Confirm = $false
            EnableException = $false
            WarningVariable = 'warnings'
            WarningAction = 'SilentlyContinue'
        }
        $result = @(Copy-DbaAgentJobStep @copy)
        $result.Count | Should -Be 1
        $result[0].Status | Should -Be Successful
        ($warnings -join ' ') | Should -Match Failure
    }
    It "terminates on connection failure with EnableException" -Tag NativeChecklist:enable-exception {
        $copy = @{
            Destination = 'tcp:127.0.0.1,1'
            InputObject = $jobs[1]
            Confirm = $false
            EnableException = $true
        }
        { Copy-DbaAgentJobStep @copy } | Should -Throw
    }
}
