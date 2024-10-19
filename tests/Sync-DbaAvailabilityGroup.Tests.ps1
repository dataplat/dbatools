param($ModuleName = 'dbatools')

Describe "Sync-DbaAvailabilityGroup" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Sync-DbaAvailabilityGroup
        }
        It "Should have Primary parameter" {
            $CommandUnderTest | Should -HaveParameter Primary
        }
        It "Should have PrimarySqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter PrimarySqlCredential
        }
        It "Should have Secondary parameter" {
            $CommandUnderTest | Should -HaveParameter Secondary
        }
        It "Should have SecondarySqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SecondarySqlCredential
        }
        It "Should have AvailabilityGroup parameter" {
            $CommandUnderTest | Should -HaveParameter AvailabilityGroup
        }
        It "Should have Exclude parameter" {
            $CommandUnderTest | Should -HaveParameter Exclude
        }
        It "Should have Login parameter" {
            $CommandUnderTest | Should -HaveParameter Login
        }
        It "Should have ExcludeLogin parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeLogin
        }
        It "Should have Job parameter" {
            $CommandUnderTest | Should -HaveParameter Job
        }
        It "Should have ExcludeJob parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeJob
        }
        It "Should have DisableJobOnDestination parameter" {
            $CommandUnderTest | Should -HaveParameter DisableJobOnDestination
        }
        It "Should have InputObject parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject
        }
        It "Should have Force parameter" {
            $CommandUnderTest | Should -HaveParameter Force
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }
}

<#
    Integration tests are custom to the command you are writing for.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidance
#>
