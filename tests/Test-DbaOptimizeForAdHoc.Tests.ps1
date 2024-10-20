param($ModuleName = 'dbatools')

Describe "Test-DbaOptimizeForAdHoc" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Test-DbaOptimizeForAdHoc
        }
        It "has all the required parameters" {
            $params = @(
                "SqlInstance",
                "SqlCredential",
                "EnableException"
            )
            It "has the required parameter: <_>" -ForEach $params {
                $CommandUnderTest | Should -HaveParameter $PSItem
            }
        }
    }

    Context "Command actually works" {
        BeforeAll {
            $results = Test-DbaOptimizeForAdHoc -SqlInstance $global:instance2
        }
        It "Should return result for the server" {
            $results | Should -Not -BeNullOrEmpty
        }
        It "Should return 'CurrentOptimizeAdHoc' property as int" {
            $results.CurrentOptimizeAdHoc | Should -BeOfType [System.Int32]
        }
        It "Should return 'RecommendedOptimizeAdHoc' property as int" {
            $results.RecommendedOptimizeAdHoc | Should -BeOfType [System.Int32]
        }
    }
}
