$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'ExcludeDatabase', 'NoClobber', 'Append', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "Command actually works" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $script:instance1
            $random = Get-Random
            $indexName = "dbatoolsci_index_$random"
            $tableName = "dbatoolsci_table_$random"
            $sql = "create table $tableName (col1 int)
                    create index $indexName on $tableName (col1)
                    ALTER INDEX $indexName ON $tableName DISABLE;"
            $null = $server.Query($sql, 'tempdb')
        }
        AfterAll {
            $sql = "drop table $tableName;"
            $null = $server.Query($sql, 'tempdb')
        }

        It "Should find disabled index: $indexName" {
            $results = Find-DbaDbDisabledIndex -SqlInstance $script:instance1
            $results.IndexName -contains $indexName | Should Be $true
        }
        It "Should find disabled index: $indexName for specific database" {
            $results = Find-DbaDbDisabledIndex -SqlInstance $script:instance1 -Database tempdb
            $results.IndexName -contains $indexName | Should Be $true
        }
        It "Should exclude specific database" {
            $results = Find-DbaDbDisabledIndex -SqlInstance $script:instance1 -ExcludeDatabase tempdb
            $results.DatabaseName -contains 'tempdb' | Should Be $false
        }
    }
}