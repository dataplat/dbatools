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
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $jobName = "dbatoolsci_outputfile_$(Get-Random)"
        $stepName = "dbatoolsci_step1"
        $outputFilePath = "C:\Logs\dbatoolsci_output.txt"

        $null = New-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job $jobName
        $splatStep = @{
            SqlInstance = $TestConfig.InstanceSingle
            Job         = $jobName
            StepName    = $stepName
            Subsystem   = "TransactSql"
            Command     = "SELECT 1"
        }
        $null = New-DbaAgentJobStep @splatStep

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Remove-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job $jobName -Confirm:$false -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When setting output file on a job step" {
        It "Should set the output file for the specified step" {
            $splatOutput = @{
                SqlInstance = $TestConfig.InstanceSingle
                Job         = $jobName
                Step        = $stepName
                OutputFile  = $outputFilePath
            }
            $results = Set-DbaAgentJobOutputFile @splatOutput -OutVariable "global:dbatoolsciOutput"
            $results.OutputFileName | Should -Be $outputFilePath
            $results.Job | Should -Be $jobName
            $results.JobStep | Should -Be $stepName
        }
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return a PSCustomObject" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [PSCustomObject]
        }

        It "Should have the expected properties" {
            $expectedProperties = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Job",
                "JobStep",
                "OutputFileName",
                "OldOutputFileName"
            )
            $actualProperties = $global:dbatoolsciOutput[0].PSObject.Properties.Name
            Compare-Object -ReferenceObject $expectedProperties -DifferenceObject $actualProperties | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "PSCustomObject"
        }
    }
}