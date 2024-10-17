param($ModuleName = 'dbatools')

Describe "Get-DbatoolsConfig" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbatoolsConfig
        }
        It "Should have parameter FullName of type String" {
            $CommandUnderTest | Should -HaveParameter FullName -Type String -Not -Mandatory
        }
        It "Should have parameter Name of type String" {
            $CommandUnderTest | Should -HaveParameter Name -Type String -Not -Mandatory
        }
        It "Should have parameter Module of type String" {
            $CommandUnderTest | Should -HaveParameter Module -Type String -Not -Mandatory
        }
        It "Should have parameter Force of type SwitchParameter" {
            $CommandUnderTest | Should -HaveParameter Force -Type SwitchParameter -Not -Mandatory
        }
    }

    Context "Command usage" {
        BeforeAll {
            . "$PSScriptRoot\constants.ps1"
        }

        It "Returns proper information" {
            $results = Get-DbatoolsConfig -FullName sql.connection.timeout
            $results.Value | Should -BeOfType [int]
        }
    }
}
