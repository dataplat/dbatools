#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Disable-DbaAgHadr",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "Credential",
                "Force",
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

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Re-enable HADR for future tests
        $null = Enable-DbaAgHadr -SqlInstance $TestConfig.InstanceHadr -Force
        # The Agent test stops the Agent, so make sure it is running again whatever happened in between. Collected first,
        # because Start-DbaService with nothing piped in falls back to the local machine.
        $stoppedAgent = Get-DbaService -SqlInstance $TestConfig.InstanceHadr -Type Agent | Where-Object State -ne "Running"
        if ($stoppedAgent) {
            $null = $stoppedAgent | Start-DbaService
        }

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When disabling HADR" {
        It "Successfully disables HADR and keeps a running Agent running" {
            # The forced restart starts the Agent again only if it was running before, so a running Agent must
            # come back running. Collected first, because Start-DbaService with nothing piped in falls back to
            # the local machine.
            $stoppedAgent = Get-DbaService -SqlInstance $TestConfig.InstanceHadr -Type Agent | Where-Object State -ne "Running"
            if ($stoppedAgent) {
                $null = $stoppedAgent | Start-DbaService
            }
            (Get-DbaService -SqlInstance $TestConfig.InstanceHadr -Type Agent).State | Should -Be "Running"
            $disableResults = Disable-DbaAgHadr -SqlInstance $TestConfig.InstanceHadr -Force
            $disableResults.IsHadrEnabled | Should -BeFalse
            (Get-DbaService -SqlInstance $TestConfig.InstanceHadr -Type Agent).State | Should -Be "Running"
        }

        It "Leaves a stopped Agent stopped when -Force restarts the engine" {
            # The forced restart used to start the Agent with the engine whether it had been running before or not.
            $null = Get-DbaService -SqlInstance $TestConfig.InstanceHadr -Type Agent | Stop-DbaService
            $disableResults = Disable-DbaAgHadr -SqlInstance $TestConfig.InstanceHadr -Force
            $disableResults.IsHadrEnabled | Should -BeFalse
            (Get-DbaService -SqlInstance $TestConfig.InstanceHadr -Type Agent).State | Should -Be "Stopped"
            $null = Get-DbaService -SqlInstance $TestConfig.InstanceHadr -Type Agent | Start-DbaService
        }
    }
}