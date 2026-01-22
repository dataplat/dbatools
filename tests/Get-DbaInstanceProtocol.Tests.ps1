#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaInstanceProtocol",
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
    Context "Command actually works" {
        BeforeAll {
            $allResults = Get-DbaInstanceProtocol -ComputerName $TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2
            $tcpResults = $allResults | Where-Object Name -eq "Tcp"
        }

        It "shows some services" {
            $allResults.DisplayName | Should -Not -BeNullOrEmpty
        }

        It "can get TCPIP" {
            foreach ($result in $tcpResults) {
                $result.Name -eq "Tcp" | Should -Be $true
            }
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $result = Get-DbaInstanceProtocol -ComputerName $TestConfig.InstanceMulti1 -EnableException
        }

        It "Returns WMI ServerNetworkProtocol objects" {
            $result | Should -Not -BeNullOrEmpty
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                'ComputerName',
                'InstanceName',
                'DisplayName',
                'Name',
                'MultiIP',
                'IsEnabled'
            )
            $actualProps = $result[0].PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }

        It "Has Enable() script method" {
            $result[0].Enable | Should -Not -BeNullOrEmpty
            $result[0].Enable.GetType().Name | Should -Be 'PSScriptMethod'
        }

        It "Has Disable() script method" {
            $result[0].Disable | Should -Not -BeNullOrEmpty
            $result[0].Disable.GetType().Name | Should -Be 'PSScriptMethod'
        }
    }
}