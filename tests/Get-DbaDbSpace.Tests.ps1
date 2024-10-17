param($ModuleName = 'dbatools')

Describe "Get-DbaDbSpace" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaDbSpace
        }
        It "Should have SqlInstance as a non-mandatory parameter of type DbaInstanceParameter[]" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Mandatory:$false
        }
        It "Should have SqlCredential as a non-mandatory parameter of type PSCredential" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Mandatory:$false
        }
        It "Should have Database as a non-mandatory parameter of type String[]" {
            $CommandUnderTest | Should -HaveParameter Database -Type String[] -Mandatory:$false
        }
        It "Should have ExcludeDatabase as a non-mandatory parameter of type String[]" {
            $CommandUnderTest | Should -HaveParameter ExcludeDatabase -Type String[] -Mandatory:$false
        }
        It "Should have IncludeSystemDBs as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter IncludeSystemDBs -Type Switch -Mandatory:$false
        }
        It "Should have InputObject as a non-mandatory parameter of type Database[]" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Database[] -Mandatory:$false
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Mandatory:$false
        }
    }

    Context "Command usage" {
        BeforeAll {
            $dbname = "dbatoolsci_test_$(Get-Random)"
            $server = Connect-DbaInstance -SqlInstance $global:instance2
            $null = $server.Query("Create Database [$dbname]")
        }
        AfterAll {
            Remove-DbaDatabase -SqlInstance $global:instance2 -Database $dbname -Confirm:$false
        }

        Context "Gets DbSpace" {
            BeforeAll {
                $results = Get-DbaDbSpace -SqlInstance $global:instance2 | Where-Object { $_.Database -eq "$dbname" }
            }
            It "Gets results" {
                $results | Should -Not -BeNullOrEmpty
            }
            It "Should retrieve space for $dbname" {
                $results | ForEach-Object {
                    $_.Database | Should -Be $dbname
                    $_.UsedSpace | Should -Not -BeNullOrEmpty
                }
            }
            It "Should have a physical path for $dbname" {
                $results | ForEach-Object {
                    $_.PhysicalName | Should -Not -BeNullOrEmpty
                }
            }
        }

        Context "Gets DbSpace when using -Database" {
            BeforeAll {
                $results = Get-DbaDbSpace -SqlInstance $global:instance2 -Database $dbname
            }
            It "Gets results" {
                $results | Should -Not -BeNullOrEmpty
            }
            It "Should retrieve space for $dbname" {
                $results | ForEach-Object {
                    $_.Database | Should -Be $dbname
                    $_.UsedSpace | Should -Not -BeNullOrEmpty
                }
            }
            It "Should have a physical path for $dbname" {
                $results | ForEach-Object {
                    $_.PhysicalName | Should -Not -BeNullOrEmpty
                }
            }
        }

        Context "Gets no DbSpace for specific database when using -ExcludeDatabase" {
            BeforeAll {
                $results = Get-DbaDbSpace -SqlInstance $global:instance2 -ExcludeDatabase $dbname
            }
            It "Gets no results for excluded database" {
                $results.Database | Should -Not -Contain $dbname
            }
        }
    }
}
