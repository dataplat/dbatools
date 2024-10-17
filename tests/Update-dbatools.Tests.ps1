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
            $CommandUnderTest | Should -HaveParameter Development -Type switch
        }
        It "Should have Cleanup as a Switch" {
            $CommandUnderTest | Should -HaveParameter Cleanup -Type switch
        }
        It "Should have EnableException as a Switch" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type switch
        }
        It "Should have Verbose as a Switch" {
            $CommandUnderTest | Should -HaveParameter Verbose -Type switch
        }
        It "Should have Debug as a Switch" {
            $CommandUnderTest | Should -HaveParameter Debug -Type switch
        }
        It "Should have ErrorAction as an ActionPreference" {
            $CommandUnderTest | Should -HaveParameter ErrorAction -Type ActionPreference
        }
        It "Should have WarningAction as an ActionPreference" {
            $CommandUnderTest | Should -HaveParameter WarningAction -Type ActionPreference
        }
        It "Should have InformationAction as an ActionPreference" {
            $CommandUnderTest | Should -HaveParameter InformationAction -Type ActionPreference
        }
        It "Should have ProgressAction as an ActionPreference" {
            $CommandUnderTest | Should -HaveParameter ProgressAction -Type ActionPreference
        }
        It "Should have ErrorVariable as a String" {
            $CommandUnderTest | Should -HaveParameter ErrorVariable -Type string
        }
        It "Should have WarningVariable as a String" {
            $CommandUnderTest | Should -HaveParameter WarningVariable -Type string
        }
        It "Should have InformationVariable as a String" {
            $CommandUnderTest | Should -HaveParameter InformationVariable -Type string
        }
        It "Should have OutVariable as a String" {
            $CommandUnderTest | Should -HaveParameter OutVariable -Type string
        }
        It "Should have OutBuffer as an Int32" {
            $CommandUnderTest | Should -HaveParameter OutBuffer -Type int
        }
        It "Should have PipelineVariable as a String" {
            $CommandUnderTest | Should -HaveParameter PipelineVariable -Type string
        }
        It "Should have WhatIf as a Switch" {
            $CommandUnderTest | Should -HaveParameter WhatIf -Type switch
        }
        It "Should have Confirm as a Switch" {
            $CommandUnderTest | Should -HaveParameter Confirm -Type switch
        }
    }
}

<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidance.
#>
