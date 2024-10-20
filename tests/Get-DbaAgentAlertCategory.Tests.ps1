param($ModuleName = 'dbatools')

Describe "Get-DbaAgentAlertCategory" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaAgentAlertCategory
        }
        $params = @(
            "SqlInstance",
            "SqlCredential",
            "Category",
            "EnableException"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }

    Context "Command gets alert categories" {
        BeforeAll {
            . "$PSScriptRoot\constants.ps1"
            $null = New-DbaAgentAlertCategory -SqlInstance $global:instance2 -Category dbatoolsci_testcategory, dbatoolsci_testcategory2
        }
        AfterAll {
            $null = Remove-DbaAgentAlertCategory -SqlInstance $global:instance2 -Category dbatoolsci_testcategory, dbatoolsci_testcategory2 -Confirm:$false
        }
        It "Should get at least 2 categories" {
            $results = Get-DbaAgentAlertCategory -SqlInstance $global:instance2 | Where-Object {$_.Name -match "dbatoolsci"}
            $results.count | Should -BeGreaterThan 1
        }
        It "Should get the dbatoolsci_testcategory category" {
            $results = Get-DbaAgentAlertCategory -SqlInstance $global:instance2 -Category dbatoolsci_testcategory | Where-Object {$_.Name -match "dbatoolsci"}
            $results.count | Should -Be 1
        }
    }
}
