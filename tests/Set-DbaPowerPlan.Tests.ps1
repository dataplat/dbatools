$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        $knownParameters = 'ComputerName', 'Credential', 'PowerPlan', 'CustomPowerPlan', 'EnableException', 'InputObject'
        $paramCount = $knownParameters.Count
        $defaultParamCount = 13
        $command = Get-Command -Name $CommandName
        [object[]]$params = $command.Parameters.Keys
        It "Should contain our specific parameters" {
            ( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count ) | Should Be $paramCount
        }
        It "Should only contain $paramCount parameters" {
            $params.Count - $defaultParamCount | Should Be $paramCount
        }
    }
}

<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/sqlcollaborative/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>
Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "Command actually works" {
        It "Should return result for the server" {
            $results = Set-DbaPowerPlan -ComputerName $env:COMPUTERNAME
            $results | Should Not Be Null
            $results.ActivePowerPlan -eq 'High Performance' | Should Be $true
        }
        It "Should skip if already set" {
            $results = Set-DbaPowerPlan -ComputerName $env:COMPUTERNAME
            $results.ActivePowerPlan -eq 'High Performance' | Should Be $true
            $results.ActivePowerPlan -eq $results.PreviousPowerPlan | Should Be $true
        }
        It "Should return result for the server when setting defined PowerPlan" {
            $results = Set-DbaPowerPlan -ComputerName $env:COMPUTERNAME -PowerPlan Balanced
            $results | Should Not Be Null
            $results.ActivePowerPlan -eq 'Balanced' | Should Be $true
        }
        It "Should accept Piped input from Test-DbaPowerPlan" {
            $results = Test-DbaPowerPlan -ComputerName $env:COMPUTERNAME | Set-DbaPowerPlan
            $results | Should Not Be Null
            $results.ActivePowerPlan -eq 'High Performance' | Should Be $true
        }
        It "Should return result for the server when using CustomPowerPlan" {
            $results = Set-DbaPowerPlan -ComputerName $env:COMPUTERNAME -CustomPowerPlan Balanced
            $results | Should Not Be Null
            $results.ActivePowerPlan -eq 'Balanced' | Should Be $true
        }
    }
}