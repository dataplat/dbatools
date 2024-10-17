param($ModuleName = 'dbatools')

Describe "Get-DbaAvailableCollation" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaAvailableCollation
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type SwitchParameter
        }
    }

    Context "Available Collations" {
        BeforeAll {
            . "$PSScriptRoot\constants.ps1"
        }
        BeforeDiscovery {
            . "$PSScriptRoot\constants.ps1"
        }
        It "Finds a collation that matches Slovenian" {
            $results = Get-DbaAvailableCollation -SqlInstance $script:instance2
            ($results.Name -match 'Slovenian').Count | Should -BeGreaterThan 10
        }
    }
}
