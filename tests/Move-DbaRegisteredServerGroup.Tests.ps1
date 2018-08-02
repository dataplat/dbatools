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
            
            $group2 = "dbatoolsci-group1a"
            $newGroup2 = Add-DbaRegisteredServerGroup -SqlInstance $script:instance1 -Name $group2
            
            $group3 = "dbatoolsci-group1b"
            $newGroup3 = Add-DbaRegisteredServerGroup -SqlInstance $script:instance1 -Name $group3
          }
        AfterAll {
            Get-DbaRegisteredServer -SqlInstance $script:instance1 -Name $regSrvName  | Remove-DbaRegisteredServer -Confirm:$false
            Get-DbaRegisteredServerGroup -SqlInstance $script:instance1 -Group $group, $group2, $group3 | Remove-DbaRegisteredServerGroup -Confirm:$false
        }
        
        It "moves a piped group" {
            $results = $newGroup2, $newGroup3 | Move-DbaRegisteredServerGroup -NewGroup $newGroup.Name
            $results.Parent.Name | Should -Be $newGroup.Name, $newGroup.Name
        }
        
        It "moves a manually specified group" {
            $results = Move-DbaRegisteredServerGroup -SqlInstance $script:instance1 -Group "$group\$group3" -NewGroup Default
            $results.Parent.Name | Should -Be 'DatabaseEngineServerGroup'
        }
    }
}