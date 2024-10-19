param($ModuleName = 'dbatools')

Describe "Get-DbaInstanceInstallDate" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaInstanceInstallDate
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
        It "Should have IncludeWindows as a parameter" {
            $CommandUnderTest | Should -HaveParameter IncludeWindows
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }

    Context "Gets SQL Server Install Date" {
        BeforeAll {
            $results = Get-DbaInstanceInstallDate -SqlInstance $global:instance2
        }
        It "Gets results" {
            $results | Should -Not -BeNullOrEmpty
        }
    }

    Context "Gets SQL Server Install Date and Windows Install Date" {
        BeforeAll {
            $results = Get-DbaInstanceInstallDate -SqlInstance $global:instance2 -IncludeWindows
        }
        It "Gets results" {
            $results | Should -Not -BeNullOrEmpty
        }
    }
}
