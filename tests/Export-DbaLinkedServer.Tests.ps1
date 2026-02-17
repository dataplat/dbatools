#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Export-DbaLinkedServer",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "LinkedServer",
                "SqlCredential",
                "Credential",
                "Path",
                "FilePath",
                "ExcludePassword",
                "Append",
                "Passthru",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
Describe $CommandName -Tag IntegrationTests {
    Context "When exporting linked servers" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $results = Export-DbaLinkedServer -SqlInstance $TestConfig.InstanceSingle -ExcludePassword -Passthru -OutVariable "global:dbatoolsciOutput"
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Should return T-SQL script content" {
            if (-not $results) {
                Set-ItResult -Skipped -Because "no linked servers found on test instance"
                return
            }
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should contain sp_addlinkedserver calls" {
            if (-not $results) {
                Set-ItResult -Skipped -Because "no linked servers found on test instance"
                return
            }
            "$results" | Should -Match "sp_addlinkedserver"
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

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "System\.String|System\.IO\.FileInfo"
        }
    }
}