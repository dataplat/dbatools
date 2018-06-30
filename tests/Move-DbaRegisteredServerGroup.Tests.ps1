$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {
    Context "Setup" {
        BeforeAll {
            $srvName = "dbatoolsci-server1"
            $group = "dbatoolsci-group1"
            $regSrvName = "dbatoolsci-server12"
            $regSrvDesc = "dbatoolsci-server123"
            
            $newGroup = Add-DbaRegisteredServerGroup -SqlInstance $script:instance1 -Name $group
            $newServer = Add-DbaRegisteredServer -SqlInstance $script:instance1 -ServerName $srvName -Name $regSrvName -Description $regSrvDesc -Group $newGroup.Name
            
            $srvName2 = "dbatoolsci-server2"
            $group2 = "dbatoolsci-group1a"
            $regSrvName2 = "dbatoolsci-server21"
            $regSrvDesc2 = "dbatoolsci-server321"
            
            $newGroup2 = Add-DbaRegisteredServerGroup -SqlInstance $script:instance1 -Name $group2
            $newServer2 = Add-DbaRegisteredServer -SqlInstance $script:instance1 -ServerName $srvName2 -Name $regSrvName2 -Description $regSrvDesc2
            
            $regSrvName3 = "dbatoolsci-server3"
            $srvName3 = "dbatoolsci-server3"
            $regSrvDesc3 = "dbatoolsci-server3desc"
            
            $newServer3 = Add-DbaRegisteredServer -SqlInstance $script:instance1 -ServerName $srvName3 -Name $regSrvName3 -Description $regSrvDesc3
        }
        AfterAll {
            Get-DbaRegisteredServer -SqlInstance $script:instance1 -Name $regSrvName, $regSrvName2, $regSrvName3 | Remove-DbaRegisteredServer -Confirm:$false
            Get-DbaRegisteredServerGroup -SqlInstance $script:instance1 -Group $group, $group2 | Remove-DbaRegisteredServerGroup -Confirm:$false
        }
        
        It -Skip "moves a piped group" {
            $results = $newGroup2 | Move-DbaRegisteredServerGroup -NewGroup $newGroup.Name
            $results.Parent.Name | Should -Be $newGroup.Name
            $results.Name | Should -Be $regSrvName2
        }
        
        It -Skip "moves a manually specified group" {
            $results = Move-DbaRegisteredServerGroup -SqlInstance $script:instance1 -ServerName $srvName3 -NewGroup $newGroup2.Name
            $results.Parent.Name | Should -Be $newGroup2.Name
            $results.Description | Should -Be $regSrvDesc3
        }
    }
}