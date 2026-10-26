#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Invoke-DbaXEReplay",
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
                "Event",
                "InputObject",
                "Raw",
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
Describe $CommandName -Tag IntegrationTests -Skip:(-not (Get-Command -Name sqlcmd -ErrorAction Ignore)) {
    Context "When replaying into a database context" {
        It "Runs the batch in the requested database" {
            # -Database was declared and documented but never handed to sqlcmd, so every replay ran in the default
            # database of the login (#10607).
            $batch = [PSCustomObject]@{
                Name       = "sql_batch_completed"
                batch_text = "SELECT DB_NAME() AS dbatoolsci_replay_db"
            }
            $results = $batch | Invoke-DbaXEReplay -SqlInstance $TestConfig.InstanceSingle -Database tempdb
            ($results -join " ") | Should -BeLike "*tempdb*"
        }
    }
}
