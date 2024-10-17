param($ModuleName = 'dbatools')

Describe "Remove-DbaAgentAlertCategory" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Remove-DbaAgentAlertCategory
        }
        It "Should have SqlInstance as a non-mandatory parameter of type DbaInstanceParameter[]" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Not -Mandatory
        }
        It "Should have SqlCredential as a non-mandatory parameter of type PSCredential" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Not -Mandatory
        }
        It "Should have Category as a non-mandatory parameter of type String[]" {
            $CommandUnderTest | Should -HaveParameter Category -Type String[] -Not -Mandatory
        }
        It "Should have InputObject as a non-mandatory parameter of type AlertCategory[]" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type AlertCategory[] -Not -Mandatory
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Not -Mandatory
        }
    }

    Context "Integration Tests" {
        BeforeAll {
            . "$PSScriptRoot\constants.ps1"
        }

        It "Should remove newly created Agent Alert Categories" {
            $results = New-DbaAgentAlertCategory -SqlInstance $global:instance2 -Category CategoryTest1, CategoryTest2, CategoryTest3
            $results.Count | Should -Be 3
            $results[0].Name | Should -Be "CategoryTest1"
            $results[1].Name | Should -Be "CategoryTest2"
            $results[2].Name | Should -Be "CategoryTest3"

            $newResults = Get-DbaAgentAlertCategory -SqlInstance $global:instance2 -Category CategoryTest1, CategoryTest2, CategoryTest3
            $newResults.Count | Should -Be 3

            Remove-DbaAgentAlertCategory -SqlInstance $global:instance2 -Category CategoryTest1, CategoryTest2, CategoryTest3 -Confirm:$false

            $finalResults = Get-DbaAgentAlertCategory -SqlInstance $global:instance2 -Category CategoryTest1, CategoryTest2, CategoryTest3
            $finalResults.Count | Should -Be 0
        }

        It "Should support piping SQL Agent alert category" {
            $categoryName = "dbatoolsci_test_$(Get-Random)"
            $null = New-DbaAgentAlertCategory -SqlInstance $global:instance2 -Category $categoryName
            $category = Get-DbaAgentAlertCategory -SqlInstance $global:instance2 -Category $categoryName
            $category | Should -Not -BeNullOrEmpty

            $category | Remove-DbaAgentAlertCategory -Confirm:$false

            $removedCategory = Get-DbaAgentAlertCategory -SqlInstance $global:instance2 -Category $categoryName
            $removedCategory | Should -BeNullOrEmpty
        }
    }
}
