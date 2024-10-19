param($ModuleName = 'dbatools')

Describe "Find-DbaInstance" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Find-DbaInstance
        }
        It "Should have ComputerName as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter ComputerName
        }
        It "Should have DiscoveryType as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter DiscoveryType
        }
        It "Should have Credential as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Credential
        }
        It "Should have SqlCredential as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have ScanType as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter ScanType
        }
        It "Should have IpAddress as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter IpAddress
        }
        It "Should have DomainController as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter DomainController
        }
        It "Should have TCPPort as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter TCPPort
        }
        It "Should have MinimumConfidence as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter MinimumConfidence
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }

    Context "Command finds SQL Server instances" {
        BeforeDiscovery {
            . (Join-Path $PSScriptRoot 'constants.ps1')
        }
        BeforeAll {
            $results = Find-DbaInstance -ComputerName $global:instance3 -ScanType Browser, SqlConnect | Select-Object -First 1
        }
        It "Returns an object type of [Dataplat.Dbatools.Discovery.DbaInstanceReport]" {
            $results | Should -BeOfType [Dataplat.Dbatools.Discovery.DbaInstanceReport]
        }
        It "FullName is populated" {
            $results.FullName | Should -Not -BeNullOrEmpty
        }
        It "TcpConnected is true" -Skip:([Dataplat.Dbatools.Parameter.DbaInstanceParameter]$global:instance3).IsLocalHost {
            $results.TcpConnected | Should -Be $true
        }
        It "successfully connects" {
            $results.SqlConnected | Should -Be $true
        }
    }
}
