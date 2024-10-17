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
            $CommandUnderTest | Should -HaveParameter Primary -Type DbaInstanceParameter
        }
        It "Should have PrimarySqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter PrimarySqlCredential -Type PSCredential
        }
        It "Should have Secondary parameter" {
            $CommandUnderTest | Should -HaveParameter Secondary -Type DbaInstanceParameter[]
        }
        It "Should have SecondarySqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SecondarySqlCredential -Type PSCredential
        }
        It "Should have AvailabilityGroup parameter" {
            $CommandUnderTest | Should -HaveParameter AvailabilityGroup -Type String
        }
        It "Should have Exclude parameter" {
            $CommandUnderTest | Should -HaveParameter Exclude -Type String[]
        }
        It "Should have Login parameter" {
            $CommandUnderTest | Should -HaveParameter Login -Type String[]
        }
        It "Should have ExcludeLogin parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeLogin -Type String[]
        }
        It "Should have Job parameter" {
            $CommandUnderTest | Should -HaveParameter Job -Type String[]
        }
        It "Should have ExcludeJob parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeJob -Type String[]
        }
        It "Should have DisableJobOnDestination parameter" {
            $CommandUnderTest | Should -HaveParameter DisableJobOnDestination -Type Switch
        }
        It "Should have InputObject parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type AvailabilityGroup[]
        }
        It "Should have Force parameter" {
            $CommandUnderTest | Should -HaveParameter Force -Type Switch
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch
        }
    }
}

<#
    Integration tests are custom to the command you are writing for.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidance
#>
