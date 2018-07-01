$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {
    Context "Setup" {
        BeforeAll {
            $srvName = "dbatoolsci-server1"
            $regSrvName = "dbatoolsci-server12"
            $regSrvDesc = "dbatoolsci-server123"
            $newServer = Add-DbaRegisteredServer -SqlInstance $script:instance1 -ServerName $srvName -Name $regSrvName -Description $regSrvDesc
            
            $srvName2 = "dbatoolsci-server2"
            $regSrvName2 = "dbatoolsci-server21"
            $regSrvDesc2 = "dbatoolsci-server321"
            $newServer2 = Add-DbaRegisteredServer -SqlInstance $script:instance1 -ServerName $srvName2 -Name $regSrvName2 -Description $regSrvDesc2
        }
        AfterAll {
            Get-DbaRegisteredServer -SqlInstance $script:instance1, $script:instance2 | Where-Object Name -match dbatoolsci | Remove-DbaRegisteredServer -Confirm:$false
        }
        It "supports dropping via the pipeline" {
            $results = $newServer | Remove-DbaRegisteredServer -Confirm:$false
            $results.Name | Should -Be $regSrvName
            $results.Status | Should -Be 'Dropped'
        }
        
        It "supports dropping manually" {
            $results = Remove-DbaRegisteredServer -Confirm:$false -SqlInstance $script:instance1 -Name $regSrvName2
            $results.Name | Should -Be $regSrvName2
            $results.Status | Should -Be 'Dropped'
        }
    }
}