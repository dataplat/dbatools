$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'ComputerName', 'Credential', 'CustomPowerPlan', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/sqlcollaborative/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>
Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $powerPlan = Test-DbaPowerPlan -ComputerName $env:COMPUTERNAME
        if ($powerPlan.PowerPlan -ne 'Balanced') {
            $null = Set-DbaPowerPlan -ComputerName $env:COMPUTERNAME -CustomPowerPlan 'Balanced'
        }
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
        It "Should return result for the server when using CustomPowerPlan" {
            $results = Set-DbaPowerPlan -ComputerName $env:COMPUTERNAME -CustomPowerPlan Balanced
            $results | Should Not Be Null
            $results.ActivePowerPlan | Should Be 'Balanced'
            $results.IsChanged | Should Be $true
        }
    }
}