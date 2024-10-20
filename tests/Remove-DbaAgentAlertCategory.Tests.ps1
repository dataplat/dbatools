$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Category', 'InputObject', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "New Agent Alert Category is changed properly" {

        It "Should have the right name" {
            $results = New-DbaAgentAlertCategory -SqlInstance $TestConfig.instance2 -Category CategoryTest1, CategoryTest2, CategoryTest3
            $results[0].Name | Should Be "CategoryTest1"
            $results[1].Name | Should Be "CategoryTest2"
            $results[2].Name | Should Be "CategoryTest3"
        }

        It "Should actually for sure exist" {
            $newresults = Get-DbaAgentAlertCategory -SqlInstance $TestConfig.instance2 -Category CategoryTest1, CategoryTest2, CategoryTest3
            $newresults.Count | Should Be 3
        }

        It "Remove the alert categories" {
            Remove-DbaAgentAlertCategory -SqlInstance $TestConfig.instance2 -Category CategoryTest1, CategoryTest2, Categorytest3 -Confirm:$false

            $newresults = Get-DbaAgentAlertCategory -SqlInstance $TestConfig.instance2 -Category CategoryTest1, CategoryTest2, CategoryTest3

            $newresults.Count | Should Be 0
        }

        It "supports piping SQL Agent alert category" {
            $categoryName = "dbatoolsci_test_$(get-random)"
            $null = New-DbaAgentAlertCategory -SqlInstance $TestConfig.instance2 -Category $categoryName
            (Get-DbaAgentAlertCategory -SqlInstance $TestConfig.instance2 -Category $categoryName ) | Should -Not -BeNullOrEmpty
            Get-DbaAgentAlertCategory -SqlInstance $TestConfig.instance2 -Category $categoryName | Remove-DbaAgentAlertCategory -Confirm:$false
            (Get-DbaAgentAlertCategory -SqlInstance $TestConfig.instance2 -Category $categoryName ) | Should -BeNullOrEmpty
        }
    }
}
