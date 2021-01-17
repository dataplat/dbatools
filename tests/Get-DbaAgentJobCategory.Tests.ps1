$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {

        [array]$knownParameters = 'SqlInstance', 'SqlCredential', 'Category', 'CategoryType', 'Force', 'EnableException'
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    Context "Command gets job categories" {
        BeforeAll {
            $null = New-DbaAgentJobCategory -SqlInstance $script:instance2 -Category dbatoolsci_testcategory, dbatoolsci_testcategory2
        }
        AfterAll {
            $null = Remove-DbaAgentJobCategory -SqlInstance $script:instance2 -Category dbatoolsci_testcategory, dbatoolsci_testcategory2
        }
        $results = Get-DbaAgentJobCategory -SqlInstance $script:instance2 | Where-Object { $_.Name -match "dbatoolsci" }
        It "Should get at least 2 categories" {
            $results.count | Should BeGreaterThan 1
        }
        $results = Get-DbaAgentJobCategory -SqlInstance $script:instance2 -Category dbatoolsci_testcategory | Where-Object { $_.Name -match "dbatoolsci" }
        It "Should get the dbatoolsci_testcategory category" {
            $results.count | Should Be 1
        }
        $results = Get-DbaAgentJobCategory -SqlInstance $script:instance2 -CategoryType LocalJob | Where-Object { $_.Name -match "dbatoolsci" }
        It "Should get at least 1 LocalJob" {
            $results.count | Should BeGreaterThan 1
        }
    }
}