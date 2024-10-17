param($ModuleName = 'dbatools')

Describe "Test-DbaIdentityUsage" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Test-DbaIdentityUsage
        }
        It "Should have SqlInstance parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Not -Mandatory
        }
        It "Should have SqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Not -Mandatory
        }
        It "Should have Database parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type Object[] -Not -Mandatory
        }
        It "Should have ExcludeDatabase parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeDatabase -Type Object[] -Not -Mandatory
        }
        It "Should have Threshold parameter" {
            $CommandUnderTest | Should -HaveParameter Threshold -Type Int32 -Not -Mandatory
        }
        It "Should have ExcludeSystem parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeSystem -Type Switch -Not -Mandatory
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Not -Mandatory
        }
    }

    Context "Verify Test Identity Usage on TinyInt" {
        BeforeAll {
            $table = "TestTable_$(Get-random)"
            $tableDDL = "CREATE TABLE $table (testId TINYINT IDENTITY(1,1),testData DATETIME2 DEFAULT getdate() )"
            Invoke-DbaQuery -SqlInstance $env:instance1 -Query $tableDDL -database TempDb

            $insertSql = "INSERT INTO $table (testData) DEFAULT VALUES"
            1..128 | ForEach-Object {
                Invoke-DbaQuery -SqlInstance $env:instance1 -Query $insertSql -database TempDb
            }
        }
        AfterAll {
            $cleanup = "Drop table $table"
            Invoke-DbaQuery -SqlInstance $env:instance1 -Query $cleanup -database TempDb
        }

        It "Identity column should have 128 uses" {
            $results = Test-DbaIdentityUsage -SqlInstance $env:instance1 -Database TempDb | Where-Object {$_.Table -eq $table}
            $results.NumberOfUses | Should -Be 128
        }
        It "TinyInt identity column with 128 rows inserted should be 50.20% full" {
            $results = Test-DbaIdentityUsage -SqlInstance $env:instance1 -Database TempDb | Where-Object {$_.Table -eq $table}
            $results.PercentUsed | Should -Be 50.20
        }

        It "Identity column should have 255 uses after inserting 127 more rows" {
            $insertSql = "INSERT INTO $table (testData) DEFAULT VALUES"
            1..127 | ForEach-Object {
                Invoke-DbaQuery -SqlInstance $env:instance1 -Query $insertSql -database TempDb
            }
            $results = Test-DbaIdentityUsage -SqlInstance $env:instance1 -Database TempDb | Where-Object {$_.Table -eq $table}
            $results.NumberOfUses | Should -Be 255
        }
        It "TinyInt with 255 rows should be 100% full" {
            $results = Test-DbaIdentityUsage -SqlInstance $env:instance1 -Database TempDb | Where-Object {$_.Table -eq $table}
            $results.PercentUsed | Should -Be 100
        }
    }

    Context "Verify Test Identity Usage with increment of 5" {
        BeforeAll {
            $table = "TestTable_$(Get-random)"
            $tableDDL = "CREATE TABLE $table (testId tinyint IDENTITY(0,5),testData DATETIME2 DEFAULT getdate() )"
            Invoke-DbaQuery -SqlInstance $env:instance1 -Query $tableDDL -database TempDb

            $insertSql = "INSERT INTO $table (testData) DEFAULT VALUES"
            1..25 | ForEach-Object {
                Invoke-DbaQuery -SqlInstance $env:instance1 -Query $insertSql -database TempDb
            }
        }
        AfterAll {
            $cleanup = "Drop table $table"
            Invoke-DbaQuery -SqlInstance $env:instance1 -Query $cleanup -database TempDb
        }

        It "Identity column should have 24 uses" {
            $results = Test-DbaIdentityUsage -SqlInstance $env:instance1 -Database TempDb | Where-Object {$_.Table -eq $table}
            $results.NumberOfUses | Should -Be 24
        }
        It "TinyInt identity column with 25 rows using increment of 5 should be 47.06% full" {
            $results = Test-DbaIdentityUsage -SqlInstance $env:instance1 -Database TempDb | Where-Object {$_.Table -eq $table}
            $results.PercentUsed | Should -Be 47.06
        }
    }
}
