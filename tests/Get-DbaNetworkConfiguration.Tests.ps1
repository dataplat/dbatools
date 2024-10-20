param($ModuleName = 'dbatools')

Describe "Get-DbaNetworkConfiguration" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaNetworkConfiguration
        }

        $params = @(
            "SqlInstance",
            "Credential",
            "OutputType",
            "EnableException"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }

    Context "Command actually works" {
        BeforeDiscovery {
            . (Join-Path $PSScriptRoot 'constants.ps1')
        }
        BeforeAll {
            $resultsFull = Get-DbaNetworkConfiguration -SqlInstance $global:instance2
            $resultsTcpIpProperties = Get-DbaNetworkConfiguration -SqlInstance $global:instance2 -OutputType TcpIpProperties
        }

        It "Should Return a Result" {
            $resultsFull | Should -Not -BeNullOrEmpty
            $resultsTcpIpProperties | Should -Not -BeNullOrEmpty
        }

        It "has the correct properties for full output" {
            $ExpectedPropsFull = 'ComputerName', 'InstanceName', 'SqlInstance', 'SharedMemoryEnabled', 'NamedPipesEnabled', 'TcpIpEnabled', 'TcpIpProperties', 'TcpIpAddresses', 'Certificate', 'Advanced'
            $resultsFull.PSObject.Properties.Name | Sort-Object | Should -Be ($ExpectedPropsFull | Sort-Object)
        }

        It "has the correct properties for TcpIpProperties output" {
            $ExpectedPropsTcpIpProperties = 'ComputerName', 'InstanceName', 'SqlInstance', 'Enabled', 'KeepAlive', 'ListenAll'
            $resultsTcpIpProperties.PSObject.Properties.Name | Sort-Object | Should -Be ($ExpectedPropsTcpIpProperties | Sort-Object)
        }
    }
}
