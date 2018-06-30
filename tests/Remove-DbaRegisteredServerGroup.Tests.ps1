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
    }
}