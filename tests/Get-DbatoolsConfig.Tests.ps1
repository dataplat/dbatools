param($ModuleName = 'dbatools')

Describe "Get-DbatoolsConfig" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbatoolsConfig
        }
        It "Should have parameter FullName of type String" {
            $CommandUnderTest | Should -HaveParameter FullName -Type String -Mandatory:$false
        }
        It "Should have parameter Name of type String" {
            $CommandUnderTest | Should -HaveParameter Name -Type String -Mandatory:$false
        }
        It "Should have parameter Module of type String" {
            $CommandUnderTest | Should -HaveParameter Module -Type String -Mandatory:$false
        }
        It "Should have parameter Force of type Switch" {
            $CommandUnderTest | Should -HaveParameter Force -Type Switch -Mandatory:$false
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
