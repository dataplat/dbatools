#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Export-DbaExecutionPlan",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "ExcludeDatabase",
                "Path",
                "SinceCreation",
                "SinceLastExecution",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>

Describe $CommandName -Tag IntegrationTests {
    Context "When Path is not a directory" {
        BeforeAll {
            $notADirectory = Join-Path -Path $TestConfig.Temp -ChildPath "dbatoolsci_notadirectory_$(Get-Random).txt"
            Set-Content -Path $notADirectory -Value "dbatoolsci"
        }

        AfterAll {
            Remove-Item -Path $notADirectory -Force -ErrorAction SilentlyContinue
        }

        It "Warns and exports nothing" {
            # The check used to read Test-Bound -ParamterName, a misspelled parameter that Test-Bound quietly ignored,
            # so a file passed as -Path was never rejected and the plans were exported into a path under that file
            # instead (#10655).
            $splatExport = @{
                SqlInstance   = $TestConfig.InstanceSingle
                Path          = $notADirectory
                WarningAction = "SilentlyContinue"
            }
            $results = Export-DbaExecutionPlan @splatExport
            $results | Should -BeNullOrEmpty
            ($WarnVar -join " ") | Should -BeLike "*must be a directory*"
        }
    }
}
