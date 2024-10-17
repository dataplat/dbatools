param($ModuleName = 'dbatools')

Describe "Set-DbaMaxDop" {
    BeforeAll {
        $commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        . "$PSScriptRoot\constants.ps1"

        $singledb = "dbatoolsci_singledb"
        $dbs = "dbatoolsci_lildb", "dbatoolsci_testMaxDop", $singledb
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Set-DbaMaxDop
        }
        It "Should have SqlInstance parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Mandatory:$false
        }
        It "Should have SqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Mandatory:$false
        }
        It "Should have Database parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type Object[] -Mandatory:$false
        }
        It "Should have ExcludeDatabase parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeDatabase -Type Object[] -Mandatory:$false
        }
        It "Should have MaxDop parameter" {
            $CommandUnderTest | Should -HaveParameter MaxDop -Type Int32 -Mandatory:$false
        }
        It "Should have InputObject parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type PSObject -Mandatory:$false
        }
        It "Should have AllDatabases parameter" {
            $CommandUnderTest | Should -HaveParameter AllDatabases -Type Switch -Mandatory:$false
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Mandatory:$false
        }
    }

    Context "Input validation" {
        BeforeAll {
            Mock Stop-Function { } -ModuleName dbatools
        }
        It "Should Call Stop-Function when -Database, -AllDatabases and -ExcludeDatabase are used together" {
            Set-DbaMaxDop -SqlInstance $global:instance1 -MaxDop 12 -Database $singledb -AllDatabases -ExcludeDatabase "master"
            Should -Invoke Stop-Function -Exactly 1 -Scope It -ModuleName dbatools
        }
    }

    Context "Apply to multiple instances" {
        BeforeAll {
            $results = Set-DbaMaxDop -SqlInstance $global:instance1, $global:instance2 -MaxDop 2
        }
        It 'Returns MaxDop 2 for each instance' {
            $results | ForEach-Object {
                $_.CurrentInstanceMaxDop | Should -Be 2
            }
        }
    }

    Context "Connects to 2016+ instance and apply configuration to single database" {
        BeforeAll {
            $results = Set-DbaMaxDop -SqlInstance $global:instance2 -MaxDop 4 -Database $singledb
        }
        It 'Returns 4 for each database' {
            $results | ForEach-Object {
                $_.DatabaseMaxDop | Should -Be 4
            }
        }
    }

    Context "Connects to 2016+ instance and apply configuration to multiple databases" {
        BeforeAll {
            $results = Set-DbaMaxDop -SqlInstance $global:instance2 -MaxDop 8 -Database $dbs
        }
        It 'Returns 8 for each database' {
            $results | ForEach-Object {
                $_.DatabaseMaxDop | Should -Be 8
            }
        }
    }

    Context "Piping from Test-DbaMaxDop works" {
        BeforeAll {
            $results = Test-DbaMaxDop -SqlInstance $global:instance2 | Set-DbaMaxDop -MaxDop 4
            $server = Connect-DbaInstance -SqlInstance $global:instance2
        }
        It 'Command returns output' {
            $results.CurrentInstanceMaxDop | Should -Not -BeNullOrEmpty
            $results.CurrentInstanceMaxDop | Should -Be 4
        }
        It 'Maxdop should match expected' {
            $server.Configuration.MaxDegreeOfParallelism.ConfigValue | Should -Be 4
        }
    }

    Context "Piping SqlInstance name works" {
        BeforeAll {
            $results = $global:instance2 | Set-DbaMaxDop -MaxDop 2
            $server = Connect-DbaInstance -SqlInstance $global:instance2
        }
        It 'Command returns output' {
            $results.CurrentInstanceMaxDop | Should -Not -BeNullOrEmpty
            $results.CurrentInstanceMaxDop | Should -Be 2
        }
        It 'Maxdop should match expected' {
            $server.Configuration.MaxDegreeOfParallelism.ConfigValue | Should -Be 2
        }
    }
}
