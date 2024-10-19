param($ModuleName = 'dbatools')

Describe "Find-DbaDbUnusedIndex" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Find-DbaDbUnusedIndex
        }
        It "Should have SqlInstance parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have Database parameter" {
            $CommandUnderTest | Should -HaveParameter Database
        }
        It "Should have ExcludeDatabase parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeDatabase
        }
        It "Should have IgnoreUptime parameter" {
            $CommandUnderTest | Should -HaveParameter IgnoreUptime
        }
        It "Should have Seeks parameter" {
            $CommandUnderTest | Should -HaveParameter Seeks
        }
        It "Should have Scans parameter" {
            $CommandUnderTest | Should -HaveParameter Scans
        }
        It "Should have Lookups parameter" {
            $CommandUnderTest | Should -HaveParameter Lookups
        }
        It "Should have InputObject parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }
}

Describe "Find-DbaDbUnusedIndex Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
        $server = Connect-DbaInstance -SqlInstance $global:instance2
        $random = Get-Random
        $dbName = "dbatoolsci_$random"
        $null = New-DbaDatabase -SqlInstance $global:instance2 -Name $dbName

        $indexName = "dbatoolsci_index_$random"
        $tableName = "dbatoolsci_table_$random"
        $sql = @"
USE $dbName;
CREATE TABLE $tableName (ID INTEGER);
CREATE INDEX $indexName ON $tableName (ID);
INSERT INTO $tableName (ID) VALUES (1);
SELECT ID FROM $tableName;
WAITFOR DELAY '00:00:05';
"@
        $null = $server.Query($sql)
    }

    AfterAll {
        Remove-DbaDatabase -SqlInstance $global:instance2 -Database $dbName -Confirm:$false
    }

    It "Should find the 'unused' index" {
        $results = Find-DbaDbUnusedIndex -SqlInstance $global:instance2 -Database $dbName -IgnoreUptime -Seeks 10 -Scans 10 -Lookups 10
        $results.Database | Should -Be $dbName
        $results.IndexName | Should -Contain $indexName
    }

    It "Should return the expected columns" {
        $expectedColumns = @('CompressionDescription', 'ComputerName', 'Database', 'DatabaseId', 'IndexId', 'IndexName', 'IndexSizeMB', 'InstanceName', 'LastSystemLookup', 'LastSystemScan', 'LastSystemSeek', 'LastSystemUpdate', 'LastUserLookup', 'LastUserScan', 'LastUserSeek', 'LastUserUpdate', 'ObjectId', 'RowCount', 'Schema', 'SqlInstance', 'SystemLookup', 'SystemScans', 'SystemSeeks', 'SystemUpdates', 'Table', 'TypeDesc', 'UserLookups', 'UserScans', 'UserSeeks', 'UserUpdates')

        $results = Find-DbaDbUnusedIndex -SqlInstance $global:instance2 -Database $dbName -IgnoreUptime -Seeks 10 -Scans 10 -Lookups 10
        $resultColumns = $results | Get-Member -MemberType Property | Select-Object -ExpandProperty Name

        $missingColumns = $expectedColumns | Where-Object { $_ -notin $resultColumns }
        $missingColumns | Should -BeNullOrEmpty
    }
}
