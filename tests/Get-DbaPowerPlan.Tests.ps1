param($ModuleName = 'dbatools')

Describe "Get-DbaPowerPlan" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaPowerPlan
        }
        $params = @(
            "ComputerName",
            "Credential",
            "List",
            "EnableException"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }

    Context "Command actually works" {
        BeforeDiscovery {
            . "$PSScriptRoot\constants.ps1"
        }
        It "Should return result for the server" {
            $results = Get-DbaPowerPlan -ComputerName $global:instance2
            $results | Should -Not -BeNullOrEmpty
        }
    }
}
