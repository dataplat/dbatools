param($ModuleName = 'dbatools')

Describe "Find-DbaInstance" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Find-DbaInstance
        }
        It "has all the required parameters" {
            $requiredParameters = @(
                "ComputerName",
                "DiscoveryType",
                "Credential",
                "SqlCredential",
                "ScanType",
                "IpAddress",
                "DomainController",
                "TCPPort",
                "MinimumConfidence",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
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
