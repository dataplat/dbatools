#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Copy-DbaAgentJobStep",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Source",
                "SourceSqlCredential",
                "Destination",
                "DestinationSqlCredential",
                "Job",
                "ExcludeJob",
                "Step",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Create unique job names for testing
        $sourceJobName = "dbatoolsci_copyjobstep_$(Get-Random)"
        $pipelineJobName = "dbatoolsci_copyjobstep_pipeline_$(Get-Random)"

        # Create source job with one step
        $null = New-DbaAgentJob -SqlInstance $TestConfig.InstanceCopy1 -Job $sourceJobName
        $splatStep1 = @{
            SqlInstance = $TestConfig.InstanceCopy1
            Job         = $sourceJobName
            StepName    = "Step1"
            Subsystem   = "TransactSql"
            Command     = "SELECT 1"
        }
        $null = New-DbaAgentJobStep @splatStep1

        # Create pipeline test job separately
        $null = New-DbaAgentJob -SqlInstance $TestConfig.InstanceCopy1 -Job $pipelineJobName
        $splatPipelineStep = @{
            SqlInstance = $TestConfig.InstanceCopy1
            Job         = $pipelineJobName
            StepName    = "PipelineStep1"
            Subsystem   = "TransactSql"
            Command     = "SELECT 'pipeline'"
        }
        $null = New-DbaAgentJobStep @splatPipelineStep

        # Copy jobs to destination so they exist there for step synchronization tests
        $null = Copy-DbaAgentJob -Source $TestConfig.InstanceCopy1 -Destination $TestConfig.InstanceCopy2 -Job $sourceJobName, $pipelineJobName

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup all created jobs
        $null = Remove-DbaAgentJob -SqlInstance $TestConfig.InstanceCopy1 -Job $sourceJobName, $pipelineJobName -Confirm:$false -ErrorAction SilentlyContinue
        $null = Remove-DbaAgentJob -SqlInstance $TestConfig.InstanceCopy2 -Job $sourceJobName, $pipelineJobName -Confirm:$false -ErrorAction SilentlyContinue
    }

    Context "Command synchronizes job steps properly" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Add a second step to source job to test synchronization
            $splatNewStep = @{
                SqlInstance = $TestConfig.InstanceCopy1
                Job         = $sourceJobName
                StepName    = "Step2"
                Subsystem   = "TransactSql"
                Command     = "SELECT 2"
            }
            $null = New-DbaAgentJobStep @splatNewStep

            $splatCopyStep = @{
                Source      = $TestConfig.InstanceCopy1
                Destination = $TestConfig.InstanceCopy2
                Job         = $sourceJobName
            }
            $results = Copy-DbaAgentJobStep @splatCopyStep

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Returns success status" {
            $results.Name | Should -Be $sourceJobName
            $results.Status | Should -Be "Successful"
            $results.Notes | Should -BeLike "Synchronized * job step(s)"
        }

        It "Synchronizes all steps to destination" {
            $destSteps = Get-DbaAgentJobStep -SqlInstance $TestConfig.InstanceCopy2 -Job $sourceJobName
            $destSteps.Count | Should -Be 2
            $destSteps.Name | Should -Contain "Step1"
            $destSteps.Name | Should -Contain "Step2"
        }

        It "Preserves step commands" {
            $destSteps = Get-DbaAgentJobStep -SqlInstance $TestConfig.InstanceCopy2 -Job $sourceJobName
            ($destSteps | Where-Object Name -eq "Step1").Command | Should -BeLike "*SELECT 1*"
            ($destSteps | Where-Object Name -eq "Step2").Command | Should -BeLike "*SELECT 2*"
        }
    }

    Context "Non-existent job handling" {
        It "Skips jobs that do not exist on destination" {
            $splatNonExistent = @{
                Source      = $TestConfig.InstanceCopy1
                Destination = $TestConfig.InstanceCopy2
                Job         = "NonExistentJob_$(Get-Random)"
            }
            $results = Copy-DbaAgentJobStep @splatNonExistent
            $results | Should -BeNullOrEmpty
        }
    }

    Context "Pipeline support" {
        It "Accepts job objects from Get-DbaAgentJob" {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $job = Get-DbaAgentJob -SqlInstance $TestConfig.InstanceCopy1 -Job $pipelineJobName
            $results = $job | Copy-DbaAgentJobStep -Destination $TestConfig.InstanceCopy2

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")

            $results.Name | Should -Be $pipelineJobName
            $results.Status | Should -Be "Successful"
        }
    }
}
