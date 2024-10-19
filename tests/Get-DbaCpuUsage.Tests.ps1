param($ModuleName = 'dbatools')

Describe "Get-DbaCpuUsage" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaCpuUsage
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have Credential as a parameter" {
            $CommandUnderTest | Should -HaveParameter Credential
        }
        It "Should have Threshold as a parameter" {
            $CommandUnderTest | Should -HaveParameter Threshold
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }

    Context "Gets the CPU Usage" {
        BeforeAll {
            $results = Get-DbaCPUUsage -SqlInstance $global:instance2
        }
        It "Results are not empty" {
            $results | Should -Not -BeNullOrEmpty
        }
    }
}
