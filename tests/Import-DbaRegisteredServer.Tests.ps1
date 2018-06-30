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
            Get-DbaRegisteredServer -SqlInstance $script:instance1, $script:instance2 -Name $regSrvName, $regSrvName2, $regSrvName3 | Remove-DbaRegisteredServer -Confirm:$false
            Get-DbaRegisteredServerGroup -SqlInstance $script:instance1, $script:instance2 -Group $group, $group2 | Remove-DbaRegisteredServerGroup -Confirm:$false
        }
        
        It "imports group objects" {
            $results = $newServer.Parent | Import-DbaRegisteredServer -SqlInstance $script:instance2
            $results.Description | Should -Be $regSrvDesc
            $results.ServerName | Should -Be $srvName
            $results.Parent.Name | Should -Be $group
        }
        
        It "imports registered server objects" {
            $results2 = $newServer2 | Import-DbaRegisteredServer -SqlInstance $script:instance2
            $results2.ServerName | Should -Be $newServer2.ServerName
            $results2.Parent.Name | Should -Be $newServer2.Parent.Name
        }
        
        It "imports a file from Export-DbaRegisteredServer" {
            $results3 = $newServer3 | Export-DbaRegisteredServer -Path C:\temp\dbatoolsci_regserverexport.xml
            $results4 = Import-DbaRegisteredServer -SqlInstance $script:instance2 -Path $results3
            $results4.ServerName | Should -Be $newServer3.ServerName
            $results4.Description | Should -Be $newServer3.Description
        }
    }
}