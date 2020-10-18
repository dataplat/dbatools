$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Category', 'Force', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "New Agent Alert Category is changed properly" {

        It "Should have the right name" {
            $results = New-DbaAgentAlertCategory -SqlInstance $script:instance2 -Category CategoryTest1, CategoryTest2, CategoryTest3
            $results[0].Name | Should Be "CategoryTest1"
            $results[1].Name | Should Be "CategoryTest2"
            $results[2].Name | Should Be "CategoryTest3"
        }

        It "Should actually for sure exist" {
            $newresults = Get-DbaAgentAlertCategory -SqlInstance $script:instance2 -Category CategoryTest1, CategoryTest2, CategoryTest3
            $newresults.Count | Should Be 3
        }

        It "Remove the alert categories" {
            Remove-DbaAgentAlertCategory -SqlInstance $script:instance2 -Category CategoryTest1, CategoryTest2, Categorytest3

            $newresults = Get-DbaAgentAlertCategory -SqlInstance $script:instance2 -Category CategoryTest1, CategoryTest2, CategoryTest3

            $newresults.Count | Should Be 0
        }
    }
}