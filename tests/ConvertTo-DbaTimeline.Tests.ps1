#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "ConvertTo-DbaTimeline",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "InputObject",
                "ExcludeRowLabel",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
        $splatHistory = @{
            SqlInstance     = $TestConfig.InstanceSingle
            StartDate       = (Get-Date).AddDays(-7)
            ExcludeJobSteps = $true
        }
        $history = @(Get-DbaAgentJobHistory @splatHistory | Select-Object -First 5)
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When converting agent job history" {
        BeforeAll {
            $results = @($history | ConvertTo-DbaTimeline -OutVariable "global:dbatoolsciOutput")
        }

        It "Should return three output elements" {
            $results.Count | Should -Be 3
        }

        It "Should return HTML header as first element" {
            $results[0] | Should -BeOfType [System.String]
            $results[0] | Should -Match "<html>"
            $results[0] | Should -Match "dataTable\.addRows"
        }

        It "Should return HTML footer as last element" {
            $results[-1] | Should -BeOfType [System.String]
            $results[-1] | Should -Match "</html>"
            $results[-1] | Should -Match "dbatools"
        }

        It "Should contain timeline data rows in the body" {
            $html = $results -join "`n"
            $html | Should -Match "google\.visualization\.Timeline"
        }
    }

    Context "When using ExcludeRowLabel" {
        BeforeAll {
            $resultsNoLabel = @($history | ConvertTo-DbaTimeline -ExcludeRowLabel)
        }

        It "Should set showRowLabels to false" {
            $resultsNoLabel[-1] | Should -Match "showRowLabels: false"
        }
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return the correct type" {
            if (-not $global:dbatoolsciOutput) {
                Set-ItResult -Skipped -Because "no output was captured"
                return
            }
            $global:dbatoolsciOutput[0] | Should -BeOfType [System.String]
        }

        It "Should produce valid HTML when combined" {
            if (-not $global:dbatoolsciOutput) {
                Set-ItResult -Skipped -Because "no output was captured"
                return
            }
            $html = $global:dbatoolsciOutput -join "`n"
            $html | Should -Match "<html>"
            $html | Should -Match "</html>"
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "System\.String"
        }
    }
}