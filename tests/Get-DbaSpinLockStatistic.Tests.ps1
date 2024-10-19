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
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
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
