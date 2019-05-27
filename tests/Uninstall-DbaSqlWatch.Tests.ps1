$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "Testing SqlWatch uninstaller" {
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
            $tableCount = (Get-DbaDbTable -SqlInstance $script:instance2 -Database $Database | Where-Object {($PSItem.Name -like "sql_perf_mon_*") -or ($PSItem.Name -like "logger_*")}).Count
            $tableCount | Should -Be 0
        }
        It "Removed all views" {
            $viewCount = (Get-DbaDbView -SqlInstance $script:instance2 -Database $Database | Where-Object {$PSItem.Name -like "vw_sql_perf_mon_*" }).Count
            $viewCount | Should -Be 0
        }
        It "Removed all stored procedures" {
            $sprocCount = (Get-DbaDbStoredProcedure -SqlInstance $script:instance2 -Database $Database | Where-Object {($PSItem.Name -like "sp_sql_perf_mon_*") -or ($PSItem.Name -like "usp_logger_*")}).Count
            $sprocCount | Should -Be 0
        }
        It "Removed all SQL Agent jobs" {
            $agentCount = (Get-DbaAgentJob -SqlInstance $script:instance2 | Where-Object {($PSItem.Name -like "SqlWatch-*") -or ($PSItem.Name -like "DBA-PERF-*")}).Count
            $agentCount | Should -Be 0
        }

    }
}