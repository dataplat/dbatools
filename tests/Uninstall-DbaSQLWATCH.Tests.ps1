$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        $paramCount = 7
        $commonParamCount = ([System.Management.Automation.PSCmdlet]::CommonParameters).Count + 2
        [object[]]$params = (Get-ChildItem function:\Uninstall-DbaSQLWATCH).Parameters.Keys
        $knownParameters = 'SqlInstance', 'SqlCredential', 'Branch', 'Database', 'Force', 'LocalFile', 'EnableException', 'ConnectionString'
        It "Should contain our specific parameters" {
            ( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count ) | Should Be $paramCount
        }
        It "Should only contain $paramCount parameters" {
            $params.Count - $commonParamCount | Should Be $paramCount
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "Testing SQLWATCH uninstaller" {
        BeforeAll {
            $database = "dbatoolsci_sqlwatch_$(Get-Random)"
            $server = Connect-DbaInstance -SqlInstance $script:instance2
            Install-DbaSQLWATCH -SqlInstance $server -Database $database
        }
        AfterAll {
            Remove-DbaDatabase -SqlInstance $server -Database $database -Confirm:$false
            Get-DbaAgentJob -SqlInstance $server | Where-Object {$PSItem.Name -like "DBA-PERF-*" } | Remove-DbaAgentJob
        }

        It "Removed all tables" {
            $tableCount = (Get-DbaDbTable -SqlInstance $server -Database $database | Where-Object {$PSItem.Name -like "sql_perf_mon_*" }).Count
            $tableCount | Should -Be 0
        }
        It "Removed all views" {
            $viewCount = (Get-DbaDbView -SqlInstance $server -Database $database | Where-Object {$PSItem.Name -like "vw_sql_perf_mon_*" }).Count
            $viewCount | Should -Be 0
        }
        It "Removed all stored procedures" {
            $sprocCount = (Get-DbaDbStoredProcedure -SqlInstance $server -Database $database | Where-Object {$PSItem.Name -like "sp_sql_perf_mon_*" }).Count
            $sprocCount | Should -Be 0
        }
        It "Removed all SQL Agent jobs" {
            $agentCount = (Get-DbaAgentJob -SqlInstance $server -Database $database | Where-Object {$PSItem.Name -like "DBA-PERF-*" }).Count
            $agentCount | Should -Be 0
        }

    }
}