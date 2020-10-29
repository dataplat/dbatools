$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        It "Should only contain our specific parameters" {
            [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
            [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'ExcludeDatabase', 'EnableException'
            $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should -Be 0
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $script:instance2
        $random = Get-Random
        $dbname = "dbatoolsci_getlastbackup$random"
        $server.Query("CREATE DATABASE $dbname")
        $server.Query("ALTER DATABASE $dbname SET RECOVERY FULL WITH NO_WAIT")
        $backupdir = Join-Path $server.BackupDirectory $dbname
        if (-not (Test-Path $backupdir -PathType Container)) {
            $null = New-Item -Path $backupdir -ItemType Container
        }
    }

    AfterAll {
        $null = Get-DbaDatabase -SqlInstance $script:instance2 -Database $dbname | Remove-DbaDatabase -Confirm:$false
        Remove-Item -Path $backupdir -Recurse -Force -ErrorAction SilentlyContinue
    }

    Context "Get null history for database" {
        It "doesn't have any values for last backups because none exist yet" {
            $results = Get-DbaLastBackup -SqlInstance $script:instance2 -Database $dbname
            $results.LastFullBackup | Should -Be $null
            $results.LastDiffBackup | Should -Be $null
            $results.LastLogBackup  | Should -Be $null
        }
    }

    Context "Get last history for single database" {
        It "returns a date within the proper range" {
            $yesterday = (Get-Date).AddDays(-1)
            $null = Get-DbaDatabase -SqlInstance $script:instance2 -Database $dbname | Backup-DbaDatabase -BackupDirectory $backupdir
            $null = Get-DbaDatabase -SqlInstance $script:instance2 -Database $dbname | Backup-DbaDatabase -BackupDirectory $backupdir -Type Differential
            $null = Get-DbaDatabase -SqlInstance $script:instance2 -Database $dbname | Backup-DbaDatabase -BackupDirectory $backupdir -Type Log
            $results = Get-DbaLastBackup -SqlInstance $script:instance2 -Database $dbname
            [datetime]$results.LastFullBackup -gt $yesterday    | Should -Be $true
            [datetime]$results.LastDiffBackup -gt $yesterday    | Should -Be $true
            [datetime]$results.LastLogBackup -gt $yesterday     | Should -Be $true
        }
    }

    Context "Get last history for all databases" {
        It "returns more than 3 databases" {
            $results = Get-DbaLastBackup -SqlInstance $script:instance2
            $results.count -gt 3                | Should -Be $true
            $results.Database -contains $dbname | Should -Be $true
        }
    }

    Context "Get last history for one split database" {
        It "supports multi-file backups" {
            $null = Backup-DbaDatabase -SqlInstance $script:instance2 -Database $dbname -FileCount 4
            $results = Get-DbaLastBackup -SqlInstance $script:instance2 -Database $dbname | Select-Object -First 1
            $results.LastFullBackup.GetType().Name | Should -Be "DbaDateTime"
        }
    }

    Context "Filter backups" {
        It "by 'is_copy_only'" {
            $null = Backup-DbaDatabase -SqlInstance $script:instance2 -Database $dbname -BackupDirectory $backupdir -Type Full -CopyOnly
            $null = Backup-DbaDatabase -SqlInstance $script:instance2 -Database $dbname -BackupDirectory $backupdir -Type Log -CopyOnly

            $results = Get-DbaLastBackup -SqlInstance $script:instance2
            $copyOnlyFullBackup = ($results | Where-Object { $_.Database -eq $dbname -and $_.LastFullBackupIsCopyOnly -eq $true })
            $copyOnlyLogBackup = ($results | Where-Object { $_.Database -eq $dbname -and $_.LastLogBackupIsCopyOnly -eq $true })

            $copyOnlyFullBackup.Database   | Should -Be $dbname
            $copyOnlyLogBackup.Database    | Should -Be $dbname


            $null = Backup-DbaDatabase -SqlInstance $script:instance2 -Database $dbname -BackupDirectory $backupdir -Type Full
            $null = Backup-DbaDatabase -SqlInstance $script:instance2 -Database $dbname -BackupDirectory $backupdir -Type Log

            $results = Get-DbaLastBackup -SqlInstance $script:instance2 -Database $dbname

            $results.LastFullBackupIsCopyOnly   | Should -Be $false
            $results.LastLogBackupIsCopyOnly    | Should -Be $false
        }
    }
}