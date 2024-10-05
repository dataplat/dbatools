$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Write-host -Object "${script:instance2}" -ForegroundColor Cyan
Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'ExcludeDatabase', 'InputObject', 'ObjectName', 'IncludeStats', 'IncludeDataTypes', 'Raw', 'IncludeFragmentation', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}
Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $script:instance2
        $random = Get-Random
        $dbname = "dbatoolsci_$random"
        $server.Query("CREATE DATABASE $dbname")
        $server.Query("Create Table Test (col1 varchar(50) PRIMARY KEY, col2 int)", $dbname)
        $server.Query("Insert into test values ('value1',1),('value2',2)", $dbname)
        $server.Query("create statistics dbatools_stats on test (col2)", $dbname)
        $server.Query("select * from test", $dbname)
        $server.Query("create table t1(c1 int,c2 int,c3 int,c4 int)", $dbname)
        $server.Query("create nonclustered index idx_1 on t1(c1) include(c3)", $dbname)
        $server.Query("create table t2(c1 int,c2 int,c3 int,c4 int)", $dbname)
        $server.Query("create nonclustered index idx_1 on t2(c1,c2) include(c3,c4)", $dbname)
    }
    AfterAll {
        $null = Get-DbaDatabase -SqlInstance $script:instance2 -Database $dbname | Remove-DbaDatabase -Confirm:$false
    }
    Context "Command works for indexes" {
        $results = Get-DbaHelpIndex -SqlInstance $script:instance2 -Database $dbname -ObjectName Test
        It 'Results should be returned' {
            $results | Should Not BeNullOrEmpty
        }
        It 'Gets results for the test table' {
            $results.object | Should Be '[dbo].[test]'
        }
        It 'Correctly returns IndexRows of 2' {
            $results.IndexRows | Should Be 2
        }
        It 'Should not return datatype for col1' {
            $results.KeyColumns | Should Not Match 'varchar'
        }
    }
    Context "Command works when including statistics" {
        $results = Get-DbaHelpIndex -SqlInstance $script:instance2 -Database $dbname -ObjectName Test -IncludeStats | Where-Object { $_.Statistics }
        It 'Results should be returned' {
            $results | Should Not BeNullOrEmpty
        }
        It 'Returns dbatools_stats from test object' {
            $results.Statistics | Should Contain 'dbatools_stats'
        }
    }
    Context "Command output includes data types" {
        $results = Get-DbaHelpIndex -SqlInstance $script:instance2 -Database $dbname -ObjectName Test -IncludeDataTypes
        It 'Results should be returned' {
            $results | Should Not BeNullOrEmpty
        }
        It 'Returns varchar for col1' {
            $results.KeyColumns | Should Match 'varchar'
        }
    }
    Context "Formatting is correct" {
        $results = Get-DbaHelpIndex -SqlInstance $script:instance2 -Database $dbname -ObjectName Test -IncludeFragmentation
        It 'Formatted as strings' {
            $results.IndexReads | Should BeOfType 'String'
            $results.IndexUpdates | Should BeOfType 'String'
            $results.Size | Should BeOfType 'String'
            $results.IndexRows | Should BeOfType 'String'
            $results.IndexLookups | Should BeOfType 'String'
            $results.StatsSampleRows | Should BeOfType 'String'
            $results.IndexFragInPercent | Should BeOfType 'String'
        }
    }
    Context "Formatting is correct for raw" {
        $results = Get-DbaHelpIndex -SqlInstance $script:instance2 -Database $dbname -ObjectName Test -raw -IncludeFragmentation
        It 'Formatted as Long' {
            $results.IndexReads | Should BeOfType 'Long'
            $results.IndexUpdates | Should BeOfType 'Long'
            $results.Size | Should BeOfType 'dbasize'
            $results.IndexRows | Should BeOfType 'Long'
            $results.IndexLookups | Should BeOfType 'Long'
        }
        It 'Formatted as Double' {
            $results.IndexFragInPercent | Should BeOfType 'Double'
        }
    }
    Context "Result is correct for tables having the indexes with the same names" {
        $results = Get-DbaHelpIndex -SqlInstance $script:instance2 -Database $dbname
        It 'Table t1 has correct index key columns and included columns' {
            $results.where({ $_.object -eq '[dbo].[t1]' }).KeyColumns | Should -be 'c1'
            $results.where({ $_.object -eq '[dbo].[t1]' }).IncludeColumns | Should -be 'c3'
        }
        It 'Table t2 has correct index key columns and included columns' {
            $results.where({ $_.object -eq '[dbo].[t2]' }).KeyColumns | Should -be 'c1, c2'
            $results.where({ $_.object -eq '[dbo].[t2]' }).IncludeColumns | Should -be 'c3, c4'
        }

    }
}