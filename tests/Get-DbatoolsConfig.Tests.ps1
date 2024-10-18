param($ModuleName = 'dbatools')

Describe "Get-DbatoolsConfig" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbatoolsConfig
        }
        It "Should have parameter FullName of type System.String" {
            $CommandUnderTest | Should -HaveParameter FullName -Type System.String -Mandatory:$false
        }
        It "Should have parameter Name of type System.String" {
            $CommandUnderTest | Should -HaveParameter Name -Type System.String -Mandatory:$false
        }
        It "Should have parameter Module of type System.String" {
            $CommandUnderTest | Should -HaveParameter Module -Type System.String -Mandatory:$false
        }
        It "Should have parameter Force of type System.Management.Automation.SwitchParameter" {
            $CommandUnderTest | Should -HaveParameter Force -Type System.Management.Automation.SwitchParameter -Mandatory:$false
        }
    }

    Context "Command usage" {
        BeforeAll {
            . "$PSScriptRoot\constants.ps1"
        }

        It "Returns proper information" {
            $results = Get-DbatoolsConfig -FullName sql.connection.timeout
            $results.Value | Should -BeOfType [System.Int32]
        }
    }
}
