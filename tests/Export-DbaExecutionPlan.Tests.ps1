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

    Context "When Path is omitted and the configured export directory does not exist" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $exportPathBefore = Get-DbatoolsConfigValue -FullName "Path.DbatoolsExport"
            $missingExportPath = Join-Path -Path $TestConfig.Temp -ChildPath "dbatoolsci_export_$(Get-Random)"
            Set-DbatoolsConfig -FullName "Path.DbatoolsExport" -Value $missingExportPath
            # A cached plan in tempdb to export: the plan of an ad hoc statement carries the database it was compiled
            # in, and the second run makes sure a full plan is cached even with optimize for ad hoc workloads on.
            foreach ($i in 1..2) {
                $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database tempdb -Query "SELECT 1 AS dbatoolsci_plan_probe"
            }

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            Set-DbatoolsConfig -FullName "Path.DbatoolsExport" -Value $exportPathBefore
            Remove-Item -Path $missingExportPath -Recurse -Force -ErrorAction SilentlyContinue

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Creates the directory and exports into it" {
            # Test-Bound does not see a default, so the bootstrap never ran for an omitted -Path and the plans were
            # saved into a directory that did not exist.
            $results = Export-DbaExecutionPlan -SqlInstance $TestConfig.InstanceSingle -Database tempdb -ExcludeEmptyQueryPlan -WarningAction SilentlyContinue
            Test-Path -Path $missingExportPath -PathType Container | Should -BeTrue
            ($results | Measure-Object).Count | Should -BeGreaterThan 0
            $results.OutputFile | Should -BeLike "$missingExportPath\*"
            Get-ChildItem -Path $missingExportPath -Filter "*.sqlplan" | Should -Not -BeNullOrEmpty
        }
    }
}
