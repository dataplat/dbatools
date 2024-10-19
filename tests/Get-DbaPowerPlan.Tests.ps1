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
        It "has all the required parameters" {
            $requiredParameters = @(
                "ComputerName",
                "Credential",
                "List",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
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
