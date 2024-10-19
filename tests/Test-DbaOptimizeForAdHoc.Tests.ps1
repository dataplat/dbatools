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
