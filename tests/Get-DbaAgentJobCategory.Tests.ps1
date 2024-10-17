param($ModuleName = 'dbatools')

Describe "Get-DbaAgentJobCategory" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaAgentJobCategory
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have Category as a parameter" {
            $CommandUnderTest | Should -HaveParameter Category -Type String[]
        }
        It "Should have CategoryType as a parameter" {
            $CommandUnderTest | Should -HaveParameter CategoryType -Type String
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch
        }
    }

    Context "Command gets job categories" {
        BeforeAll {
            . "$PSScriptRoot\constants.ps1"
            $null = New-DbaAgentJobCategory -SqlInstance $global:instance2 -Category dbatoolsci_testcategory, dbatoolsci_testcategory2
        }
        AfterAll {
            $null = Remove-DbaAgentJobCategory -SqlInstance $global:instance2 -Category dbatoolsci_testcategory, dbatoolsci_testcategory2 -Confirm:$false
        }
        It "Should get at least 2 categories" {
            $results = Get-DbaAgentJobCategory -SqlInstance $global:instance2 | Where-Object {$_.Name -match "dbatoolsci"}
            $results.count | Should -BeGreaterThan 1
        }
        It "Should get the dbatoolsci_testcategory category" {
            $results = Get-DbaAgentJobCategory -SqlInstance $global:instance2 -Category dbatoolsci_testcategory | Where-Object {$_.Name -match "dbatoolsci"}
            $results.count | Should -Be 1
        }
        It "Should get at least 1 LocalJob" {
            $results = Get-DbaAgentJobCategory -SqlInstance $global:instance2 -CategoryType LocalJob | Where-Object {$_.Name -match "dbatoolsci"}
            $results.count | Should -BeGreaterThan 1
        }
    }
}
