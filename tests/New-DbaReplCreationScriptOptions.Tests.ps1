#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "New-DbaReplCreationScriptOptions",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = @( )  # Command does not use [CmdletBinding()]
            $expectedParameters += @(
                "Options",
                "NoDefaults"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $result = New-DbaReplCreationScriptOptions
        }

        It "Returns the documented output type" {
            $result | Should -BeOfType [Microsoft.SqlServer.Replication.CreationScriptOptions]
        }

        It "Includes default options when -NoDefaults is not specified" {
            $result | Should -Match 'PrimaryObject'
            $result | Should -Match 'CustomProcedures'
            $result | Should -Match 'Identity'
            $result | Should -Match 'ClusteredIndexes'
            $result | Should -Match 'DriPrimaryKey'
        }
    }

    Context "Output with -NoDefaults" {
        BeforeAll {
            $result = New-DbaReplCreationScriptOptions -NoDefaults
        }

        It "Returns empty CreationScriptOptions when -NoDefaults specified" {
            $result.ToString() | Should -BeExactly '0'
        }
    }

    Context "Output with -Options" {
        BeforeAll {
            $result = New-DbaReplCreationScriptOptions -Options NonClusteredIndexes, Statistics
        }

        It "Includes specified options along with defaults" {
            $result | Should -Match 'NonClusteredIndexes'
            $result | Should -Match 'Statistics'
            $result | Should -Match 'PrimaryObject'
        }
    }

    Context "Output with -Options and -NoDefaults" {
        BeforeAll {
            $result = New-DbaReplCreationScriptOptions -Options ClusteredIndexes, Identity -NoDefaults
        }

        It "Includes only specified options when -NoDefaults specified" {
            $result | Should -Match 'ClusteredIndexes'
            $result | Should -Match 'Identity'
            $result | Should -Not -Match 'CustomProcedures'
        }
    }
}
<#
    Integration tests for replication are in GitHub Actions and run from \tests\gh-actions-repl-*.ps1.ps1
#>