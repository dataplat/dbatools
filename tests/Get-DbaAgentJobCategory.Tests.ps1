$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Category', 'CategoryType', 'Force', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
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
        $results = Get-DbaAgentJobCategory -SqlInstance $script:instance2 | Where-Object {$_.Name -match "dbatoolsci"}
        It "Should get at least 2 categories" {
            $results.count | Should BeGreaterThan 1
        }
        $results = Get-DbaAgentJobCategory -SqlInstance $script:instance2 -Category dbatoolsci_testcategory | Where-Object {$_.Name -match "dbatoolsci"}
        It "Should get the dbatoolsci_testcategory category" {
            $results.count | Should Be 1
        }
        $results = Get-DbaAgentJobCategory -SqlInstance $script:instance2 -CategoryType LocalJob | Where-Object {$_.Name -match "dbatoolsci"}
        It "Should get at least 1 LocalJob" {
            $results.count | Should BeGreaterThan 1
        }
    }
}