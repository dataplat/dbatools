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
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true


            foreach ($set in Get-DbaPfDataCollectorSet) {
                write-warning -Message "DbaPfDataCollectorSet: $($set.Name) is $($set.State)"
            }
            $set = Get-DbaPfDataCollectorSet | Where-Object State -eq 'Running' | Select-Object -First 1
            $set | Start-DbaPfDataCollectorSet -WarningAction SilentlyContinue
            Start-Sleep 2

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $set | Stop-DbaPfDataCollectorSet -WarningAction SilentlyContinue
        }

        It "Should return a result with the right computername and name is not null" {
            $results = $set | Stop-DbaPfDataCollectorSet -WarningAction SilentlyContinue
            if (-not $WarnVar) {
                $results.ComputerName | Should -Be $env:COMPUTERNAME
                $results.Name | Should -Not -BeNullOrEmpty
            }
        }
    }
}