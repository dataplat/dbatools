#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Set-DbaAgentJobOutputFile",
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
                "Step",
                "OutputFile",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Output validation" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $jobName = "dbatoolsci_outputtest_outputfile_$(Get-Random)"
            $stepName = "dbatoolsci_step1"
            $outputFilePath = "C:\temp\dbatoolsci_outputtest.txt"
            $null = New-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job $jobName
            $null = New-DbaAgentJobStep -SqlInstance $TestConfig.InstanceSingle -Job $jobName -StepName $stepName -Command "SELECT 1"
            $result = Set-DbaAgentJobOutputFile -SqlInstance $TestConfig.InstanceSingle -Job $jobName -Step $stepName -OutputFile $outputFilePath

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            Remove-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job $jobName -Confirm:$false -ErrorAction SilentlyContinue
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Returns output as PSCustomObject" {
            $result | Should -Not -BeNullOrEmpty
            $result[0] | Should -BeOfType PSCustomObject
        }

        It "Has the expected properties" {
            $expectedProps = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Job",
                "JobStep",
                "OutputFileName",
                "OldOutputFileName"
            )
            foreach ($prop in $expectedProps) {
                $result[0].psobject.Properties.Name | Should -Contain $prop -Because "property '$prop' should be present"
            }
        }

        It "Has correct property values" {
            $result[0].Job | Should -Be $jobName
            $result[0].JobStep | Should -Be $stepName
            $result[0].OutputFileName | Should -Be $outputFilePath
        }
    }
}