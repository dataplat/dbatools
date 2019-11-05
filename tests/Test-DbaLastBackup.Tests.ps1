$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'ExcludeDatabase', 'Destination', 'DestinationCredential', 'DataDirectory', 'LogDirectory', 'Prefix', 'VerifyOnly', 'NoCheck', 'NoDrop', 'CopyFile', 'CopyPath', 'MaxSize', 'IncludeCopyOnly', 'IgnoreLogBackup', 'AzureCredential', 'InputObject', 'EnableException', 'DeviceType'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $dbs = $testlastbackup, "dbatoolsci_lildb", "dbatoolsci_testrestore", "dbatoolsci_singlerestore"
        $null = Get-DbaDatabase -SqlInstance $script:instance1 -Database $dbs | Remove-DbaDatabase -Confirm:$false
        $server = Connect-DbaInstance -SqlInstance $script:instance1
        $random = Get-Random
        $testlastbackup = "dbatoolsci_testlastbackup$random"
        $dbs = $testlastbackup, "dbatoolsci_lildb", "dbatoolsci_testrestore", "dbatoolsci_singlerestore"

        foreach ($db in $dbs) {
            $server.Query("CREATE DATABASE $db")
            $server.Query("ALTER DATABASE $db SET RECOVERY FULL WITH NO_WAIT")
            $server.Query("CREATE TABLE [$db].[dbo].[Example] (id int identity, name nvarchar(max))")
            $server.Query("INSERT INTO [$db].[dbo].[Example] values ('sample')")
        }

    }
    AfterAll {
        # these for sure
        Get-DbaDatabase -SqlInstance $script:instance1 -Database $dbs, "bigtestrest", "smalltestrest" | Remove-DbaDatabase -Confirm:$false
        # those just in case test-dbalastbackup didn't cooperate
        Get-DbaDatabase -SqlInstance $script:instance1 | Where-Object Name -like 'dbatools-testrestore-dbatoolsci_*' | Remove-DbaDatabase -Confirm:$false
        # see "Restores using a specific path"
        Get-ChildItem -Path C:\Temp\dbatools-testrestore-dbatoolsci_singlerestore* | Remove-Item
    }
    Context "Setup restores and backups on the local drive for Test-DbaLastBackup" {
        Get-DbaDatabase -SqlInstance $script:instance1 -Database $dbs | Backup-DbaDatabase -Type Database
        Invoke-DbaQuery -SqlInstance $script:instance1 -Query "INSERT INTO [$testlastbackup].[dbo].[Example] values ('sample')"
        Get-DbaDatabase -SqlInstance $script:instance1 -Database $testlastbackup | Backup-DbaDatabase -Type Differential
        Invoke-DbaQuery -SqlInstance $script:instance1 -Query "INSERT INTO [$testlastbackup].[dbo].[Example] values ('sample1')"
        Get-DbaDatabase -SqlInstance $script:instance1 -Database $testlastbackup | Backup-DbaDatabase -Type Differential
        Invoke-DbaQuery -SqlInstance $script:instance1 -Query "INSERT INTO [$testlastbackup].[dbo].[Example] values ('sample2')"
        Get-DbaDatabase -SqlInstance $script:instance1 -Database $testlastbackup | Backup-DbaDatabase -Type Log
        Invoke-DbaQuery -SqlInstance $script:instance1 -Query "INSERT INTO [$testlastbackup].[dbo].[Example] values ('sample3')"
        Get-DbaDatabase -SqlInstance $script:instance1 -Database $testlastbackup | Backup-DbaDatabase -Type Log
        Invoke-DbaQuery -SqlInstance $script:instance1 -Query "INSERT INTO [$testlastbackup].[dbo].[Example] values ('sample4')"
    }

    Context "Test a single database" {
        $results = Test-DbaLastBackup -SqlInstance $script:instance1 -Database $testlastbackup

        It "Should return success" {
            $results.RestoreResult | Should Be "Success"
            $results.DbccResult | Should Be "Success"
        }
    }

    Context "Testing the whole instance" {
        $results = Test-DbaLastBackup -SqlInstance $script:instance1 -ExcludeDatabase tempdb
        It "Should be more than 3 databases" {
            $results.count | Should BeGreaterThan 3
        }
    }

    Context "Restores using a specific path" {
        $null = Get-DbaDatabase -SqlInstance $script:instance1 -Database "dbatoolsci_singlerestore" | Backup-DbaDatabase
        $null = Test-DbaLastBackup -SqlInstance $script:instance1 -Database "dbatoolsci_singlerestore" -DataDirectory C:\Temp -LogDirectory C:\Temp -NoDrop
        $results = Get-DbaDbFile -SqlInstance $script:instance1 -Database "dbatools-testrestore-dbatoolsci_singlerestore"
        It "Should match C:\Temp" {
            ('C:\Temp\dbatools-testrestore-dbatoolsci_singlerestore.mdf' -in $results.PhysicalName) | Should Be $true
            ('C:\Temp\dbatools-testrestore-dbatoolsci_singlerestore_log.ldf' -in $results.PhysicalName) | Should Be $true
        }
    }

    Context "Test dbsize skip and cleanup (Issue 3968)" {
        $results1 = Restore-DbaDatabase -SqlInstance $script:instance1 -Database bigtestrest -Path $script:appveyorlabrepo\sql2008-backups\db1\FULL -ReplaceDbNameInFile
        Backup-DbaDatabase -SqlInstance $script:instance1 -Database bigtestrest
        $results1 = Restore-DbaDatabase -SqlInstance $script:instance1 -Database smalltestrest -Path $script:appveyorlabrepo\sql2008-backups\db2\FULL\SQL2008_db2_FULL_20170518_041738.bak -ReplaceDbNameInFile
        Backup-DbaDatabase -SqlInstance $script:instance1 -Database smalltestrest

        $results = Test-DbaLastBackup -SqlInstance $script:instance1 -Database bigtestrest, smalltestrest -CopyFile -CopyPath c:\temp -MaxSize 3 -Prefix testlast
        $fileresult = Get-ChildItem c:\temp | Where-Object { $_.name -like '*bigtestrest' }
        It "Should have skipped bigtestrest and tested smalltestrest" {
            $results[0].RestoreResult | Should -BeLike '*exceeds the specified maximum*'
            $results[0].DbccResult | Should -Be 'Skipped'
            $results[1].RestoreResult | Should -Be 'Success'
            $results[1].DbccResult | Should -Be 'Success'
        }

        It "Should have removed the temp backup copy even if skipped" {
            ($null -eq $fileresult) | Should -Be $true
        }

        Get-DbaDatabase -SqlInstance $script:instance1 -Database  bigtestrest, smalltestrest | Remove-DbaDatabase -confirm:$false
    }
}