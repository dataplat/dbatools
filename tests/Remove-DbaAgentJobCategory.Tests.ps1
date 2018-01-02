$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "New Agent Job Category is changed properly" {

        It "Should have the right name and category type" {
            $results = New-DbaAgentJobCategory -SqlInstance $script:instance2 -Category CategoryTest1, CategoryTest2, CategoryTest3
            $results[0].Name | Should Be "CategoryTest1"
            $results[0].CategoryType | Should Be "LocalJob"
            $results[1].Name | Should Be "CategoryTest2"
            $results[1].CategoryType | Should Be "LocalJob"
            $results[2].Name | Should Be "CategoryTest3"
            $results[2].CategoryType | Should Be "LocalJob"
        }

        It "Should actually for sure exist" {
            $newresults = Get-DbaAgentJobCategory -SqlInstance $script:instance2 -Category CategoryTest1, CategoryTest2, CategoryTest3
            $newresults.Count | Should Be 3
        }

        It "Remove the job categories" {
            Remove-DbaAgentJobCategory -SqlInstance $script:instance2 -Category CategoryTest1, CategoryTest2, Categorytest3

            $newresults = Get-DbaAgentJobCategory -SqlInstance $script:instance2 -Category CategoryTest1, CategoryTest2, CategoryTest3

            $newresults.Count | Should Be 0
        }
    }
}