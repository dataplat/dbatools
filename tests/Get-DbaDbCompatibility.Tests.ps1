param($ModuleName = 'dbatools')

Describe "Get-DbaDbCompatibility" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaDbCompatibility
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have Database as a parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type String[]
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Microsoft.SqlServer.Management.Smo.Database[]
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch
        }
    }

    Context "Command usage" {
        BeforeDiscovery {
            . "$PSScriptRoot\constants.ps1"
        }
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $global:instance1
            $compatibilityLevel = $server.Databases['master'].CompatibilityLevel
        }

        Context "Gets compatibility for multiple databases" {
            BeforeAll {
                $results = Get-DbaDbCompatibility -SqlInstance $global:instance1
            }
            It "Gets results" {
                $results | Should -Not -BeNullOrEmpty
            }
            It "Should return correct compatibility level for <_.Database>" -ForEach $results {
                # Only test system databases as there might be leftover databases from other tests
                if ($_.DatabaseId -le 4) {
                    $_.Compatibility | Should -Be $compatibilityLevel
                }
                $_.DatabaseId | Should -Be (Get-DbaDatabase -SqlInstance $global:instance1 -Database $_.Database).Id
            }
        }

        Context "Gets compatibility for one database" {
            BeforeAll {
                $results = Get-DbaDbCompatibility -SqlInstance $global:instance1 -Database master
            }
            It "Gets results" {
                $results | Should -Not -BeNullOrEmpty
            }
            It "Should return correct compatibility level for master" {
                $results.Compatibility | Should -Be $compatibilityLevel
                $results.DatabaseId | Should -Be (Get-DbaDatabase -SqlInstance $global:instance1 -Database master).Id
            }
        }
    }
}
