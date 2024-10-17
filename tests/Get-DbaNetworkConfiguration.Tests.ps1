param($ModuleName = 'dbatools')

Describe "Get-DbaNetworkConfiguration" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaNetworkConfiguration
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have Credential as a parameter" {
            $CommandUnderTest | Should -HaveParameter Credential -Type PSCredential
        }
        It "Should have OutputType as a parameter" {
            $CommandUnderTest | Should -HaveParameter OutputType -Type String
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch
        }
    }

    Context "Command actually works" {
        BeforeDiscovery {
            . (Join-Path $PSScriptRoot 'constants.ps1')
        }
        BeforeAll {
            $resultsFull = Get-DbaNetworkConfiguration -SqlInstance $env:instance2
            $resultsTcpIpProperties = Get-DbaNetworkConfiguration -SqlInstance $env:instance2 -OutputType TcpIpProperties
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
