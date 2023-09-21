param(
    [string[]]
    $TestServer
)

$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        BeforeAll {
            [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
            [object[]]$knownParameters = 'ComputerName', 'DiscoveryType', 'Credential', 'SqlCredential', 'ScanType', 'IpAddress', 'DomainController', 'TCPPort', 'MinimumConfidence', 'EnableException'
            $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        }
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {
    Context "Command finds SQL Server instances" {
        BeforeAll {
            if ($env:APPVEYOR) {
                $results = Find-DbaInstance -ComputerName $script:instance3 -ScanType Browser, SqlConnect | Select-Object -First 1
            } else {
                $results = Find-DbaInstance -ComputerName $TestServer -ScanType Browser, SqlConnect | Select-Object -First 1
            }
        }
        It "Returns an object type of [Dataplat.Dbatools.Discovery.DbaInstanceReport]" {
            $results | Should -BeOfType [Dataplat.Dbatools.Discovery.DbaInstanceReport]
        }
        It "FullName is populated" {
            $results.FullName | Should -Not -BeNullOrEmpty
        }
        It "TcpConnected is true" {
            $results.TcpConnected | Should -Be $true
        }
        It "successfully connects" {
            $results.SqlConnected | Should -Be $true
        }
    }
}
