param($ModuleName = 'dbatools')

Describe "Get-DbaAvailableCollation" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaAvailableCollation
        }
        $params = @(
            "SqlInstance",
            "SqlCredential",
            "EnableException"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
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
            $results = Get-DbaAvailableCollation -SqlInstance $global:instance2
            ($results.Name -match 'Slovenian').Count | Should -BeGreaterThan 10
        }
    }
}
