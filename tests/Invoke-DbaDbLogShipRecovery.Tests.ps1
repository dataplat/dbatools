#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Invoke-DbaDbLogShipRecovery",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "Database",
                "SqlCredential",
                "NoRecovery",
                "EnableException",
                "Force",
                "InputObject",
                "Delay"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
Describe $CommandName -Tag IntegrationTests -Skip {
    # Skip IntegrationTests because LogShipRecovery requires log shipping to be configured.

    Context "Output validation" {
        BeforeAll {
            $outputResult = Invoke-DbaDbLogShipRecovery -SqlInstance $TestConfig.InstanceSingle -Database "dbatoolsci_logship_recovery" -Force
        }

        It "Returns output of the expected type" {
            if (-not $outputResult) { Set-ItResult -Skipped -Because "no result to validate" }
            $outputResult[0] | Should -BeOfType [PSCustomObject]
        }

        It "Has the expected properties" {
            if (-not $outputResult) { Set-ItResult -Skipped -Because "no result to validate" }
            $expectedProperties = @("ComputerName", "InstanceName", "SqlInstance", "Database", "RecoverResult", "Comment")
            foreach ($prop in $expectedProperties) {
                $outputResult[0].PSObject.Properties.Name | Should -Contain $prop -Because "property '$prop' should exist on the output object"
            }
        }
    }
}