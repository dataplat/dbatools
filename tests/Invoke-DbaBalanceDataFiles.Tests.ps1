param($ModuleName = 'dbatools')

Describe "Invoke-DbaBalanceDataFiles" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Invoke-DbaBalanceDataFiles
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
        It "Should have Table parameter" {
            $CommandUnderTest | Should -HaveParameter Table -Type Object[] -Not -Mandatory
        }
        It "Should have RebuildOffline parameter" {
            $CommandUnderTest | Should -HaveParameter RebuildOffline -Type Switch -Not -Mandatory
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Not -Mandatory
        }
        It "Should have Force parameter" {
            $CommandUnderTest | Should -HaveParameter Force -Type Switch -Not -Mandatory
        }
    }
}

Describe "Invoke-DbaBalanceDataFiles Integration Tests" -Tag "IntegrationTests" {
    BeforeDiscovery {
        . "$PSScriptRoot\constants.ps1"
    }

    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $env:instance2
        $defaultdata = (Get-DbaDefaultPath -SqlInstance $server).Data
        $dbname = "dbatoolscsi_balance"

        $server.Query("CREATE DATABASE [$dbname]")
        $server.Databases.Refresh()
        $db = Get-DbaDatabase -SqlInstance $server -Database $dbname

        $db.Query("CREATE TABLE table1 (ID1 INT IDENTITY PRIMARY KEY, Name1 char(100))")
        $db.Query("CREATE TABLE table2 (ID1 INT IDENTITY PRIMARY KEY, Name2 char(100))")

        $sqlvalues = New-Object System.Collections.ArrayList
        1 .. 1000 | ForEach-Object { $null = $sqlvalues.Add("('some value')") }

        $db.Query("insert into table1 (Name1) Values $($sqlvalues -join ',')")
        $db.Query("insert into table1 (Name1) Values $($sqlvalues -join ',')")
        $db.Query("insert into table1 (Name1) Values $($sqlvalues -join ',')")
        $db.Query("insert into table1 (Name1) Values $($sqlvalues -join ',')")
        $db.Query("insert into table1 (Name1) Values $($sqlvalues -join ',')")
        $db.Query("insert into table2 (Name2) Values $($sqlvalues -join ',')")
        $db.Query("insert into table2 (Name2) Values $($sqlvalues -join ',')")
        $db.Query("insert into table2 (Name2) Values $($sqlvalues -join ',')")
        $db.Query("insert into table2 (Name2) Values $($sqlvalues -join ',')")
        $db.Query("insert into table2 (Name2) Values $($sqlvalues -join ',')")

        $db.Query("ALTER DATABASE $dbname ADD FILE (NAME = secondfile, FILENAME = '$defaultdata\$dbname-secondaryfg.ndf') TO FILEGROUP [PRIMARY]")
    }

    AfterAll {
        Remove-DbaDatabase -SqlInstance $server -Database $dbname -Confirm:$false
    }

    Context "Data is balanced among data files" {
        BeforeAll {
            $results = Invoke-DbaBalanceDataFiles -SqlInstance $server -Database $dbname -RebuildOffline -Force
            $sizeUsedBefore = $results.DataFilesStart[0].UsedSpace.Kilobyte
            $sizeUsedAfter = $results.DataFilesEnd[0].UsedSpace.Kilobyte
        }

        It "Result returns success" {
            $results.Success | Should -Be $true
        }

        It "New used space should be less" {
            $sizeUsedAfter | Should -BeLessThan $sizeUsedBefore
        }
    }
}
