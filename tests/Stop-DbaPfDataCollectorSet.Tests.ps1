#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Stop-DbaPfDataCollectorSet",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "ComputerName",
                "Credential",
                "CollectorSet",
                "InputObject",
                "NoWait",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Command execution and functionality" {
        AfterAll {
            $script:set | Stop-DbaPfDataCollectorSet -WarningAction SilentlyContinue
        }

        It "Should return a result with the right computername and name is not null" {
            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove('*-Dba*:EnableException')
            $script:set = Get-DbaPfDataCollectorSet | Select-Object -First 1
            $script:set | Start-DbaPfDataCollectorSet -WarningAction SilentlyContinue
            Start-Sleep 2

            $results = $script:set | Select-Object -First 1 | Stop-DbaPfDataCollectorSet -WarningAction SilentlyContinue -WarningVariable warn
            if (-not $warn) {
                $results.ComputerName | Should -Be $env:COMPUTERNAME
                $results.Name | Should -Not -Be $null
            }
        }
    }
}