param($ModuleName = 'dbatools')

Describe "Find-DbaInstance" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Find-DbaInstance
        }
        It "Should have ComputerName as a non-mandatory parameter of type DbaInstanceParameter[]" {
            $CommandUnderTest | Should -HaveParameter ComputerName -Type DbaInstanceParameter[] -Not -Mandatory
        }
        It "Should have DiscoveryType as a non-mandatory parameter of type DbaInstanceDiscoveryType" {
            $CommandUnderTest | Should -HaveParameter DiscoveryType -Type DbaInstanceDiscoveryType -Not -Mandatory
        }
        It "Should have Credential as a non-mandatory parameter of type PSCredential" {
            $CommandUnderTest | Should -HaveParameter Credential -Type PSCredential -Not -Mandatory
        }
        It "Should have SqlCredential as a non-mandatory parameter of type PSCredential" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Not -Mandatory
        }
        It "Should have ScanType as a non-mandatory parameter of type DbaInstanceScanType[]" {
            $CommandUnderTest | Should -HaveParameter ScanType -Type DbaInstanceScanType[] -Not -Mandatory
        }
        It "Should have IpAddress as a non-mandatory parameter of type String[]" {
            $CommandUnderTest | Should -HaveParameter IpAddress -Type String[] -Not -Mandatory
        }
        It "Should have DomainController as a non-mandatory parameter of type String" {
            $CommandUnderTest | Should -HaveParameter DomainController -Type String -Not -Mandatory
        }
        It "Should have TCPPort as a non-mandatory parameter of type Int32[]" {
            $CommandUnderTest | Should -HaveParameter TCPPort -Type Int32[] -Not -Mandatory
        }
        It "Should have MinimumConfidence as a non-mandatory parameter of type DbaInstanceConfidenceLevel" {
            $CommandUnderTest | Should -HaveParameter MinimumConfidence -Type DbaInstanceConfidenceLevel -Not -Mandatory
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Not -Mandatory
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
        It "TcpConnected is true" -Skip:([DbaInstanceParameter]$global:instance3).IsLocalHost {
            $results.TcpConnected | Should -Be $true
        }
        It "successfully connects" {
            $results.SqlConnected | Should -Be $true
        }
    }
}
