param($ModuleName = 'dbatools')

Describe "Invoke-DbaDbLogShipRecovery" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Invoke-DbaDbLogShipRecovery
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have Database as a parameter" {
            $CommandUnderTest | Should -HaveParameter Database
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have NoRecovery as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter NoRecovery
        }
        It "Should have EnableException as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
        It "Should have Force as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter Force
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject
        }
        It "Should have Delay as a parameter" {
            $CommandUnderTest | Should -HaveParameter Delay
        }
    }
}

<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidance.
#>
