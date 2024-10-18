param($ModuleName = 'dbatools')

Describe "Get-DbaHelpIndex Unit Tests" -Tag 'UnitTests' {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
        Write-host -Object "${script:instance2}" -ForegroundColor Cyan
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaHelpIndex
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type Dataplat.Dbatools.Parameter.DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type System.Management.Automation.PSCredential
        }
        It "Should have Database as a parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type System.Object[]
        }
        It "Should have ExcludeDatabase as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeDatabase -Type System.Object[]
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Microsoft.SqlServer.Management.Smo.Database[]
        }
        It "Should have ObjectName as a parameter" {
            $CommandUnderTest | Should -HaveParameter ObjectName -Type System.String
        }
        It "Should have IncludeStats as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter IncludeStats -Type System.Management.Automation.SwitchParameter
        }
        It "Should have IncludeDataTypes as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter IncludeDataTypes -Type System.Management.Automation.SwitchParameter
        }
        It "Should have Raw as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter Raw -Type System.Management.Automation.SwitchParameter
        }
        It "Should have IncludeFragmentation as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter IncludeFragmentation -Type System.Management.Automation.SwitchParameter
        }
        It "Should have EnableException as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter
        }
    }
}

Describe "Get-DbaHelpIndex Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $global:instance2
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
        $null = Get-DbaDatabase -SqlInstance $global:instance2 -Database $dbname | Remove-DbaDatabase -Confirm:$false
    }

    Context "Command works for indexes" {
        BeforeAll {
            $results = Get-DbaHelpIndex -SqlInstance $global:instance2 -Database $dbname -ObjectName Test
        }

        It 'Results should be returned' {
            $results | Should -Not -BeNullOrEmpty
        }

        It 'Gets results for the test table' {
            $results.object | Should -Be '[dbo].[test]'
        }

        It 'Correctly returns IndexRows of 2' {
            $results.IndexRows | Should -Be 2
        }

        It 'Should not return datatype for col1' {
            $results.KeyColumns | Should -Not -Match 'varchar'
        }
    }

    Context "Command works when including statistics" {
        BeforeAll {
            $results = Get-DbaHelpIndex -SqlInstance $global:instance2 -Database $dbname -ObjectName Test -IncludeStats | Where-Object { $_.Statistics }
        }

        It 'Results should be returned' {
            $results | Should -Not -BeNullOrEmpty
        }

        It 'Returns dbatools_stats from test object' {
            $results.Statistics | Should -Contain 'dbatools_stats'
        }
    }

    Context "Command output includes data types" {
        BeforeAll {
            $results = Get-DbaHelpIndex -SqlInstance $global:instance2 -Database $dbname -ObjectName Test -IncludeDataTypes
        }

        It 'Results should be returned' {
            $results | Should -Not -BeNullOrEmpty
        }

        It 'Returns varchar for col1' {
            $results.KeyColumns | Should -Match 'varchar'
        }
    }

    Context "Formatting is correct" {
        BeforeAll {
            $results = Get-DbaHelpIndex -SqlInstance $global:instance2 -Database $dbname -ObjectName Test -IncludeFragmentation
        }

        It 'Formatted as strings' {
            $results.IndexReads | Should -BeOfType 'String'
            $results.IndexUpdates | Should -BeOfType 'String'
            $results.Size | Should -BeOfType 'String'
            $results.IndexRows | Should -BeOfType 'String'
            $results.IndexLookups | Should -BeOfType 'String'
            $results.StatsSampleRows | Should -BeOfType 'String'
            $results.IndexFragInPercent | Should -BeOfType 'String'
        }
    }

    Context "Formatting is correct for raw" {
        BeforeAll {
            $results = Get-DbaHelpIndex -SqlInstance $global:instance2 -Database $dbname -ObjectName Test -raw -IncludeFragmentation
        }

        It 'Formatted as Long' {
            $results.IndexReads | Should -BeOfType 'Long'
            $results.IndexUpdates | Should -BeOfType 'Long'
            $results.Size | Should -BeOfType 'dbasize'
            $results.IndexRows | Should -BeOfType 'Long'
            $results.IndexLookups | Should -BeOfType 'Long'
        }

        It 'Formatted as Double' {
            $results.IndexFragInPercent | Should -BeOfType 'Double'
        }
    }

    Context "Result is correct for tables having the indexes with the same names" {
        BeforeAll {
            $results = Get-DbaHelpIndex -SqlInstance $global:instance2 -Database $dbname
        }

        It 'Table t1 has correct index key columns and included columns' {
            $results.where({ $_.object -eq '[dbo].[t1]' }).KeyColumns | Should -Be 'c1'
            $results.where({ $_.object -eq '[dbo].[t1]' }).IncludeColumns | Should -Be 'c3'
        }

        It 'Table t2 has correct index key columns and included columns' {
            $results.where({ $_.object -eq '[dbo].[t2]' }).KeyColumns | Should -Be 'c1, c2'
            $results.where({ $_.object -eq '[dbo].[t2]' }).IncludeColumns | Should -Be 'c3, c4'
        }
    }
}
