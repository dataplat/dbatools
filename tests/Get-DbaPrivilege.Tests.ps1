#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaPrivilege",
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
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Gets Instance Privilege" {
        BeforeAll {
            $results = Get-DbaPrivilege -ComputerName $env:ComputerName -WarningVariable warn 3> $null
        }

        It "Gets results" {
            $results | Should -Not -BeNullOrEmpty
        }
        It "Should not warn" {
            $warn | Should -BeNullOrEmpty
        }
    }

    Context "Output validation" {
        BeforeAll {
            $result = @(Get-DbaPrivilege -ComputerName $env:ComputerName 3> $null)
        }

        It "Returns output" {
            $result | Should -Not -BeNullOrEmpty
        }

        It "Has the expected properties" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $expectedProps = @("ComputerName", "User", "LogonAsBatch", "InstantFileInitialization", "LockPagesInMemory", "GenerateSecurityAudit", "LogonAsAService")
            foreach ($prop in $expectedProps) {
                $result[0].PSObject.Properties.Name | Should -Contain $prop -Because "property '$prop' should exist on the output object"
            }
        }

        It "ComputerName property is populated" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $result[0].ComputerName | Should -Not -BeNullOrEmpty
        }
    }
}