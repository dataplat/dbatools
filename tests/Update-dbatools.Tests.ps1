param($ModuleName = 'dbatools')

Describe "Update-Dbatools" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Update-Dbatools
        }
        It "Should have Development as a Switch" {
            $CommandUnderTest | Should -HaveParameter Development
        }
        It "Should have Cleanup as a Switch" {
            $CommandUnderTest | Should -HaveParameter Cleanup
        }
        It "Should have EnableException as a Switch" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }
}

<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidance.
#>
