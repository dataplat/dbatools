param($ModuleName = 'dbatools')

Describe "Register-DbatoolsConfig" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Register-DbatoolsConfig
        }

        It "has all the required parameters" {
            $params = @(
                "Config",
                "FullName",
                "Module",
                "Name",
                "Scope",
                "EnableException"
            )
            It "has the required parameter: <_>" -ForEach $params {
                $CommandUnderTest | Should -HaveParameter $PSItem
            }
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
