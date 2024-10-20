param($ModuleName = 'dbatools')

Describe "Remove-DbaAgentJobCategory" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Remove-DbaAgentJobCategory
        }

        $params = @(
            "SqlInstance",
            "SqlCredential",
            "Category",
            "CategoryType",
            "InputObject",
            "EnableException",
            "WhatIf",
            "Confirm"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }
}

Describe "Remove-DbaAgentJobCategory Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "New Agent Job Category is changed properly" {
        BeforeAll {
            $results = New-DbaAgentJobCategory -SqlInstance $global:instance2 -Category CategoryTest1, CategoryTest2, CategoryTest3
        }

        It "Should have the right name and category type" {
            $results[0].Name | Should -Be "CategoryTest1"
            $results[0].CategoryType | Should -Be "LocalJob"
            $results[1].Name | Should -Be "CategoryTest2"
            $results[1].CategoryType | Should -Be "LocalJob"
            $results[2].Name | Should -Be "CategoryTest3"
            $results[2].CategoryType | Should -Be "LocalJob"
        }

        It "Should actually for sure exist" {
            $newresults = Get-DbaAgentJobCategory -SqlInstance $global:instance2 -Category CategoryTest1, CategoryTest2, CategoryTest3
            $newresults.Count | Should -Be 3
        }

        It "Remove the job categories" {
            Remove-DbaAgentJobCategory -SqlInstance $global:instance2 -Category CategoryTest1, CategoryTest2, CategoryTest3 -Confirm:$false

            $newresults = Get-DbaAgentJobCategory -SqlInstance $global:instance2 -Category CategoryTest1, CategoryTest2, CategoryTest3

            $newresults.Count | Should -Be 0
        }

        AfterAll {
            # Cleanup any remaining test categories
            Remove-DbaAgentJobCategory -SqlInstance $global:instance2 -Category CategoryTest1, CategoryTest2, CategoryTest3 -Confirm:$false -ErrorAction SilentlyContinue
        }
    }
}
