#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Start-DbaPfDataCollectorSet",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        BeforeAll {
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
        }

        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $global:testSet = Get-DbaPfDataCollectorSet | Select-Object -First 1
        $global:testSet | Stop-DbaPfDataCollectorSet -WarningAction SilentlyContinue
        Start-Sleep 2
    }
    
    AfterAll {
        $global:testSet | Stop-DbaPfDataCollectorSet -WarningAction SilentlyContinue
    }
    
    Context "Verifying command works" {
        It "returns a result with the right computername and name is not null" {
            $results = $global:testSet | Select-Object -First 1 | Start-DbaPfDataCollectorSet -WarningAction SilentlyContinue -WarningVariable warn
            if (-not $warn) {
                $results.ComputerName | Should -Be $env:COMPUTERNAME
                $results.Name | Should -Not -BeNullOrEmpty
            }
        }
    }
}
