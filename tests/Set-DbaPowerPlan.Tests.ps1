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

    Context "Command actually works" {
        It "Should return result for the server" {
            $results = Set-DbaPowerPlan -ComputerName $env:COMPUTERNAME -OutVariable "global:dbatoolsciOutput"
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

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return a PSCustomObject" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [PSCustomObject]
        }

        It "Should have the expected properties" {
            $expectedProperties = @(
                "ComputerName",
                "PreviousInstanceId",
                "PreviousPowerPlan",
                "ActiveInstanceId",
                "ActivePowerPlan",
                "IsChanged"
            )
            $actualProperties = $global:dbatoolsciOutput[0].PSObject.Properties.Name
            Compare-Object -ReferenceObject $expectedProperties -DifferenceObject $actualProperties | Should -BeNullOrEmpty
        }

        It "Should have the correct default display columns" {
            $expectedColumns = @(
                "ComputerName",
                "PreviousPowerPlan",
                "ActivePowerPlan",
                "IsChanged"
            )
            $defaultColumns = $global:dbatoolsciOutput[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            Compare-Object -ReferenceObject $expectedColumns -DifferenceObject $defaultColumns | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "PSCustomObject"
        }
    }
}