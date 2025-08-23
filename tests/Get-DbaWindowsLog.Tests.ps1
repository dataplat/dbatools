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

Describe $CommandName -Tag IntegrationTests {
    # TODO: Command is very unstable and should be reviewed, so we skip the tests.
    Context -Skip "Command returns proper info" {
        It "returns results" {
            $results = Get-DbaWindowsLog -SqlInstance $TestConfig.instance2
            $results | Should -Not -BeNullOrEmpty
        }
    }
}