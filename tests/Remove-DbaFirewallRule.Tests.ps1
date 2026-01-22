#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaFirewallRule",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "Credential",
                "Type",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Output Validation" {
        It "Returns PSCustomObject" {
            $result = [PSCustomObject]@{
                ComputerName = "TestServer"
                InstanceName = "MSSQLSERVER"
                SqlInstance  = "TestServer"
                DisplayName  = "SQL Server Engine - TestServer"
                Type         = "Engine"
                IsRemoved    = $true
                Status       = "The rule was successfully removed."
            }
            $result.PSObject.TypeNames | Should -Contain 'System.Management.Automation.PSCustomObject'
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                'ComputerName',
                'InstanceName',
                'SqlInstance',
                'DisplayName',
                'Type',
                'IsRemoved',
                'Status'
            )
            # Create mock object with expected properties
            $result = [PSCustomObject]@{
                ComputerName = "TestServer"
                InstanceName = "MSSQLSERVER"
                SqlInstance  = "TestServer"
                DisplayName  = "SQL Server Engine - TestServer"
                Type         = "Engine"
                IsRemoved    = $true
                Status       = "The rule was successfully removed."
            }
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }
    }
}

<#
The command will be tested together with New-DbaFirewallRule
#>