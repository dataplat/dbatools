$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'ComputerName', 'Credential', 'CustomPowerPlan', 'InputObject', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "Command actually works" {
        It "Should return result for the server" {
            $results = Test-DbaPowerPlan -ComputerName $script:instance2
            $results | Should Not Be Null
            $results.RecommendedPowerPlan | Should Be 'High performance'
            $results.RecommendedInstanceId | Should Be '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
            $results.ActivePowerPlan | Should Be 'High performance'
        }
        It "Use 'Balanced' plan as best practice" {
            $null = Set-DbaPowerPlan -ComputerName $env:COMPUTERNAME -PowerPlan Balanced
            $results = Test-DbaPowerPlan -ComputerName $script:instance2 -CustomPowerPlan 'Balanced'
            $results.IsBestPractice | Should Be $true
        }
    }
}