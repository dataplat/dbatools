#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbatoolsLog",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "FunctionName",
                "ModuleName",
                "Target",
                "Tag",
                "Last",
                "Skip",
                "Runspace",
                "Level",
                "Raw",
                "Errors",
                "LastError",
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
    # Characterization tests (W1-016): pure in-memory LogHost compute - dbatools commands
    # write log entries as a side effect, so a config read guarantees fresh entries.
    BeforeAll {
        $null = Get-DbatoolsConfigValue -FullName sql.connection.timeout
        try { $null = Get-DbatoolsConfigValue -FullName no.such.log.key -NotNull 3>$null } catch { }
    }

    Context "Log retrieval" {
        It "returns log entries with the projected shape" {
            $results = @(Get-DbatoolsLog)
            $results.Count | Should -BeGreaterThan 0
            $expectedProps = @(
                "CallStack", "ComputerName", "File", "FunctionName", "Level", "Line",
                "Message", "ModuleName", "Runspace", "Tags", "TargetObject", "Timestamp",
                "Type", "Username"
            )
            ($results[0].PSObject.Properties.Name -join ",") | Should -Be ($expectedProps -join ",")
        }

        It "filters by FunctionName" {
            $results = @(Get-DbatoolsLog -FunctionName Get-DbatoolsConfigValue)
            $results.Count | Should -BeGreaterThan 0
            $results.FunctionName | Select-Object -Unique | Should -Be "Get-DbatoolsConfigValue"
        }

        It "returns raw LogEntry objects under -Raw" {
            $results = @(Get-DbatoolsLog -Raw)
            $results.Count | Should -BeGreaterThan 0
            $results[0] | Should -BeOfType [Dataplat.Dbatools.Message.LogEntry]
        }

        It "returns error entries under -Errors after a forced failure" {
            $results = @(Get-DbatoolsLog -Errors)
            $results.Count | Should -BeGreaterThan 0
        }
    }
}