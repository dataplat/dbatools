param($ModuleName = 'dbatools')

Describe "Get-DbaAgentJobCategory" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaAgentJobCategory
        }
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "SqlCredential",
                "Category",
                "CategoryType",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
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
