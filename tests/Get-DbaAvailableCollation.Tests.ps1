param($ModuleName = 'dbatools')

Describe "Get-DbaAvailableCollation" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaAvailableCollation
        }
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "SqlCredential",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
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
