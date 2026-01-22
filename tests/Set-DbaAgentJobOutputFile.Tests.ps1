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

    Context "Output Validation" {
        BeforeAll {
            $splatConnection = @{
                SqlInstance     = $TestConfig.instance2
                SqlCredential   = $TestConfig.SqlCredential
                EnableException = $true
            }
            $jobName = "dbatoolsci_outputfiletest_$(Get-Random)"
            $outputPath = "C:\temp\dbatoolsci_$(Get-Random).txt"

            # Create test job with a step
            $null = New-DbaAgentJob @splatConnection -Job $jobName
            $null = New-DbaAgentJobStep @splatConnection -Job $jobName -StepName "Step1" -Command "SELECT 1"

            # Set output file
            $result = Set-DbaAgentJobOutputFile @splatConnection -Job $jobName -Step "Step1" -OutputFile $outputPath
        }

        AfterAll {
            # Cleanup
            $splatConnection = @{
                SqlInstance     = $TestConfig.instance2
                SqlCredential   = $TestConfig.SqlCredential
                EnableException = $true
            }
            $null = Remove-DbaAgentJob @splatConnection -Job $jobName -Confirm:$false
        }

        It "Returns PSCustomObject" {
            $result.PSObject.TypeNames | Should -Contain 'System.Management.Automation.PSCustomObject'
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                'ComputerName',
                'InstanceName',
                'SqlInstance',
                'Job',
                'JobStep',
                'OutputFileName',
                'OldOutputFileName'
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }

        It "Returns correct property values" {
            $result.Job | Should -Be $jobName
            $result.JobStep | Should -Be "Step1"
            $result.OutputFileName | Should -Be $outputPath
        }
    }
}

<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>