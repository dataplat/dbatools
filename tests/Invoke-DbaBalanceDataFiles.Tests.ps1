param($ModuleName = 'dbatools')

Describe "Invoke-DbaBalanceDataFiles" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Invoke-DbaBalanceDataFiles
        }
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "Table",
                "RebuildOffline",
                "EnableException",
                "Force"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
        }
    }
}

Describe "Invoke-DbaBalanceDataFiles Integration Tests" -Tag "IntegrationTests" {
    BeforeDiscovery {
        . "$PSScriptRoot\constants.ps1"
    }

    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $global:instance2
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
