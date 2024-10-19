param($ModuleName = 'dbatools')

Describe "Get-DbatoolsConfig" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbatoolsConfig
        }
        It "Should have parameter FullName" {
            $CommandUnderTest | Should -HaveParameter FullName
        }
        It "Should have parameter Name" {
            $CommandUnderTest | Should -HaveParameter Name
        }
        It "Should have parameter Module" {
            $CommandUnderTest | Should -HaveParameter Module
        }
        It "Should have parameter Force" {
            $CommandUnderTest | Should -HaveParameter Force
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
