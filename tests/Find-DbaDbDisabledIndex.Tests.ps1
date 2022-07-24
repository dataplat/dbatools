$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'ExcludeDatabase', 'NoClobber', 'Append', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "Command actually works" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $script:instance1
            $random = Get-Random
            $databaseName1 = "dbatoolsci1_$random"
            $databaseName2 = "dbatoolsci2_$random"
            $db1 = New-DbaDatabase -SqlInstance $server -Name $databaseName1
            $db2 = New-DbaDatabase -SqlInstance $server -Name $databaseName2
            $indexName = "dbatoolsci_index_$random"
            $tableName = "dbatoolsci_table_$random"
            $sql = "create table $tableName (col1 int)
                    create index $indexName on $tableName (col1)
                    ALTER INDEX $indexName ON $tableName DISABLE;"
            $null = $db1.Query($sql)
            $null = $db2.Query($sql)
        }
        AfterAll {
            $db1, $db2 | Remove-DbaDatabase -Confirm:$false
        }

        It "Should find disabled index: $indexName" {
            $results = Find-DbaDbDisabledIndex -SqlInstance $script:instance1
            ($results | Where-Object { $_.IndexName -eq $indexName }).Count | Should -Be 2
            ($results | Where-Object { $_.DatabaseName -in $databaseName1, $databaseName2 }).Count | Should -Be 2
            ($results | Where-Object { $_.DatabaseId -in $db1.Id, $db2.Id }).Count | Should -Be 2
        }
        It "Should find disabled index: $indexName for specific database" {
            $results = Find-DbaDbDisabledIndex -SqlInstance $script:instance1 -Database $databaseName1
            $results.IndexName | Should -Be $indexName
            $results.DatabaseName | Should -Be $databaseName1
            $results.DatabaseId | Should -Be $db1.Id
        }
        It "Should exclude specific database" {
            $results = Find-DbaDbDisabledIndex -SqlInstance $script:instance1 -ExcludeDatabase $databaseName1
            $results.IndexName | Should -Be $indexName
            $results.DatabaseName | Should -Be $databaseName2
            $results.DatabaseId | Should -Be $db2.Id
        }
    }
}