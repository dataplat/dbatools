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
        $params = @(
            "Template",
            "Path",
            "ExcludeDefault",
            "EnableException"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
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
