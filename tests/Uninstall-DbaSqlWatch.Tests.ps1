param($ModuleName = 'dbatools')

Describe "Uninstall-DbaSqlWatch" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Uninstall-DbaSqlWatch
        }
        It "Should have SqlInstance parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have Database parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type String
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type SwitchParameter
        }
    }

    Context "Testing SqlWatch uninstaller" {
        BeforeDiscovery {
            . (Join-Path $PSScriptRoot 'constants.ps1')
        }

        BeforeAll {
            $database = "dbatoolsci_sqlwatch_$(Get-Random)"
            $server = Connect-DbaInstance -SqlInstance $script:instance2
            $server.Query("CREATE DATABASE $database")
            Install-DbaSqlWatch -SqlInstance $script:instance2 -Database $database
            Uninstall-DbaSqlWatch -SqlInstance $script:instance2 -Database $database
        }

        AfterAll {
            Remove-DbaDatabase -SqlInstance $script:instance2 -Database $database -Confirm:$false
        }

        It "Removed all tables" {
            $tableCount = (Get-DbaDbTable -SqlInstance $script:instance2 -Database $Database | Where-Object {($_.Name -like "sql_perf_mon_*") -or ($_.Name -like "logger_*")}).Count
            $tableCount | Should -Be 0
        }

        It "Removed all views" {
            $viewCount = (Get-DbaDbView -SqlInstance $script:instance2 -Database $Database | Where-Object {$_.Name -like "vw_sql_perf_mon_*" }).Count
            $viewCount | Should -Be 0
        }

        It "Removed all stored procedures" {
            $sprocCount = (Get-DbaDbStoredProcedure -SqlInstance $script:instance2 -Database $Database | Where-Object {($_.Name -like "sp_sql_perf_mon_*") -or ($_.Name -like "usp_logger_*")}).Count
            $sprocCount | Should -Be 0
        }

        It "Removed all SQL Agent jobs" {
            $agentCount = (Get-DbaAgentJob -SqlInstance $script:instance2 | Where-Object {($_.Name -like "SqlWatch-*") -or ($_.Name -like "DBA-PERF-*")}).Count
            $agentCount | Should -Be 0
        }
    }
}
