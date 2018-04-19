$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    <#
    Context "Properly restores a database on the local drive using Path" {
        $results = Backup-DbaDatabase -SqlInstance $script:instance1 -BackupDirectory C:\temp\backups
        It "Should return a database name, specifically master" {
            ($results.DatabaseName -contains 'master') | Should Be $true
        }
        It "Should return successful restore" {
            $results.ForEach{ $_.BackupComplete | Should Be $true }
        }
    }
    #>
    BeforeAll {
        $DestBackupDir = 'C:\Temp\backups'
        $random = Get-Random
        $DestDbRandom = "dbatools_ci_backupdbadatabase$random"
        if (-Not(Test-Path $DestBackupDir)) {
            New-Item -Type Container -Path $DestBackupDir
        }
        Get-DbaDatabase -SqlInstance $script:instance1 -Database "dbatoolsci_singlerestore" | Remove-DbaDatabase -Confirm:$false
        Get-DbaDatabase -SqlInstance $script:instance2 -Database $DestDbRandom | Remove-DbaDatabase -Confirm:$false
    }
    AfterAll {
        Get-DbaDatabase -SqlInstance $script:instance1 -Database "dbatoolsci_singlerestore" | Remove-DbaDatabase -Confirm:$false
        Get-DbaDatabase -SqlInstance $script:instance2 -Database $DestDbRandom | Remove-DbaDatabase -Confirm:$false
        if (Test-Path $DestBackupDir) {
            Remove-Item "$DestBackupDir\*" -Force -Recurse
        }
    }
    Context "Should not backup if database and exclude match" {
        $results = Backup-DbaDatabase -SqlInstance $script:instance1 -BackupDirectory $DestBackupDir -Database master -Exclude master
        It "Should not return object" {
            $results | Should Be $null
        }
    }

    Context "Database should backup 1 database" {
        $results = Backup-DbaDatabase -SqlInstance $script:instance1 -BackupDirectory $DestBackupDir -Database master
        It "Database backup object count should be 1" {
            $results.DatabaseName.Count | Should Be 1
            $results.BackupComplete | Should Be $true
        }
    }

    Context "Database should backup 2 databases" {
        $results = Backup-DbaDatabase -SqlInstance $script:instance1 -BackupDirectory $DestBackupDir -Database master, msdb
        It "Database backup object count should be 2" {
            $results.DatabaseName.Count | Should Be 2
            $results.BackupComplete | Should Be @($true, $true)
        }
    }

    Context "Should take path and filename" {
        $results = Backup-DbaDatabase -SqlInstance $script:instance1 -BackupDirectory $DestBackupDir -Database master -BackupFileName 'PesterTest.bak'
        It "Should report it has backed up to the path with the corrrect name"{
            $results.Fullname | Should BeLike "$DestBackupDir*PesterTest.bak"
        }
        It "Should have backed up to the path with the corrrect name"{
            Test-Path "$DestBackupDir\PesterTest.bak" | Should Be $true
        }
    }

    Context "Should Backup to default path if none specified" {
        $results = Backup-DbaDatabase -SqlInstance $script:instance1 -Database master -BackupFileName 'PesterTest.bak'
        $DefaultPath = (Get-DbaDefaultPath -SqlInstance $script:instance1).Backup
        It "Should report it has backed up to the path with the corrrect name"{
            $results.Fullname | Should BeLike "$DefaultPath*PesterTest.bak"
        }
        It "Should have backed up to the path with the corrrect name"{
            Test-Path "$DefaultPath\PesterTest.bak" | Should Be $true
        }
    }
    if ($env:APPVEYOR -eq 'True') {
        #This test doesn't play nice on domain joined machines that can't see their home domain, so only run on Appyveyor
        Context " backup to a write only folder with ignore filechecks" {
            $ReadOnlyFolder = "c:\temp\WriteOnly"
            New-Item -ItemType Directory -Path $ReadOnlyFolder
            $acl = Get-Acl $ReadOnlyFolder
            $perm = 'Everyone', 'Read', 'ContainerInherit, ObjectInherit', 'None', 'Deny'
            $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule $perm
            $acl.AddAccessRule($accessRule)
            $acl | Set-Acl -Path $ReadOnlyFolder
            It "Should fail without the switch" {
                $results =  Backup-DbaDatabase -SqlInstance $script:instance1 -Database master -BackupDirectory $ReadOnlyFolder -ErrorVariable backuperrvar
                ($null -eq $backuperrvar) | Should Be $false
                ($null -eq $results) | Should Be $false
            }
            It "Should succeed with the switch" {
                $results =  Backup-DbaDatabase -SqlInstance $script:instance1 -Database master -BackupDirectory $ReadOnlyFolder -ErrorVariable backuperrvar
                ($null -eq $backuperrvar) | Should Be $True
                ($null -eq $results) | Should Be $True
            }
        }
    }
    Context "Backup can pipe to restore" {
        $null = Restore-DbaDatabase -SqlServer $script:instance1 -Path $script:appveyorlabrepo\singlerestore\singlerestore.bak -DatabaseName "dbatoolsci_singlerestore"
        $results = Backup-DbaDatabase -SqlInstance $script:instance1 -BackupDirectory $DestBackupDir -Database "dbatoolsci_singlerestore" | Restore-DbaDatabase -SqlInstance $script:instance2 -DatabaseName $DestDbRandom -TrustDbBackupHistory -ReplaceDbNameInFile
        It "Should return successful restore" {
            $results.RestoreComplete | Should Be $true
        }
    }
}