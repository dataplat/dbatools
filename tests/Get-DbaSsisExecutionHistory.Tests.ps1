#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaSsisExecutionHistory",
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
                "Since",
                "Status",
                "Project",
                "Folder",
                "Environment",
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
    # Characterization tests (2026-07-06, Track A): a minimal project-deployment fixture was
    # deployed to the live SSISDB on InstanceSsis (folder dbatoolsci_charfolder, project
    # dbatoolsci_charproject, package dbatoolsci_charpackage.dtsx) and executed once to
    # Succeeded with LOGGING_LEVEL 1. These pin the observed output shape of the current
    # implementation ahead of the C# port. SSISDB catalog operations require Integrated
    # Authentication, so the fixture is lab state (rebuilt by Initialize-MigrationLab), not
    # BeforeAll setup.
    BeforeAll {
        $allHistory = @(Get-DbaSsisExecutionHistory -SqlInstance $TestConfig.InstanceSsis)
        $charExecution = $allHistory | Where-Object FolderName -eq "dbatoolsci_charfolder" | Select-Object -First 1
    }

    Context "When reading execution history from the live catalog" {
        It "Returns the fixture execution" {
            $allHistory.Count | Should -BeGreaterOrEqual 1
            $charExecution | Should -Not -BeNullOrEmpty
        }

        It "Emits the characterized property shape" {
            $charExecution.ExecutionID | Should -BeOfType [long]
            $charExecution.ProjectName | Should -Be "dbatoolsci_charproject"
            $charExecution.PackageName | Should -Be "dbatoolsci_charpackage.dtsx"
            $charExecution.Environment | Should -Be ""
            $charExecution.StatusCode | Should -Be "Succeeded"
            $charExecution.StartTime | Should -BeOfType [Dataplat.Dbatools.Utility.DbaDateTime]
            $charExecution.EndTime | Should -BeOfType [Dataplat.Dbatools.Utility.DbaDateTime]
            $charExecution.ElapsedMinutes | Should -BeOfType [int]
            $charExecution.LoggingLevel | Should -Be 1
        }
    }

    Context "When filtering execution history" {
        It "Matches on folder, project and status together" {
            $splatFilter = @{
                SqlInstance = $TestConfig.InstanceSsis
                Folder      = "dbatoolsci_charfolder"
                Project     = "dbatoolsci_charproject"
                Status      = "Succeeded"
            }
            @(Get-DbaSsisExecutionHistory @splatFilter).Count | Should -BeGreaterOrEqual 1
        }

        It "Excludes non-matching status and future Since values" {
            $failedOnly = @(Get-DbaSsisExecutionHistory -SqlInstance $TestConfig.InstanceSsis -Status Failed | Where-Object FolderName -eq "dbatoolsci_charfolder")
            $failedOnly.Count | Should -Be 0
            $futureOnly = @(Get-DbaSsisExecutionHistory -SqlInstance $TestConfig.InstanceSsis -Since (Get-Date).AddDays(1))
            $futureOnly.Count | Should -Be 0
        }
    }
}