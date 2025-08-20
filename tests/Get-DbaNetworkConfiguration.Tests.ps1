#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaNetworkConfiguration",
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
                "OutputType",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Command actually works" {
        BeforeAll {
            $resultsFull = Get-DbaNetworkConfiguration -SqlInstance $TestConfig.instance2
            $resultsTcpIpProperties = Get-DbaNetworkConfiguration -SqlInstance $TestConfig.instance2 -OutputType TcpIpProperties
        }

        It "Should Return a Result" {
            $resultsFull | Should -Not -Be $null
            $resultsTcpIpProperties | Should -Not -Be $null
        }

        It "has the correct properties" {
            $expectedPropsFull = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "SharedMemoryEnabled",
                "NamedPipesEnabled",
                "TcpIpEnabled",
                "TcpIpProperties",
                "TcpIpAddresses",
                "Certificate",
                "Advanced"
            )
            ($resultsFull.PsObject.Properties.Name | Sort-Object) | Should -BeExactly ($expectedPropsFull | Sort-Object)

            $expectedPropsTcpIpProperties = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Enabled",
                "KeepAlive",
                "ListenAll"
            )
            ($resultsTcpIpProperties.PsObject.Properties.Name | Sort-Object) | Should -BeExactly ($expectedPropsTcpIpProperties | Sort-Object)
        }
    }
}