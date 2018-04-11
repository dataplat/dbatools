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

    Context "Backup can pipe to restore" {
        $null = Restore-DbaDatabase -SqlServer $script:instance1 -Path $script:appveyorlabrepo\singlerestore\singlerestore.bak -DatabaseName "dbatoolsci_singlerestore"
        $results = Backup-DbaDatabase -SqlInstance $script:instance1 -BackupDirectory $DestBackupDir -Database "dbatoolsci_singlerestore" | Restore-DbaDatabase -SqlInstance $script:instance2 -DatabaseName $DestDbRandom -TrustDbBackupHistory -ReplaceDbNameInFile
        It "Should return successful restore" {
            $results.RestoreComplete | Should Be $true
        }
    }
}