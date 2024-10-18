param($ModuleName = 'dbatools')

Describe "Get-DbaSsisEnvironmentVariable" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaSsisEnvironmentVariable
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type Dataplat.Dbatools.Parameter.DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type System.Management.Automation.PSCredential
        }
        It "Should have Environment as a parameter" {
            $CommandUnderTest | Should -HaveParameter Environment -Type System.Object[]
        }
        It "Should have EnvironmentExclude as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnvironmentExclude -Type System.Object[]
        }
        It "Should have Folder as a parameter" {
            $CommandUnderTest | Should -HaveParameter Folder -Type System.Object[]
        }
        It "Should have FolderExclude as a parameter" {
            $CommandUnderTest | Should -HaveParameter FolderExclude -Type System.Object[]
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter
        }
    }
}

<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/sqlcollaborative/dbatools/blob/development/contributing.md#tests
    for more guidance.
#>
