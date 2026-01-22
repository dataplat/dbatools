#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaSpn",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "ComputerName",
                "AccountName",
                "Credential",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Output Validation" {
        BeforeAll {
            # Note: This command requires Active Directory access and may not work in all test environments
            # Testing with localhost/current computer as the most likely to succeed
            $result = Get-DbaSpn -ComputerName $env:COMPUTERNAME -EnableException -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
        }

        It "Returns PSCustomObject" {
            if ($result) {
                $result[0].PSObject.TypeNames | Should -Contain 'System.Management.Automation.PSCustomObject'
            } else {
                Set-ItResult -Skipped -Because "No SPNs found in test environment"
            }
        }

        It "Has the expected default display properties" {
            if ($result) {
                $expectedProps = @(
                    'Input',
                    'AccountName',
                    'ServiceClass',
                    'Port',
                    'SPN'
                )
                $actualProps = $result[0].PSObject.Properties.Name
                foreach ($prop in $expectedProps) {
                    $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
                }
            } else {
                Set-ItResult -Skipped -Because "No SPNs found in test environment"
            }
        }
    }
}
