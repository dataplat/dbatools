param($ModuleName = 'dbatools')

Describe "Invoke-DbaDbUpgrade" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Invoke-DbaDbUpgrade
        }
        It "Should have SqlInstance parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Not -Mandatory
        }
        It "Should have SqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Not -Mandatory
        }
        It "Should have Database parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type Object[] -Not -Mandatory
        }
        It "Should have ExcludeDatabase parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeDatabase -Type Object[] -Not -Mandatory
        }
        It "Should have NoCheckDb parameter" {
            $CommandUnderTest | Should -HaveParameter NoCheckDb -Type SwitchParameter -Not -Mandatory
        }
        It "Should have NoUpdateUsage parameter" {
            $CommandUnderTest | Should -HaveParameter NoUpdateUsage -Type SwitchParameter -Not -Mandatory
        }
        It "Should have NoUpdateStats parameter" {
            $CommandUnderTest | Should -HaveParameter NoUpdateStats -Type SwitchParameter -Not -Mandatory
        }
        It "Should have NoRefreshView parameter" {
            $CommandUnderTest | Should -HaveParameter NoRefreshView -Type SwitchParameter -Not -Mandatory
        }
        It "Should have AllUserDatabases parameter" {
            $CommandUnderTest | Should -HaveParameter AllUserDatabases -Type SwitchParameter -Not -Mandatory
        }
        It "Should have Force parameter" {
            $CommandUnderTest | Should -HaveParameter Force -Type SwitchParameter -Not -Mandatory
        }
        It "Should have InputObject parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Database[] -Not -Mandatory
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type SwitchParameter -Not -Mandatory
        }
    }
}

<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidance.
#>
