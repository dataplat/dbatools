#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaDbMirrorMonitor",
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

        $db = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database msdb
        if (($db.Tables["dbm_monitor_data"].Name)) {
            $putback = $true
        } else {
            $null = Add-DbaDbMirrorMonitor -SqlInstance $TestConfig.InstanceSingle -WarningAction SilentlyContinue
        }

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        if ($putback) {
            # add it back
            $results = Add-DbaDbMirrorMonitor -SqlInstance $TestConfig.InstanceSingle -WarningAction SilentlyContinue
        }

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    It "removes the mirror monitor" {
        $results = Remove-DbaDbMirrorMonitor -SqlInstance $TestConfig.InstanceSingle -WarningAction SilentlyContinue
        if (-not $results) {
            Set-ItResult -Skipped -Because "mirror monitor could not be removed in this environment"
        }
        $results.MonitorStatus | Should -Be "Removed"
        $script:outputValidationResult = $results
    }

    Context "Output validation" {
        It "Returns output of the correct type" {
            if (-not $script:outputValidationResult) { Set-ItResult -Skipped -Because "no result to validate" }
            $script:outputValidationResult[0] | Should -BeOfType PSCustomObject
        }

        It "Returns output with the expected properties" {
            if (-not $script:outputValidationResult) { Set-ItResult -Skipped -Because "no result to validate" }
            $script:outputValidationResult[0].ComputerName | Should -Not -BeNullOrEmpty
            $script:outputValidationResult[0].InstanceName | Should -Not -BeNullOrEmpty
            $script:outputValidationResult[0].SqlInstance | Should -Not -BeNullOrEmpty
            $script:outputValidationResult[0].MonitorStatus | Should -Be "Removed"
        }
    }
}