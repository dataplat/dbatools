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
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Mandatory:$false
        }
        It "Should have SqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Mandatory:$false
        }
        It "Should have Database parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type Object[] -Mandatory:$false
        }
        It "Should have ExcludeDatabase parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeDatabase -Type Object[] -Mandatory:$false
        }
        It "Should have NoCheckDb parameter" {
            $CommandUnderTest | Should -HaveParameter NoCheckDb -Type Switch -Mandatory:$false
        }
        It "Should have NoUpdateUsage parameter" {
            $CommandUnderTest | Should -HaveParameter NoUpdateUsage -Type Switch -Mandatory:$false
        }
        It "Should have NoUpdateStats parameter" {
            $CommandUnderTest | Should -HaveParameter NoUpdateStats -Type Switch -Mandatory:$false
        }
        It "Should have NoRefreshView parameter" {
            $CommandUnderTest | Should -HaveParameter NoRefreshView -Type Switch -Mandatory:$false
        }
        It "Should have AllUserDatabases parameter" {
            $CommandUnderTest | Should -HaveParameter AllUserDatabases -Type Switch -Mandatory:$false
        }
        It "Should have Force parameter" {
            $CommandUnderTest | Should -HaveParameter Force -Type Switch -Mandatory:$false
        }
        It "Should have InputObject parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Database[] -Mandatory:$false
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Mandatory:$false
        }
    }
}

<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidance.
#>
