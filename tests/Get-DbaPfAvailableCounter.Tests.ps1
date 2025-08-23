#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaPfAvailableCounter",
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
                "Pattern",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $null = Get-DbaPfDataCollectorSetTemplate -Template "Long Running Queries" | Import-DbaPfDataCollectorSetTemplate
    }

    AfterAll {
        $null = Get-DbaPfDataCollectorSet -CollectorSet "Long Running Queries" | Remove-DbaPfDataCollectorSet
    }

    Context "Verifying command returns all the required results" {
        It "returns the correct values" {
            $results = Get-DbaPfAvailableCounter
            $results.Count -gt 1000 | Should -Be $true
        }

        It "returns are pipable into Add-DbaPfDataCollectorCounter" {
            $results = Get-DbaPfAvailableCounter -Pattern "*sql*" | Select-Object -First 3 | Add-DbaPfDataCollectorCounter -CollectorSet "Long Running Queries" -Collector "DataCollector01" -WarningAction SilentlyContinue
            foreach ($result in $results) {
                $result.Name -match "sql" | Should -Be $true
            }
        }
    }
}