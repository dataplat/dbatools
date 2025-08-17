#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Start-DbaPfDataCollectorSet",
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
    # [Start-DbaPfDataCollectorSet] Server Manager Performance Monitor on APPVYR-WIN is disabled..
    Context -Skip:($env:appveyor) "Verifying command works" {
        BeforeAll {
            $set = Get-DbaPfDataCollectorSet | Select-Object -First 1
            $set | Stop-DbaPfDataCollectorSet -WarningAction SilentlyContinue
            Start-Sleep 2
        }

        AfterAll {
            $set | Stop-DbaPfDataCollectorSet -WarningAction SilentlyContinue
        }

        It "returns a result with the right computername and name is not null" {
            $results = $set | Start-DbaPfDataCollectorSet
            $WarnVar | Should -BeNullOrEmpty
            $results.ComputerName | Should -Be $env:COMPUTERNAME
            $results.Name | Should -Not -BeNullOrEmpty
        }
    }
}