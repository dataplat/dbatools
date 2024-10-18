param($ModuleName = 'dbatools')

Describe "Find-DbaInstance" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Find-DbaInstance
        }
        It "Should have ComputerName as a non-mandatory parameter of type Dataplat.Dbatools.Parameter.DbaInstanceParameter[]" {
            $CommandUnderTest | Should -HaveParameter ComputerName -Type Dataplat.Dbatools.Parameter.DbaInstanceParameter[] -Mandatory:$false
        }
        It "Should have DiscoveryType as a non-mandatory parameter of type Dataplat.Dbatools.Discovery.DbaInstanceDiscoveryType" {
            $CommandUnderTest | Should -HaveParameter DiscoveryType -Type Dataplat.Dbatools.Discovery.DbaInstanceDiscoveryType -Mandatory:$false
        }
        It "Should have Credential as a non-mandatory parameter of type Microsoft.SqlServer.Management.Smo.PSCredential" {
            $CommandUnderTest | Should -HaveParameter Credential -Type Microsoft.SqlServer.Management.Smo.PSCredential -Mandatory:$false
        }
        It "Should have SqlCredential as a non-mandatory parameter of type Microsoft.SqlServer.Management.Smo.PSCredential" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type Microsoft.SqlServer.Management.Smo.PSCredential -Mandatory:$false
        }
        It "Should have ScanType as a non-mandatory parameter of type Dataplat.Dbatools.Discovery.DbaInstanceScanType[]" {
            $CommandUnderTest | Should -HaveParameter ScanType -Type Dataplat.Dbatools.Discovery.DbaInstanceScanType[] -Mandatory:$false
        }
        It "Should have IpAddress as a non-mandatory parameter of type System.String[]" {
            $CommandUnderTest | Should -HaveParameter IpAddress -Type System.String[] -Mandatory:$false
        }
        It "Should have DomainController as a non-mandatory parameter of type System.String" {
            $CommandUnderTest | Should -HaveParameter DomainController -Type System.String -Mandatory:$false
        }
        It "Should have TCPPort as a non-mandatory parameter of type System.Int32[]" {
            $CommandUnderTest | Should -HaveParameter TCPPort -Type System.Int32[] -Mandatory:$false
        }
        It "Should have MinimumConfidence as a non-mandatory parameter of type Dataplat.Dbatools.Discovery.DbaInstanceConfidenceLevel" {
            $CommandUnderTest | Should -HaveParameter MinimumConfidence -Type Dataplat.Dbatools.Discovery.DbaInstanceConfidenceLevel -Mandatory:$false
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter -Mandatory:$false
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
