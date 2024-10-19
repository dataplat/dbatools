param($ModuleName = 'dbatools')

Describe "Get-DbaRandomizedDatasetTemplate" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaRandomizedDatasetTemplate
        }
        It "Should have Template as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Template
        }
        It "Should have Path as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Path
        }
        It "Should have ExcludeDefault as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeDefault
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }

    Context "Command returns templates" {
        BeforeAll {
            $templates = Get-DbaRandomizedDatasetTemplate
        }

        It "Should have at least 1 row" {
            $templates.Count | Should -BeGreaterThan 0
        }
    }
}
