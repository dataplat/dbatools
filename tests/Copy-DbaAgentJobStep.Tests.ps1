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
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $sourceJobName = "dbatoolsci_copyjobstep"
        $sourceJobMultiStepName = "dbatoolsci_copyjobstep_multi"

        $null = New-DbaAgentJob -SqlInstance $TestConfig.instance2 -Job $sourceJobName
        $splatStep1 = @{
            SqlInstance = $TestConfig.instance2
            Job         = $sourceJobName
            StepName    = "Step1"
            Subsystem   = "TransactSql"
            Command     = "SELECT 1"
        }
        $null = New-DbaAgentJobStep @splatStep1

        $null = New-DbaAgentJob -SqlInstance $TestConfig.instance2 -Job $sourceJobMultiStepName
        $splatMultiStep1 = @{
            SqlInstance = $TestConfig.instance2
            Job         = $sourceJobMultiStepName
            StepName    = "Step1"
            Subsystem   = "TransactSql"
            Command     = "SELECT 1"
        }
        $null = New-DbaAgentJobStep @splatMultiStep1
        $splatMultiStep2 = @{
            SqlInstance = $TestConfig.instance2
            Job         = $sourceJobMultiStepName
            StepName    = "Step2"
            Subsystem   = "TransactSql"
            Command     = "SELECT 2"
        }
        $null = New-DbaAgentJobStep @splatMultiStep2

        $null = Copy-DbaAgentJob -Source $TestConfig.instance2 -Destination $TestConfig.instance3 -Job $sourceJobName, $sourceJobMultiStepName

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Remove-DbaAgentJob -SqlInstance $TestConfig.instance2 -Job $sourceJobName, $sourceJobMultiStepName -ErrorAction SilentlyContinue
        $null = Remove-DbaAgentJob -SqlInstance $TestConfig.instance3 -Job $sourceJobName, $sourceJobMultiStepName -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $command = Get-Command $CommandName
            $hasParameters = $command.Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Source",
                "SourceSqlCredential",
                "Destination",
                "DestinationSqlCredential",
                "Job",
                "ExcludeJob",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Command synchronizes job steps properly" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $splatNewStep = @{
                SqlInstance = $TestConfig.instance2
                Job         = $sourceJobName
                StepName    = "Step2"
                Subsystem   = "TransactSql"
                Command     = "SELECT 2"
            }
            $null = New-DbaAgentJobStep @splatNewStep

            $splatCopyStep = @{
                Source      = $TestConfig.instance2
                Destination = $TestConfig.instance3
                Job         = $sourceJobName
            }
            $results = Copy-DbaAgentJobStep @splatCopyStep

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "returns success status" {
            $results.Name | Should -Be $sourceJobName
            $results.Status | Should -Be "Successful"
            $results.Notes | Should -BeLike "Synchronized * job step(s)"
        }

        It "synchronizes all steps to destination" {
            $destSteps = Get-DbaAgentJobStep -SqlInstance $TestConfig.instance3 -Job $sourceJobName
            $destSteps.Count | Should -Be 2
            $destSteps.Name | Should -Contain "Step1"
            $destSteps.Name | Should -Contain "Step2"
        }

        It "preserves step commands" {
            $destSteps = Get-DbaAgentJobStep -SqlInstance $TestConfig.instance3 -Job $sourceJobName
            ($destSteps | Where-Object Name -eq "Step1").Command | Should -BeLike "*SELECT 1*"
            ($destSteps | Where-Object Name -eq "Step2").Command | Should -BeLike "*SELECT 2*"
        }
    }

    Context "Job history is preserved" {
        It "does not destroy job execution history" {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $splatStartJob = @{
                SqlInstance = $TestConfig.instance3
                Job         = $sourceJobMultiStepName
            }
            $null = Start-DbaAgentJob @splatStartJob
            Start-Sleep -Seconds 2

            $historyBefore = Get-DbaAgentJobHistory -SqlInstance $TestConfig.instance3 -Job $sourceJobMultiStepName

            $splatModifyStep = @{
                SqlInstance = $TestConfig.instance2
                Job         = $sourceJobMultiStepName
                StepName    = "Step3"
                Subsystem   = "TransactSql"
                Command     = "SELECT 3"
            }
            $null = New-DbaAgentJobStep @splatModifyStep

            $splatCopyModified = @{
                Source      = $TestConfig.instance2
                Destination = $TestConfig.instance3
                Job         = $sourceJobMultiStepName
            }
            $null = Copy-DbaAgentJobStep @splatCopyModified

            $historyAfter = Get-DbaAgentJobHistory -SqlInstance $TestConfig.instance3 -Job $sourceJobMultiStepName

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")

            $historyBefore.Count | Should -BeGreaterThan 0
            $historyAfter.Count | Should -Be $historyBefore.Count
        }
    }

    Context "Non-existent job handling" {
        It "skips jobs that don't exist on destination" {
            $splatNonExistent = @{
                Source      = $TestConfig.instance2
                Destination = $TestConfig.instance3
                Job         = "NonExistentJob_$(Get-Random)"
            }
            $results = Copy-DbaAgentJobStep @splatNonExistent
            $results | Should -BeNullOrEmpty
        }
    }

    Context "Pipeline support" {
        It "accepts job objects from Get-DbaAgentJob" {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $splatGetJob = @{
                SqlInstance = $TestConfig.instance2
                Job         = $sourceJobName
            }
            $job = Get-DbaAgentJob @splatGetJob

            $results = $job | Copy-DbaAgentJobStep -Destination $TestConfig.instance3

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")

            $results.Name | Should -Be $sourceJobName
            $results.Status | Should -Be "Successful"
        }
    }
}
