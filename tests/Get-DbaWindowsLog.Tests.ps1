#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaWindowsLog",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "Start",
                "End",
                "Credential",
                "MaxThreads",
                "MaxRemoteThreads",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests -Skip {
    # Skip IntegrationTests because the command is very unstable and should be reviewed.

    Context "Command returns proper info" {
        It "returns results" {
            $results = Get-DbaWindowsLog -SqlInstance $TestConfig.InstanceSingle
            $results | Should -Not -BeNullOrEmpty
        }
    }

    Context "Output validation" {
        BeforeAll {
            $outputResult = Get-DbaWindowsLog -SqlInstance $TestConfig.InstanceSingle
        }

        It "Returns output of type PSCustomObject" {
            if (-not $outputResult) { Set-ItResult -Skipped -Because "no result to validate" }
            $outputResult[0] | Should -BeOfType [PSCustomObject]
        }

        It "Has the expected properties" {
            if (-not $outputResult) { Set-ItResult -Skipped -Because "no result to validate" }
            $expectedProps = @("InstanceName", "Timestamp", "Spid", "Severity", "ErrorNumber", "State", "Message")
            foreach ($prop in $expectedProps) {
                $outputResult[0].PSObject.Properties.Name | Should -Contain $prop -Because "property '$prop' should exist on output"
            }
        }
    }
}