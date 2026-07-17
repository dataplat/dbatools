#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
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
                "DateFormat",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Growth event input" {
        BeforeAll {
            $growthEvent = [PSCustomObject]@{
                SqlInstance  = "sql1"
                InstanceName = "MSSQLSERVER"
                EventClass   = 92
                ChangeInSize = 16
                DatabaseName = "MyDb"
                StartTime    = [datetime]"2024-01-01T00:00:00"
                EndTime      = [datetime]"2024-01-01T00:01:00"
            }
            $growthEventWithQuote = [PSCustomObject]@{
                SqlInstance  = "sql1"
                InstanceName = "MSSQLSERVER"
                EventClass   = 92
                ChangeInSize = 16
                DatabaseName = "O'Reilly"
                StartTime    = [datetime]"2024-01-01T00:00:00"
                EndTime      = [datetime]"2024-01-01T00:01:00"
            }
        }

        It "Supports Find-DbaDbGrowthEvent style input" {
            $result = $growthEvent | ConvertTo-DbaTimeline

            $result | Should -HaveCount 3
            $result[1] | Should -Match "Data Grow"
            $result[2] | Should -Match ([regex]::Escape("<code>Find-DbaDbGrowthEvent</code>"))
        }

        It "Escapes database names for JavaScript output" {
            $result = $growthEventWithQuote | ConvertTo-DbaTimeline

            $result[1] | Should -BeLike "*O\'Reilly*"
        }

        It "Uses the requested date format in tooltips and the timeline axis" {
            $result = $growthEvent | ConvertTo-DbaTimeline -DateFormat "MM/dd"

            $result[2] | Should -Match ([regex]::Escape("pattern: 'MM/dd/yy HH:mm:ss'"))
            $result[2] | Should -Match ([regex]::Escape("format: 'MM/dd HH:mm'"))
        }

        It "Does not append a second year to a format that includes one" {
            $result = $growthEvent | ConvertTo-DbaTimeline -DateFormat "yyyy-MM-dd"

            $result[2] | Should -Match ([regex]::Escape("pattern: 'yyyy-MM-dd HH:mm:ss'"))
        }

        It "Rejects date formats that could inject JavaScript" {
            { $growthEvent | ConvertTo-DbaTimeline -DateFormat "';alert(1);//" } | Should -Throw
        }
    }
}

<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidance.
#>
