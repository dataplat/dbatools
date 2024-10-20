param($ModuleName = 'dbatools')

Describe "Test-DbaPowerPlan" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Test-DbaPowerPlan
        }
        $params = @(
            "ComputerName",
            "Credential",
            "PowerPlan",
            "EnableException"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }

    Context "Command actually works" {
        BeforeAll {
            $null = Set-DbaPowerPlan -ComputerName $global:instance2 -PowerPlan 'Balanced'
        }

        It "Should return result for the server" {
            $results = Test-DbaPowerPlan -ComputerName $global:instance2
            $results | Should -Not -BeNull
            $results.ActivePowerPlan | Should -Be 'Balanced'
            $results.RecommendedPowerPlan | Should -Be 'High performance'
            $results.RecommendedInstanceId | Should -Be '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
            $results.IsBestPractice | Should -BeFalse
        }

        It "Use 'Balanced' plan as best practice" {
            $results = Test-DbaPowerPlan -ComputerName $global:instance2 -PowerPlan 'Balanced'
            $results.IsBestPractice | Should -BeTrue
        }
    }
}
