#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Set-DbaPowerPlan",
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
                "PowerPlan",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>
Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # Set initial power plan to Balanced for consistent test state
        $null = Set-DbaPowerPlan -ComputerName $env:COMPUTERNAME -CustomPowerPlan "Balanced"
    }

    AfterAll {
        # Reset to original power plan after tests
        $null = Set-DbaPowerPlan -ComputerName $env:COMPUTERNAME -CustomPowerPlan "Balanced" -ErrorAction SilentlyContinue
    }

    Context "Output Validation" {
        BeforeAll {
            $result = Set-DbaPowerPlan -ComputerName $env:COMPUTERNAME -EnableException
        }

        It "Returns PSCustomObject" {
            $result.PSObject.TypeNames | Should -Contain "System.Management.Automation.PSCustomObject"
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                "ComputerName",
                "PreviousPowerPlan",
                "ActivePowerPlan",
                "IsChanged"
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }

        It "Has the additional properties available via Select-Object" {
            $additionalProps = @(
                "PreviousInstanceId",
                "ActiveInstanceId"
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $additionalProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be available"
            }
        }
    }

    Context "Command actually works" {
        It "Should return result for the server" {
            $results = Set-DbaPowerPlan -ComputerName $env:COMPUTERNAME
            $results | Should -Not -BeNullOrEmpty
            $results.ActivePowerPlan | Should -Be "High Performance"
            $results.IsChanged | Should -Be $true
        }

        It "Should skip if already set" {
            $results = Set-DbaPowerPlan -ComputerName $env:COMPUTERNAME
            $results.ActivePowerPlan | Should -Be "High Performance"
            $results.IsChanged | Should -Be $false
            $results.ActivePowerPlan -eq $results.PreviousPowerPlan | Should -Be $true
        }

        It "Should return result for the server when setting defined PowerPlan" {
            $results = Set-DbaPowerPlan -ComputerName $env:COMPUTERNAME -PowerPlan Balanced
            $results | Should -Not -BeNullOrEmpty
            $results.ActivePowerPlan | Should -Be "Balanced"
            $results.IsChanged | Should -Be $true
        }

        It "Should accept Piped input for ComputerName" {
            $results = $env:COMPUTERNAME | Set-DbaPowerPlan
            $results | Should -Not -BeNullOrEmpty
            $results.ActivePowerPlan | Should -Be "High Performance"
            $results.IsChanged | Should -Be $true
        }

        It "Should return result for the server when using the alias CustomPowerPlan" {
            $results = Set-DbaPowerPlan -ComputerName $env:COMPUTERNAME -CustomPowerPlan Balanced
            $results | Should -Not -BeNullOrEmpty
            $results.ActivePowerPlan | Should -Be "Balanced"
            $results.IsChanged | Should -Be $true
        }
    }
}