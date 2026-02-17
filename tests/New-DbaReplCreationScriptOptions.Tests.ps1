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
}
<#
    Integration tests for replication are in GitHub Actions and run from \tests\gh-actions-repl-*.ps1.ps1
#>

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # Check if the replication assembly is available - skip all tests if not
        try {
            $null = [Microsoft.SqlServer.Replication.CreationScriptOptions]
            $global:skipRepl = $false
        } catch {
            $global:skipRepl = $true
        }

        if (-not $global:skipRepl) {
            $result = New-DbaReplCreationScriptOptions -OutVariable "global:dbatoolsciOutput"
        }
    }

    Context "When creating default script options" -Skip:$global:skipRepl {
        It "Should return a CreationScriptOptions object" {
            $result | Should -Not -BeNullOrEmpty
        }

        It "Should include default options" {
            $resultString = $result.ToString()
            $resultString | Should -Match "PrimaryObject"
            $resultString | Should -Match "ClusteredIndexes"
            $resultString | Should -Match "DriPrimaryKey"
        }
    }

    Context "Output validation" -Skip:$global:skipRepl {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return the correct type" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [Microsoft.SqlServer.Replication.CreationScriptOptions]
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "Microsoft\.SqlServer\.Replication\.CreationScriptOptions"
        }
    }
}