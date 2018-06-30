$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {
    Context "Setup" {
        BeforeAll {
            $group = "dbatoolsci-group1"
            $group2 = "dbatoolsci-group2"
            $description = "group description"
        }
        AfterAll {
            Remove-DbaRegisteredServerGroup -SqlInstance $script:instance1 -Group $group, $group2 -Confirm:$false
        }

        It "adds a registered server group" {
            $results1 = Add-DbaRegisteredServerGroup -SqlInstance $script:instance1 -Name $group
            $results1.Name | Should -Be $group
            $results1.SqlInstance | Should -Be $script:instance1
        }
        It "adds a registered server group with extended properties" {
            $results2 = Add-DbaRegisteredServerGroup -SqlInstance $script:instance1 -Name $group2 -Description $description
            $results2.Name | Should -Be $group2
            $results2.Description | Should -Be $description
            $results2.SqlInstance | Should -Be $script:instance1
        }
    }
}