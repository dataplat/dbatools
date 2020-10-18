$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'Pattern', 'Tag', 'Author', 'MinimumVersion', 'MaximumVersion', 'Rebuild', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    Context "Command finds jobs using all parameters" {
        $results = Find-DbaCommand -Pattern "snapshot"
        It "Should find more than 5 snapshot commands" {
            $results.Count | Should BeGreaterThan 5
        }
        $results = Find-DbaCommand -Tag Job
        It "Should find more than 20 commands tagged as job" {
            $results.Count | Should BeGreaterThan 20
        }
        $results = Find-DbaCommand -Tag Job, Owner
        It "Should find a command that has both Job and Owner tags" {
            $results.CommandName | Should Contain "Test-DbaAgentJobOwner"
        }
        $results = Find-DbaCommand -Author chrissy
        It "Should find more than 250 commands authored by Chrissy" {
            $results.Count | Should BeGreaterThan 250
        }
        $results = Find-DbaCommand -Author chrissy -Tag AG
        It "Should find more than 15 commands for AGs authored by Chrissy" {
            $results.Count | Should BeGreaterThan 15
        }
        $results = Find-DbaCommand -Pattern snapshot -Rebuild
        It "Should find more than 5 snapshot commands after Rebuilding the index" {
            $results.Count | Should BeGreaterThan 5
        }
    }
}