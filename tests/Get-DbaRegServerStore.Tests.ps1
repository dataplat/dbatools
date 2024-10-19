param($ModuleName = 'dbatools')

Describe "Get-DbaRegServerStore" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaRegServerStore
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

    Context "Components are properly retrieved" {
        It "Should return the right values" {
            $results = Get-DbaRegServerStore -SqlInstance $global:instance2
            $results.InstanceName | Should -Not -BeNullOrEmpty
            $results.DisplayName | Should -Be "Central Management Servers"
        }
    }
}
