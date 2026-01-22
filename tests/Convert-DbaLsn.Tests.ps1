#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Convert-DbaLSN",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "LSN",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag UnitTests {
    InModuleScope dbatools {
        Context "Converts Numeric LSN to Hex" {
            BeforeAll {
                $numericLSN = "00000000020000000024300001"
                $convertResults = Convert-DbaLSN -LSN $numericLSN
            }

            It "Should convert to 00000014:000000f3:0001" {
                $convertResults.Hexadecimal | Should -Be "00000014:000000f3:0001"
            }
        }

        Context "Converts Numeric LSN to Hex without leading 0s" {
            BeforeAll {
                $shortLSN = "20000000024300001"
                $shortResults = Convert-DbaLSN -LSN $shortLSN
            }

            It "Should convert to 00000014:000000f3:0001" {
                $shortResults.Hexadecimal | Should -Be "00000014:000000f3:0001"
            }
        }

        Context "Converts Hex LSN to Numeric" {
            BeforeAll {
                $hexLSN = "00000014:000000f3:0001"
                $hexResults = Convert-DbaLSN -LSN $hexLSN
            }

            It "Should convert to 20000000024300001" {
                $hexResults.Numeric | Should -Be 20000000024300001
            }
        }

        Context "Output Validation" {
            BeforeAll {
                $result = Convert-DbaLSN -LSN "00000014:000000f3:0001" -EnableException
            }

            It "Returns PSCustomObject" {
                $result.PSObject.TypeNames | Should -Contain "System.Management.Automation.PSCustomObject"
            }

            It "Has the expected properties" {
                $expectedProps = @(
                    "Hexadecimal",
                    "Numeric"
                )
                $actualProps = $result.PSObject.Properties.Name
                foreach ($prop in $expectedProps) {
                    $actualProps | Should -Contain $prop -Because "property '$prop' should be present"
                }
            }

            It "Has exactly two properties" {
                $result.PSObject.Properties.Name.Count | Should -Be 2 -Because "command should return only Hexadecimal and Numeric properties"
            }
        }
    }
}

#
#    Integration test should appear below and are custom to the command you are writing.
#    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
#    for more guidance.
#