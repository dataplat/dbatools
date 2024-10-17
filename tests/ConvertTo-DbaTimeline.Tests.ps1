param($ModuleName = 'dbatools')

Describe "ConvertTo-DbaTimeline" {
    BeforeAll {
        $CommandName = $PSCommandPath.Split('\')[-1].Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command ConvertTo-DbaTimeline
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Object[] -Mandatory:$false
        }
        It "Should have ExcludeRowLabel as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeRowLabel -Type Switch -Mandatory:$false
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Mandatory:$false
        }
    }

    Context "Command usage" {
        BeforeAll {
            # Add any necessary setup for command usage tests
        }

        It "Example test" {
            # Add actual tests here
            $true | Should -Be $true
        }
    }
}

<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidance.
#>
