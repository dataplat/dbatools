param($ModuleName = 'dbatools')

Describe "Find-DbaDbDisabledIndex" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Find-DbaDbDisabledIndex
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type Dataplat.Dbatools.Parameter.DbaInstanceParameter[] -Mandatory:$false
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type System.Management.Automation.PSCredential -Mandatory:$false
        }
        It "Should have Database as a parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type System.Object[] -Mandatory:$false
        }
        It "Should have ExcludeDatabase as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeDatabase -Type System.Object[] -Mandatory:$false
        }
        It "Should have NoClobber as a parameter" {
            $CommandUnderTest | Should -HaveParameter NoClobber -Type System.Management.Automation.SwitchParameter -Mandatory:$false
        }
        It "Should have Append as a parameter" {
            $CommandUnderTest | Should -HaveParameter Append -Type System.Management.Automation.SwitchParameter -Mandatory:$false
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter -Mandatory:$false
        }
    }

    Context "Command actually works" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $global:instance1
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
            $results = Find-DbaDbDisabledIndex -SqlInstance $global:instance1
            ($results | Where-Object { $_.IndexName -eq $indexName }).Count | Should -Be 2
            ($results | Where-Object { $_.DatabaseName -in $databaseName1, $databaseName2 }).Count | Should -Be 2
            ($results | Where-Object { $_.DatabaseId -in $db1.Id, $db2.Id }).Count | Should -Be 2
        }
        It "Should find disabled index: $indexName for specific database" {
            $results = Find-DbaDbDisabledIndex -SqlInstance $global:instance1 -Database $databaseName1
            $results.IndexName | Should -Be $indexName
            $results.DatabaseName | Should -Be $databaseName1
            $results.DatabaseId | Should -Be $db1.Id
        }
        It "Should exclude specific database" {
            $results = Find-DbaDbDisabledIndex -SqlInstance $global:instance1 -ExcludeDatabase $databaseName1
            $results.IndexName | Should -Be $indexName
            $results.DatabaseName | Should -Be $databaseName2
            $results.DatabaseId | Should -Be $db2.Id
        }
    }
}
