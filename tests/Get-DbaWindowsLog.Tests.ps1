param($ModuleName = 'dbatools')

Describe "Get-DbaWindowsLog" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaWindowsLog
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have Start as a parameter" {
            $CommandUnderTest | Should -HaveParameter Start
        }
        It "Should have End as a parameter" {
            $CommandUnderTest | Should -HaveParameter End
        }
        It "Should have Credential as a parameter" {
            $CommandUnderTest | Should -HaveParameter Credential
        }
        It "Should have MaxThreads as a parameter" {
            $CommandUnderTest | Should -HaveParameter MaxThreads
        }
        It "Should have MaxRemoteThreads as a parameter" {
            $CommandUnderTest | Should -HaveParameter MaxRemoteThreads
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }

    Context "Command returns proper info" {
        BeforeAll {
            $results = Get-DbaWindowsLog -SqlInstance $global:instance2
        }
        It "returns results" {
            $results.Count | Should -BeGreaterThan 0
        }
    }
}
