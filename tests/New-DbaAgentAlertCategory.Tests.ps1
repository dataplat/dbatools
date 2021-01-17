$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {

        [array]$knownParameters = 'SqlInstance', 'SqlCredential', 'Category', 'Force', 'EnableException'
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "New Agent Alert Category is added properly" {

        It "Should have the right name and category type" {
            $results = New-DbaAgentAlertCategory -SqlInstance $script:instance2 -Category CategoryTest1
            $results.Name | Should Be "CategoryTest1"
        }

        It "Should have the right name and category type" {
            $results = New-DbaAgentAlertCategory -SqlInstance $script:instance2 -Category CategoryTest2
            $results.Name | Should Be "CategoryTest2"
        }

        It "Should actually for sure exist" {
            $newresults = Get-DbaAgentAlertCategory -SqlInstance $script:instance2 -Category CategoryTest1, CategoryTest2
            $newresults[0].Name | Should Be "CategoryTest1"
            $newresults[1].Name | Should Be "CategoryTest2"
        }

        It "Should not write over existing job categories" {
            $results = New-DbaAgentAlertCategory -SqlInstance $script:instance2 -Category CategoryTest1 -WarningAction SilentlyContinue -WarningVariable warn
            $warn -match "already exists" | Should Be $true
        }

        # Cleanup and ignore all output
        $null = Remove-DbaAgentAlertCategory -SqlInstance $script:instance2 -Category CategoryTest1, CategoryTest2
    }
}