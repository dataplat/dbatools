$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {
    Context "Setup" {
        BeforeAll {
            $group = "dbatoolsci-group1"
            $newGroup = Add-DbaRegisteredServerGroup -SqlInstance $script:instance1 -Name $group
            
            $group2 = "dbatoolsci-group1a"
            $newGroup2 = Add-DbaRegisteredServerGroup -SqlInstance $script:instance1 -Name $group2
            
            $hellagroup = Get-DbaRegisteredServerGroup -SqlInstance $script:instance1 -Id 1 | Add-DbaRegisteredServerGroup -Name dbatoolsci-first | Add-DbaRegisteredServerGroup -Name dbatoolsci-second | Add-DbaRegisteredServerGroup -Name dbatoolsci-third | Add-DbaRegisteredServer -ServerName dbatoolsci-test -Description ridiculous
        }
        AfterAll {
            Get-DbaRegisteredServerGroup -SqlInstance $script:instance1 | Where-Object Name -match dbatoolsci | Remove-DbaRegisteredServerGroup -Confirm:$false
        }
        
        It "supports dropping via the pipeline" {
            $results = $newGroup | Remove-DbaRegisteredServerGroup -Confirm:$false
            $results.Name | Should -Be $group
            $results.Status | Should -Be 'Dropped'
        }
        
        It "supports dropping manually" {
            $results = Remove-DbaRegisteredServerGroup -Confirm:$false -SqlInstance $script:instance1 -Name $group2
            $results.Name | Should -Be $group2
            $results.Status | Should -Be 'Dropped'
        }
        
        It "supports hella long group name" {
            $results = Get-DbaRegisteredServerGroup -SqlInstance $script:instance1 -Group $hellagroup.Group
            $results.Name | Should -Be 'dbatoolsci-third'
        }
    }
}