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

    Context "Converts Numeric LSN to Hex" {
        BeforeAll {
            $numericLSN = "00000000020000000024300001"
            $convertResults = Convert-DbaLSN -LSN $numericLSN -OutVariable "global:dbatoolsciOutput"
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

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return a PSCustomObject" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [PSCustomObject]
        }

        It "Should have the expected properties" {
            $expectedProperties = @(
                "Hexadecimal",
                "Numeric"
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

#
#    Integration test should appear below and are custom to the command you are writing.
#    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
#    for more guidance.
#