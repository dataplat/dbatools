#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaStartupParameter",
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
                "Simple",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Command actually works" {
        It "Gets Results" {
            $results = Get-DbaStartupParameter -SqlInstance $TestConfig.instance2
            $results | Should -Not -BeNullOrEmpty
        }
        It "Simple parameter returns only essential properties" {
            $results = Get-DbaStartupParameter -SqlInstance $TestConfig.instance2 -Simple
            $results | Should -Not -BeNullOrEmpty
            $properties = $results | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name
            $expectedProperties = @("ComputerName", "InstanceName", "SqlInstance", "MasterData", "MasterLog", "ErrorLog", "TraceFlags", "DebugFlags", "ParameterString")
            $properties | Should -Be $expectedProperties
        }
        It "Without Simple parameter returns additional properties" {
            $results = Get-DbaStartupParameter -SqlInstance $TestConfig.instance2
            $results | Should -Not -BeNullOrEmpty
            $properties = $results | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name
            $properties | Should -Contain "CommandPromptStart"
            $properties | Should -Contain "MinimalStart"
            $properties | Should -Contain "MemoryToReserve"
        }
    }
}