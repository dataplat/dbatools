$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {

    Context "Command actually works" {
        $results = Get-DbaServerProtocol -ComputerName $script:instance1, $script:instance2

        It "shows some services" {
            $results.DisplayName | Should Not Be $null
        }

        $results = $results | Where-Object Name -eq Tcp
        It "can get TCPIP" {
            foreach ($result in $results) {
                $result.Name -eq "Tcp" | Should Be $true
            }
        }
    }
}