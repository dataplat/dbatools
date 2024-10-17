param($ModuleName = 'dbatools')

Describe "Invoke-DbaDbClone" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Invoke-DbaDbClone
        }
        It "Should have SqlInstance parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Not -Mandatory
        }
        It "Should have SqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Not -Mandatory
        }
        It "Should have Database parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type String[] -Not -Mandatory
        }
        It "Should have InputObject parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Database[] -Not -Mandatory
        }
        It "Should have CloneDatabase parameter" {
            $CommandUnderTest | Should -HaveParameter CloneDatabase -Type String[] -Not -Mandatory
        }
        It "Should have ExcludeStatistics parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeStatistics -Type SwitchParameter -Not -Mandatory
        }
        It "Should have ExcludeQueryStore parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeQueryStore -Type SwitchParameter -Not -Mandatory
        }
        It "Should have UpdateStatistics parameter" {
            $CommandUnderTest | Should -HaveParameter UpdateStatistics -Type SwitchParameter -Not -Mandatory
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type SwitchParameter -Not -Mandatory
        }
    }

    Context "Command functions as expected" {
        BeforeAll {
            $dbname = "dbatoolsci_clonetest"
            $clonedb = "dbatoolsci_clonetest_CLONE"
            $clonedb2 = "dbatoolsci_clonetest_CLONE2"

            $server = Connect-DbaInstance -SqlInstance $script:instance2
            $server.Query("CREATE DATABASE $dbname")
        }

        AfterAll {
            Get-DbaDatabase -SqlInstance $server -Database $dbname, $clonedb, $clonedb2 | Remove-DbaDatabase -Confirm:$false
        }

        It "warns if SQL instance version is not supported" {
            $versionwarn = $null
            $results = Invoke-DbaDbClone -SqlInstance $script:instance1 -Database $dbname -CloneDatabase $clonedb -WarningAction SilentlyContinue -WarningVariable versionwarn
            $versionwarn | Should -Match "required"
        }

        It "warns if destination database already exists" {
            $dbwarn = $null
            $results = Invoke-DbaDbClone -SqlInstance $script:instance2 -Database $dbname -CloneDatabase tempdb -WarningAction SilentlyContinue -WarningVariable dbwarn
            $dbwarn | Should -Match "exists"
        }

        It "warns if a system db is specified to clone" {
            $systemwarn = $null
            $results = Invoke-DbaDbClone -SqlInstance $script:instance2 -Database master -CloneDatabase $clonedb -WarningAction SilentlyContinue -WarningVariable systemwarn
            $systemwarn | Should -Match "user database"
        }

        It "returns 1 result with the correct name" {
            $results = Invoke-DbaDbClone -SqlInstance $script:instance2 -Database $dbname -CloneDatabase $clonedb -WarningAction SilentlyContinue
            $results | Should -HaveCount 1
            $results.Name | Should -BeIn @($clonedb, $clonedb2)
        }
    }
}
