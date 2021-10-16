$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys
        [object[]]$knownParameters = 'ComputerName', 'Credential', 'PowerPlan', 'EnableException'

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $null = Set-DbaPowerPlan -ComputerName $env:COMPUTERNAME -CustomPowerPlan 'Balanced'
    }
    Context "Command actually works" {
        It "Should return result for the server" {
            $results = Set-DbaPowerPlan -ComputerName $env:COMPUTERNAME
            $results | Should Not Be Null
            $results.ActivePowerPlan | Should Be 'High Performance'
            $results.IsChanged | Should Be $true
        }
        It "Should skip if already set" {
            $results = Set-DbaPowerPlan -ComputerName $env:COMPUTERNAME
            $results.ActivePowerPlan | Should Be 'High Performance'
            $results.IsChanged | Should Be $false
            $results.ActivePowerPlan -eq $results.PreviousPowerPlan | Should Be $true
        }
        It "Should return result for the server when setting defined PowerPlan" {
            $results = Set-DbaPowerPlan -ComputerName $env:COMPUTERNAME -PowerPlan Balanced
            $results | Should Not Be Null
            $results.ActivePowerPlan | Should Be 'Balanced'
            $results.IsChanged | Should Be $true
        }
        It "Should accept Piped input for ComputerName" {
            $results = $env:COMPUTERNAME | Set-DbaPowerPlan
            $results | Should Not Be Null
            $results.ActivePowerPlan | Should Be 'High Performance'
            $results.IsChanged | Should Be $true
        }
        It "Should return result for the server when using the alias CustomPowerPlan" {
            $results = Set-DbaPowerPlan -ComputerName $env:COMPUTERNAME -CustomPowerPlan Balanced
            $results | Should Not Be Null
            $results.ActivePowerPlan | Should Be 'Balanced'
            $results.IsChanged | Should Be $true
        }
    }
}