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
            $results = Get-DbaStartupParameter -SqlInstance $TestConfig.InstanceSingle -OutVariable "global:dbatoolsciOutput"
            $results | Should -Not -BeNullOrEmpty
        }
        It "Simple parameter returns only essential properties" {
            $results = Get-DbaStartupParameter -SqlInstance $TestConfig.InstanceSingle -Simple
            $results | Should -Not -BeNullOrEmpty
            $properties = ($results | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name) | Sort-Object
            $expectedProperties = @("ComputerName", "InstanceName", "SqlInstance", "MasterData", "MasterLog", "ErrorLog", "TraceFlags", "DebugFlags", "ParameterString") | Sort-Object
            Compare-Object -ReferenceObject $expectedProperties -DifferenceObject $properties | Should -BeNullOrEmpty
        }
        It "Without Simple parameter returns additional properties" {
            $results = Get-DbaStartupParameter -SqlInstance $TestConfig.InstanceSingle
            $results | Should -Not -BeNullOrEmpty
            $properties = $results | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name
            $properties | Should -Contain "CommandPromptStart"
            $properties | Should -Contain "MinimalStart"
            $properties | Should -Contain "MemoryToReserve"
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
                "InstanceName",
                "SqlInstance",
                "MasterData",
                "MasterLog",
                "ErrorLog",
                "TraceFlags",
                "DebugFlags",
                "CommandPromptStart",
                "MinimalStart",
                "MemoryToReserve",
                "SingleUser",
                "SingleUserName",
                "NoLoggingToWinEvents",
                "StartAsNamedInstance",
                "DisableMonitoring",
                "IncreasedExtents",
                "ParameterString"
            )
            $actualProperties = $global:dbatoolsciOutput[0].PSObject.Properties.Name
            Compare-Object -ReferenceObject $expectedProperties -DifferenceObject $actualProperties | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "PSCustomObject"
        }
    }
}