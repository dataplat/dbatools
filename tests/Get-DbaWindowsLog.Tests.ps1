#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaWindowsLog",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "Start",
                "End",
                "Credential",
                "MaxThreads",
                "MaxRemoteThreads",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests -Skip:([bool]$env:APPVEYOR) {
    # These were skipped as "very unstable and should be reviewed". Reviewed on 2026-08-01: five
    # consecutive runs against the lab were all green, so they run again. If the instability comes
    # back, skip them once more but record what actually failed, not only that it is unstable.
    # AppVeyor is where they still fail: the command finds the error log through a SQL Server
    # startup event in the Windows Application log, and the CI runners have nothing to parse.

    Context "Command returns proper info" {
        It "returns results" {
            $results = Get-DbaWindowsLog -SqlInstance $TestConfig.InstanceSingle
            $results | Should -Not -BeNullOrEmpty
        }
    }
}