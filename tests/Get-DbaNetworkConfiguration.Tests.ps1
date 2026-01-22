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
            $resultsFull = Get-DbaNetworkConfiguration -SqlInstance $TestConfig.InstanceSingle
            $resultsTcpIpProperties = Get-DbaNetworkConfiguration -SqlInstance $TestConfig.InstanceSingle -OutputType TcpIpProperties
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

    Context "Output Validation - Full" {
        BeforeAll {
            $result = Get-DbaNetworkConfiguration -SqlInstance $TestConfig.InstanceSingle -OutputType Full -EnableException
        }

        It "Returns PSCustomObject" {
            $result.PSObject.TypeNames | Should -Contain "System.Management.Automation.PSCustomObject"
        }

        It "Has the expected default properties for Full output" {
            $expectedProps = @(
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
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in Full output"
            }
        }
    }

    Context "Output Validation - ServerProtocols" {
        BeforeAll {
            $result = Get-DbaNetworkConfiguration -SqlInstance $TestConfig.InstanceSingle -OutputType ServerProtocols -EnableException
        }

        It "Returns PSCustomObject" {
            $result.PSObject.TypeNames | Should -Contain "System.Management.Automation.PSCustomObject"
        }

        It "Has the expected properties for ServerProtocols output" {
            $expectedProps = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "SharedMemoryEnabled",
                "NamedPipesEnabled",
                "TcpIpEnabled"
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in ServerProtocols output"
            }
        }
    }

    Context "Output Validation - TcpIpProperties" {
        BeforeAll {
            $result = Get-DbaNetworkConfiguration -SqlInstance $TestConfig.InstanceSingle -OutputType TcpIpProperties -EnableException
        }

        It "Returns PSCustomObject" {
            $result.PSObject.TypeNames | Should -Contain "System.Management.Automation.PSCustomObject"
        }

        It "Has the expected properties for TcpIpProperties output" {
            $expectedProps = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Enabled",
                "KeepAlive",
                "ListenAll"
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in TcpIpProperties output"
            }
        }
    }

    Context "Output Validation - TcpIpAddresses" {
        BeforeAll {
            $result = Get-DbaNetworkConfiguration -SqlInstance $TestConfig.InstanceSingle -OutputType TcpIpAddresses -EnableException
        }

        It "Returns PSCustomObject" {
            $result.PSObject.TypeNames | Should -Contain "System.Management.Automation.PSCustomObject"
        }

        It "Has the expected core properties for TcpIpAddresses output" {
            $expectedProps = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Name",
                "TcpDynamicPorts",
                "TcpPort"
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in TcpIpAddresses output"
            }
        }
    }

    Context "Output Validation - Certificate" {
        BeforeAll {
            $result = Get-DbaNetworkConfiguration -SqlInstance $TestConfig.InstanceSingle -OutputType Certificate -EnableException
        }

        It "Returns PSCustomObject" {
            $result.PSObject.TypeNames | Should -Contain "System.Management.Automation.PSCustomObject"
        }

        It "Has the expected core properties for Certificate output" {
            $expectedProps = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "ServiceAccount",
                "ForceEncryption",
                "FriendlyName",
                "DnsNameList",
                "Thumbprint",
                "Generated",
                "Expires",
                "IssuedTo",
                "IssuedBy",
                "Certificate"
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in Certificate output"
            }
        }
    }
}