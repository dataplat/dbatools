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

    Context "Output Validation" {
        BeforeAll {
            # Create mock job history data for testing
            $mockJobHistory = [PSCustomObject]@{
                TypeName     = "AgentJobHistory"
                SqlInstance  = "TestInstance"
                InstanceName = "TestInstance"
                Job          = "TestJob"
                Status       = "Succeeded"
                StartDate    = (Get-Date).AddHours(-1)
                EndDate      = Get-Date
            }
            $result = $mockJobHistory | ConvertTo-DbaTimeline
        }

        It "Returns an array of three System.String objects (HTML parts)" {
            $result | Should -HaveCount 3
            $result[0] | Should -BeOfType [System.String]
            $result[1] | Should -BeOfType [System.String]
            $result[2] | Should -BeOfType [System.String]
        }

        It "First element contains HTML header with Google Charts references" {
            $result[0] | Should -BeLike "*<html>*"
            $result[0] | Should -BeLike "*google.charts.load*"
            $result[0] | Should -BeLike "*google.visualization.Timeline*"
        }

        It "Second element contains timeline data rows" {
            $result[1] | Should -BeLike "*TestJob*"
            $result[1] | Should -BeLike "*Succeeded*"
        }

        It "Third element contains closing HTML tags and chart rendering code" {
            $result[2] | Should -BeLike "*</body>*"
            $result[2] | Should -BeLike "*</html>*"
            $result[2] | Should -BeLike "*chart.draw*"
        }
    }
}

<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidance.
#>