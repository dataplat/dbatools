param($ModuleName = 'dbatools')

Describe "Test-DbaLastBackup Unit Tests" -Tag 'UnitTests' {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Test-DbaLastBackup
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Mandatory:$false
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Mandatory:$false
        }
        It "Should have Database as a parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type Object[] -Mandatory:$false
        }
        It "Should have ExcludeDatabase as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeDatabase -Type Object[] -Mandatory:$false
        }
        It "Should have Destination as a parameter" {
            $CommandUnderTest | Should -HaveParameter Destination -Type DbaInstanceParameter -Mandatory:$false
        }
        It "Should have DestinationSqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter DestinationSqlCredential -Type Object -Mandatory:$false
        }
        It "Should have DataDirectory as a parameter" {
            $CommandUnderTest | Should -HaveParameter DataDirectory -Type String -Mandatory:$false
        }
        It "Should have LogDirectory as a parameter" {
            $CommandUnderTest | Should -HaveParameter LogDirectory -Type String -Mandatory:$false
        }
        It "Should have FileStreamDirectory as a parameter" {
            $CommandUnderTest | Should -HaveParameter FileStreamDirectory -Type String -Mandatory:$false
        }
        It "Should have Prefix as a parameter" {
            $CommandUnderTest | Should -HaveParameter Prefix -Type String -Mandatory:$false
        }
        It "Should have VerifyOnly as a parameter" {
            $CommandUnderTest | Should -HaveParameter VerifyOnly -Type Switch -Mandatory:$false
        }
        It "Should have NoCheck as a parameter" {
            $CommandUnderTest | Should -HaveParameter NoCheck -Type Switch -Mandatory:$false
        }
        It "Should have NoDrop as a parameter" {
            $CommandUnderTest | Should -HaveParameter NoDrop -Type Switch -Mandatory:$false
        }
        It "Should have CopyFile as a parameter" {
            $CommandUnderTest | Should -HaveParameter CopyFile -Type Switch -Mandatory:$false
        }
        It "Should have CopyPath as a parameter" {
            $CommandUnderTest | Should -HaveParameter CopyPath -Type String -Mandatory:$false
        }
        It "Should have MaxSize as a parameter" {
            $CommandUnderTest | Should -HaveParameter MaxSize -Type Int32 -Mandatory:$false
        }
        It "Should have DeviceType as a parameter" {
            $CommandUnderTest | Should -HaveParameter DeviceType -Type String[] -Mandatory:$false
        }
        It "Should have IncludeCopyOnly as a parameter" {
            $CommandUnderTest | Should -HaveParameter IncludeCopyOnly -Type Switch -Mandatory:$false
        }
        It "Should have IgnoreLogBackup as a parameter" {
            $CommandUnderTest | Should -HaveParameter IgnoreLogBackup -Type Switch -Mandatory:$false
        }
        It "Should have AzureCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter AzureCredential -Type String -Mandatory:$false
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Microsoft.SqlServer.Management.Smo.Database[] -Mandatory:$false
        }
        It "Should have MaxTransferSize as a parameter" {
            $CommandUnderTest | Should -HaveParameter MaxTransferSize -Type Int32 -Mandatory:$false
        }
        It "Should have BufferCount as a parameter" {
            $CommandUnderTest | Should -HaveParameter BufferCount -Type Int32 -Mandatory:$false
        }
        It "Should have IgnoreDiffBackup as a parameter" {
            $CommandUnderTest | Should -HaveParameter IgnoreDiffBackup -Type Switch -Mandatory:$false
        }
        It "Should have MaxDop as a parameter" {
            $CommandUnderTest | Should -HaveParameter MaxDop -Type Int32 -Mandatory:$false
        }
        It "Should have ReuseSourceFolderStructure as a parameter" {
            $CommandUnderTest | Should -HaveParameter ReuseSourceFolderStructure -Type Switch -Mandatory:$false
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Mandatory:$false
        }
    }
}

Describe "Test-DbaLastBackup Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $random = Get-Random
        $testlastbackup = "dbatoolsci_testlastbackup$random"
        $dbs = $testlastbackup, "dbatoolsci_lildb", "dbatoolsci_testrestore", "dbatoolsci_singlerestore"

        $server = Connect-DbaInstance -SqlInstance $global:instance1
        foreach ($db in $dbs) {
            $server.Query("CREATE DATABASE $db")
            $server.Query("ALTER DATABASE $db SET RECOVERY FULL WITH NO_WAIT")
            $server.Query("CREATE TABLE [$db].[dbo].[Example] (id int identity, name nvarchar(max))")
            $server.Query("INSERT INTO [$db].[dbo].[Example] values ('sample')")
        }
    }

    AfterAll {
        # these for sure
        $dbs += "bigtestrest", "smalltestrest"
        Get-DbaDatabase -SqlInstance $global:instance1 -Database $dbs | Remove-DbaDatabase -Confirm:$false
        # those just in case test-dbalastbackup didn't cooperate
        Get-DbaDatabase -SqlInstance $global:instance1 | Where-Object Name -like 'dbatools-testrestore-dbatoolsci_*' | Remove-DbaDatabase -Confirm:$false
        # see "Restores using a specific path"
        Get-ChildItem -Path C:\Temp\dbatools-testrestore-dbatoolsci_singlerestore* | Remove-Item
    }

    Context "Setup restores and backups on the local drive for Test-DbaLastBackup" {
        BeforeAll {
            Get-DbaDatabase -SqlInstance $global:instance1 -Database $dbs | Backup-DbaDatabase -Type Microsoft.SqlServer.Management.Smo.Database
            Invoke-DbaQuery -SqlInstance $global:instance1 -Query "INSERT INTO [$testlastbackup].[dbo].[Example] values ('sample')"
            Get-DbaDatabase -SqlInstance $global:instance1 -Database $testlastbackup | Backup-DbaDatabase -Type Differential
            Invoke-DbaQuery -SqlInstance $global:instance1 -Query "INSERT INTO [$testlastbackup].[dbo].[Example] values ('sample1')"
            Get-DbaDatabase -SqlInstance $global:instance1 -Database $testlastbackup | Backup-DbaDatabase -Type Differential
            Invoke-DbaQuery -SqlInstance $global:instance1 -Query "INSERT INTO [$testlastbackup].[dbo].[Example] values ('sample2')"
            Get-DbaDatabase -SqlInstance $global:instance1 -Database $testlastbackup | Backup-DbaDatabase -Type Log
            Invoke-DbaQuery -SqlInstance $global:instance1 -Query "INSERT INTO [$testlastbackup].[dbo].[Example] values ('sample3')"
            Get-DbaDatabase -SqlInstance $global:instance1 -Database $testlastbackup | Backup-DbaDatabase -Type Log
            Invoke-DbaQuery -SqlInstance $global:instance1 -Query "INSERT INTO [$testlastbackup].[dbo].[Example] values ('sample4')"
        }
    }

    Context "Test a single database" {
        It "Should return success" {
            $results = Test-DbaLastBackup -SqlInstance $global:instance1 -Database $testlastbackup
            $results.RestoreResult | Should -Be "Success"
            $results.DbccResult | Should -Be "Success"
            $results.BackupDates | ForEach-Object { $_ | Should -BeOfType DbaDateTime }
        }
    }

    Context "Testing the whole instance" {
        It "Should be more than 3 databases" {
            $results = Test-DbaLastBackup -SqlInstance $global:instance1 -ExcludeDatabase tempdb
            $results.count | Should -BeGreaterThan 3
        }
    }

    Context "Restores using a specific path" {
        BeforeAll {
            $null = Get-DbaDatabase -SqlInstance $global:instance1 -Database "dbatoolsci_singlerestore" | Backup-DbaDatabase
            $null = Test-DbaLastBackup -SqlInstance $global:instance1 -Database "dbatoolsci_singlerestore" -DataDirectory C:\Temp -LogDirectory C:\Temp -NoDrop
            $results = Get-DbaDbFile -SqlInstance $global:instance1 -Database "dbatools-testrestore-dbatoolsci_singlerestore"
        }

        It "Should match C:\Temp" {
            'C:\Temp\dbatools-testrestore-dbatoolsci_singlerestore.mdf' | Should -BeIn $results.PhysicalName
            'C:\Temp\dbatools-testrestore-dbatoolsci_singlerestore_log.ldf' | Should -BeIn $results.PhysicalName
        }
    }

    Context "Test Ignoring Diff Backups" {
        It "Should return success and not contain a diff backup" {
            $results = Test-DbaLastBackup -SqlInstance $global:instance1 -Database $testlastbackup -IgnoreDiffBackup
            $results.RestoreResult | Should -Be "Success"
            ($results.BackupFiles | Where-Object { $_ -like '*diff*' }).count | Should -Be 0
        }
    }

    Context "Test dbsize skip and cleanup (Issue 3968)" {
        BeforeAll {
            $null = Restore-DbaDatabase -SqlInstance $global:instance1 -Database bigtestrest -Path $env:appveyorlabrepo\sql2008-backups\db1\FULL -ReplaceDbNameInFile
            Backup-DbaDatabase -SqlInstance $global:instance1 -Database bigtestrest
            $null = Restore-DbaDatabase -SqlInstance $global:instance1 -Database smalltestrest -Path $env:appveyorlabrepo\sql2008-backups\db2\FULL\SQL2008_db2_FULL_20170518_041738.bak -ReplaceDbNameInFile
            Backup-DbaDatabase -SqlInstance $global:instance1 -Database smalltestrest

            $results = Test-DbaLastBackup -SqlInstance $global:instance1 -Database bigtestrest, smalltestrest -CopyFile -CopyPath c:\temp -MaxSize 3 -Prefix testlast
            $fileresult = Get-ChildItem c:\temp | Where-Object { $_.name -like '*bigtestrest' }
        }

        It "Should have skipped bigtestrest and tested smalltestrest" {
            $results[0].RestoreResult | Should -BeLike '*exceeds the specified maximum*'
            $results[0].DbccResult | Should -Be 'Skipped'
            $results[1].RestoreResult | Should -Be 'Success'
            $results[1].DbccResult | Should -Be 'Success'
        }

        It "Should have removed the temp backup copy even if skipped" {
            $fileresult | Should -BeNullOrEmpty
        }

        AfterAll {
            Get-DbaDatabase -SqlInstance $global:instance1 -Database bigtestrest, smalltestrest | Remove-DbaDatabase -Confirm:$false
        }
    }
}
