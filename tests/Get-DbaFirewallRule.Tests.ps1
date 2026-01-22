#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaFirewallRule",
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
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Output Validation" {
        BeforeAll {
            # Note: This test validates the structure of the output object
            # Actual integration tests are performed with New-DbaFirewallRule
            # We mock the remote execution to test output structure without requiring firewall access
            Mock -ModuleName dbatools Invoke-Command2 {
                [PSCustomObject]@{
                    Successful = $true
                    Rules      = @(
                        [PSCustomObject]@{
                            DisplayName = "SQL Server default instance"
                            Name        = "SQL Server default instance"
                            Protocol    = "TCP"
                            LocalPort   = "1433"
                            Program     = "C:\Program Files\Microsoft SQL Server\MSSQL15.MSSQLSERVER\MSSQL\Binn\sqlservr.exe"
                            Rule        = New-Object PSObject
                        }
                    )
                    Verbose    = @()
                    Warning    = $null
                    Error      = $null
                    Exception  = $null
                }
            }
            $result = Get-DbaFirewallRule -SqlInstance $TestConfig.instance1 -EnableException
        }

        It "Returns PSCustomObject" {
            $result.PSObject.TypeNames | Should -Contain "System.Management.Automation.PSCustomObject"
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "DisplayName",
                "Type",
                "Protocol",
                "LocalPort",
                "Program"
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }

        It "Has the additional properties available" {
            $result.PSObject.Properties.Name | Should -Contain "Name"
            $result.PSObject.Properties.Name | Should -Contain "Rule"
            $result.PSObject.Properties.Name | Should -Contain "Credential"
        }
    }
}

<#
The command will be tested together with New-DbaFirewallRule
#>