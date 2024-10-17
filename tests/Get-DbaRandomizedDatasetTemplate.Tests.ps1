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
        It "Should have Template as a non-mandatory parameter of type String[]" {
            $CommandUnderTest | Should -HaveParameter Template -Type String[] -Mandatory:$false
        }
        It "Should have Path as a non-mandatory parameter of type String[]" {
            $CommandUnderTest | Should -HaveParameter Path -Type String[] -Mandatory:$false
        }
        It "Should have ExcludeDefault as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeDefault -Type Switch -Mandatory:$false
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Mandatory:$false
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
