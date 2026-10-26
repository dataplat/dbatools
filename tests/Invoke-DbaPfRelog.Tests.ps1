#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Invoke-DbaPfRelog",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Path",
                "Destination",
                "Type",
                "Append",
                "AllowClobber",
                "PerformanceCounter",
                "PerformanceCounterPath",
                "Interval",
                "BeginTime",
                "EndTime",
                "ConfigPath",
                "Summary",
                "InputObject",
                "Multithread",
                "AllTime",
                "Raw",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
Describe $CommandName -Tag IntegrationTests {
    Context "When no matching blg files exist" {
        It "Warns without eating an iteration of the caller's loop" {
            # The no-files guard used to run Stop-Function -Continue in the end block, where no loop
            # encloses it - the continue escaped the command before its own return statement ran and
            # consumed an iteration of this very loop, so the counter fell short (#10638).
            $loopCount = 0
            foreach ($i in 1..3) {
                $null = Invoke-DbaPfRelog -Path "$env:TEMP\dbatoolsci-does-not-exist.txt" -WarningAction SilentlyContinue
                $loopCount++
            }
            $loopCount | Should -Be 3
            $WarnVar | Should -BeLike "*Could not find matching*"
        }
    }
}