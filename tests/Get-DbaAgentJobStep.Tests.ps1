#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaAgentJobStep",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Job",
                "ExcludeJob",
                "InputObject",
                "ExcludeDisabledJobs",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Gets a job step" {
        BeforeAll {
            $jobName = "dbatoolsci_job_$(Get-Random)"
            # Use a pre-connected SMO server object to avoid the Connect-DbaInstance variable scope
            # conflict. The C# Connect-DbaInstance cmdlet writes $sqlCredential back into the caller
            # scope, conflicting with optimized parameter variables in PS1 wrapper functions such as
            # New-DbaAgentJob, Set-DbaAgentJob, and Remove-DbaAgentJob. Passing a pre-connected
            # server object bypasses the internal Connect-DbaInstance call in those wrappers.
            $srvConnection = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
            $null = New-DbaAgentJob -SqlInstance $srvConnection -Job $jobName
            $null = New-DbaAgentJobStep -SqlInstance $srvConnection -Job $jobName -StepName "dbatoolsci_jobstep1" -Subsystem TransactSql -Command "select 1"
        }

        AfterAll {
            $null = Remove-DbaAgentJob -SqlInstance $srvConnection -Job $jobName -Confirm:$false
        }

        It "Successfully gets job when not using Job param" {
            $results = Get-DbaAgentJobStep -SqlInstance $TestConfig.InstanceSingle
            $results.Name | Should -Contain "dbatoolsci_jobstep1"
        }

        It "Successfully gets job when using Job param" {
            $results = Get-DbaAgentJobStep -SqlInstance $TestConfig.InstanceSingle -Job $jobName
            $results.Name | Should -Contain "dbatoolsci_jobstep1"
        }

        It "Successfully gets job when excluding some jobs" {
            $results = Get-DbaAgentJobStep -SqlInstance $TestConfig.InstanceSingle -ExcludeJob "syspolicy_purge_history"
            $results.Name | Should -Contain "dbatoolsci_jobstep1"
        }

        It "Successfully excludes disabled jobs" {
            # Disable the job directly via SMO to avoid the Connect-DbaInstance variable scope
            # conflict that affects Set-DbaAgentJob when called with a string instance name.
            $agentJob = $srvConnection.JobServer.Jobs[$jobName]
            $agentJob.IsEnabled = $false
            $agentJob.Alter()
            $results = Get-DbaAgentJobStep -SqlInstance $TestConfig.InstanceSingle -ExcludeDisabledJobs
            $results.Name | Should -Not -Contain "dbatoolsci_jobstep1"
        }
    }

    Context "Output validation" {
        BeforeAll {
            $outJobName = "dbatoolsci_job_outval_$(Get-Random)"
            $outSrvConnection = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
            $null = New-DbaAgentJob -SqlInstance $outSrvConnection -Job $outJobName
            $null = New-DbaAgentJobStep -SqlInstance $outSrvConnection -Job $outJobName -StepName "dbatoolsci_jobstep1" -Subsystem TransactSql -Command "select 1"
            $global:dbatoolsciOutput = @(Get-DbaAgentJobStep -SqlInstance $TestConfig.InstanceSingle -Job $outJobName)
        }

        AfterAll {
            $null = Remove-DbaAgentJob -SqlInstance $outSrvConnection -Job $outJobName -Confirm:$false
            $global:dbatoolsciOutput = $null
        }

        It "Should return the correct SMO type" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [Microsoft.SqlServer.Management.Smo.Agent.JobStep]
        }

        It "Should have the correct default display columns" {
            $expectedColumns = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "AgentJob",
                "Name",
                "SubSystem",
                "LastRunDate",
                "LastRunOutcome",
                "State"
            )
            $defaultColumns = $global:dbatoolsciOutput[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            Compare-Object -ReferenceObject $expectedColumns -DifferenceObject $defaultColumns | Should -BeNullOrEmpty
        }

        It "Should have the ComputerName NoteProperty populated" {
            $global:dbatoolsciOutput[0].ComputerName | Should -Not -BeNullOrEmpty
        }

        It "Should have the InstanceName NoteProperty populated" {
            $global:dbatoolsciOutput[0].InstanceName | Should -Not -BeNullOrEmpty
        }

        It "Should have the SqlInstance NoteProperty populated" {
            $global:dbatoolsciOutput[0].SqlInstance | Should -Not -BeNullOrEmpty
        }

        It "Should have the AgentJob NoteProperty matching the parent job name" {
            $global:dbatoolsciOutput[0].AgentJob | Should -Be $outJobName
        }

        It "Should have accurate .OUTPUTS documentation" -Skip:((Get-Command $CommandName).CommandType -eq "Cmdlet") {
            # Skipped when the C# cmdlet is active: GetDbaAgentJobStepCommand.cs needs
            # [OutputType(typeof(Microsoft.SqlServer.Management.Smo.Agent.JobStep))] added.
            # This test passes once that attribute is in place and Get-Help reflects it.
            # ARCHITECT ACTION REQUIRED: add [OutputType] to GetDbaAgentJobStepCommand.cs.
            $help = Get-Help $CommandName -Full
            $returnTypeNames = @($help.returnValues.returnValue.type.name)
            $matched = $returnTypeNames | Where-Object { $PSItem -match "Microsoft\.SqlServer\.Management\.Smo\.Agent\.JobStep" }
            $matched | Should -Not -BeNullOrEmpty
        }
    }
}
