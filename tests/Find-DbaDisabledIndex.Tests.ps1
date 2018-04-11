$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        $paramCount = 7
        $defaultParamCount = 13
        [object[]]$params = (Get-ChildItem function:\Find-DbaDisabledIndex).Parameters.Keys
        $knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'ExcludeDatabase', 'NoClobber', 'Append','EnableException'
        It "Should contain our specific parameters" {
            ( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count ) | Should Be $paramCount
        }
        It "Should only contain $paramCount parameters" {
            $params.Count - $defaultParamCount | Should Be $paramCount
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
            $null = $server.Query($sql,'tempdb')
        }
        AfterAll {
           $sql = "drop table $tableName;"
           $null = $server.Query($sql,'tempdb')
        }

        It "Should find disabled index: $indexName" {
            $results = Find-DbadisabledIndex -SqlInstance $script:instance1
            $results.IndexName -contains $indexName | Should Be $true
        }
        It "Should find disabled index: $indexName for specific database" {
            $results = Find-DbadisabledIndex -SqlInstance $script:instance1 -Database tempdb
            $results.IndexName -contains $indexName | Should Be $true
        }
        It "Should exclude specific database" {
            $results = Find-DbadisabledIndex -SqlInstance $script:instance1 -ExcludeDatabase tempdb
            $results.DatabaseName -contains 'tempdb' | Should Be $false
        }
    }
}