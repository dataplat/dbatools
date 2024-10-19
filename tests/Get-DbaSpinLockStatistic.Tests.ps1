param($ModuleName = 'dbatools')

Describe "Get-DbaSpinLockStatistic" {
    BeforeAll {
        $commandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaSpinLockStatistic
        }
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "SqlCredential",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
        }
    }

    Context "Command returns proper info" {
        BeforeAll {
            $results = Get-DbaSpinLockStatistic -SqlInstance $global:instance2
        }

        It "returns results" {
            $results.Count | Should -BeGreaterThan 0
        }
    }
}
