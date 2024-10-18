param($ModuleName = 'dbatools')

Describe "Register-DbatoolsConfig" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Register-DbatoolsConfig
        }
        It "Accepts Config as a parameter" {
            $CommandUnderTest | Should -HaveParameter Config -Type Dataplat.Dbatools.Configuration.Config[]
        }
        It "Accepts FullName as a parameter" {
            $CommandUnderTest | Should -HaveParameter FullName -Type System.String[]
        }
        It "Accepts Module as a parameter" {
            $CommandUnderTest | Should -HaveParameter Module -Type System.String
        }
        It "Accepts Name as a parameter" {
            $CommandUnderTest | Should -HaveParameter Name -Type System.String
        }
        It "Accepts Scope as a parameter" {
            $CommandUnderTest | Should -HaveParameter Scope -Type Dataplat.Dbatools.Configuration.ConfigScope
        }
        It "Accepts EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter
        }
    }

    Context "Command usage" {
        BeforeAll {
            # Add any necessary setup code here
        }

        It "Should do something" {
            # Add actual test cases here
            $true | Should -Be $true
        }
    }
}
