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
Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # The command reads only .Name and .statement/.batch_text off each piped record, so a shaped
        # PSCustomObject stands in for a captured XEvent - no live Extended Events session or .xel file
        # is needed to exercise the replay path end to end.
        $batchEvent = [PSCustomObject]@{
            Name       = "sql_batch_completed"
            batch_text = "SELECT 1"
        }
        $statementEvent = [PSCustomObject]@{
            Name      = "sql_batch_completed"
            statement = "SELECT 1"
        }

        # sqlcmd is an external dependency of this command (begin refuses without it). Record its presence
        # so the assertions below state the real reason if it is missing, rather than failing obscurely.
        $sqlcmdPresent = $null -ne (Get-Command sqlcmd -ErrorAction Ignore)

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When replaying a captured batch" {
        It "Requires sqlcmd to be installed" {
            # Characterizes the begin-block dependency: without sqlcmd the command warns and produces
            # nothing, which is why the replay assertions below are conditioned on it.
            $sqlcmdPresent | Should -BeTrue -Because "Invoke-DbaXEReplay shells out to sqlcmd; the gate host needs the SQL Server Command Line Utilities"
        }

        It "Replays a batch_text event and returns trimmed output lines" -Skip:(-not $sqlcmdPresent) {
            $results = $batchEvent | Invoke-DbaXEReplay -SqlInstance $TestConfig.InstanceSingle -WarningAction SilentlyContinue
            # Non-raw output is the sqlcmd text with each line trimmed and the dashes separator dropped.
            $results | Should -Not -BeNullOrEmpty
            ($results | Where-Object { $PSItem -match "^-{20,}$" }) | Should -BeNullOrEmpty
        }

        It "Replays a statement event the same way" -Skip:(-not $sqlcmdPresent) {
            # The command prefers .statement when present and falls back to .batch_text; both reach sqlcmd.
            $results = $statementEvent | Invoke-DbaXEReplay -SqlInstance $TestConfig.InstanceSingle -WarningAction SilentlyContinue
            $results | Should -Not -BeNullOrEmpty
        }

        It "Returns unfiltered sqlcmd output with -Raw" -Skip:(-not $sqlcmdPresent) {
            # -Raw returns sqlcmd's own lines verbatim, so the separator the default path strips survives.
            $results = $batchEvent | Invoke-DbaXEReplay -SqlInstance $TestConfig.InstanceSingle -Raw -WarningAction SilentlyContinue
            $results | Should -Not -BeNullOrEmpty
        }
    }
}