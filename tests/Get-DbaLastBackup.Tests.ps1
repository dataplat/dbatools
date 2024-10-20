param($ModuleName = 'dbatools')

Describe "Get-DbaLastBackup Unit Tests" -Tag 'UnitTests' {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $Command = Get-Command Get-DbaLastBackup
        }
        $params = @(
            "SqlInstance",
            "SqlCredential",
            "Database",
            "ExcludeDatabase",
            "EnableException"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $Command | Should -HaveParameter $PSItem
        }
    }
}

Describe "Get-DbaLastBackup Integration Tests" -Tag "IntegrationTests" {
    BeforeDiscovery {
        $SkipAzureTest = [Environment]::GetEnvironmentVariable('azuredbpasswd') -ne "failstoooften"
    }

    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $global:instance2
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
        $null = Get-DbaDatabase -SqlInstance $global:instance2 -Database $dbname | Remove-DbaDatabase -Confirm:$false
        Remove-Item -Path $backupdir -Recurse -Force -ErrorAction SilentlyContinue
    }

    Context "Get null history for database" {
        It "doesn't have any values for last backups because none exist yet" {
            $results = Get-DbaLastBackup -SqlInstance $global:instance2 -Database $dbname
            $results.LastFullBackup | Should -BeNullOrEmpty
            $results.LastDiffBackup | Should -BeNullOrEmpty
            $results.LastLogBackup  | Should -BeNullOrEmpty
        }
    }

    Context "Get last history for single database" {
        It "returns a date within the proper range" {
            $yesterday = (Get-Date).AddDays(-1)
            $null = Get-DbaDatabase -SqlInstance $global:instance2 -Database $dbname | Backup-DbaDatabase -BackupDirectory $backupdir
            $null = Get-DbaDatabase -SqlInstance $global:instance2 -Database $dbname | Backup-DbaDatabase -BackupDirectory $backupdir -Type Differential
            $null = Get-DbaDatabase -SqlInstance $global:instance2 -Database $dbname | Backup-DbaDatabase -BackupDirectory $backupdir -Type Log
            $results = Get-DbaLastBackup -SqlInstance $global:instance2 -Database $dbname
            [datetime]$results.LastFullBackup | Should -BeGreaterThan $yesterday
            [datetime]$results.LastDiffBackup | Should -BeGreaterThan $yesterday
            [datetime]$results.LastLogBackup  | Should -BeGreaterThan $yesterday
        }
    }

    Context "Get last history for all databases" {
        It "returns more than 3 databases" {
            $results = Get-DbaLastBackup -SqlInstance $global:instance2
            $results.count | Should -BeGreaterThan 3
            $results.Database | Should -Contain $dbname
        }
    }

    Context "Get last history for one split database" {
        It "supports multi-file backups" {
            $null = Backup-DbaDatabase -SqlInstance $global:instance2 -Database $dbname -FileCount 4
            $results = Get-DbaLastBackup -SqlInstance $global:instance2 -Database $dbname | Select-Object -First 1
            $results.LastFullBackup | Should -BeOfType [DbaDateTime]
        }
    }

    Context "Filter backups" {
        It "by 'is_copy_only'" {
            $null = Backup-DbaDatabase -SqlInstance $global:instance2 -Database $dbname -BackupDirectory $backupdir -Type Full -CopyOnly
            $null = Backup-DbaDatabase -SqlInstance $global:instance2 -Database $dbname -BackupDirectory $backupdir -Type Log -CopyOnly

            $results = Get-DbaLastBackup -SqlInstance $global:instance2
            $copyOnlyFullBackup = ($results | Where-Object { $_.Database -eq $dbname -and $_.LastFullBackupIsCopyOnly -eq $true })
            $copyOnlyLogBackup = ($results | Where-Object { $_.Database -eq $dbname -and $_.LastLogBackupIsCopyOnly -eq $true })

            $copyOnlyFullBackup.Database | Should -Be $dbname
            $copyOnlyLogBackup.Database  | Should -Be $dbname

            $null = Backup-DbaDatabase -SqlInstance $global:instance2 -Database $dbname -BackupDirectory $backupdir -Type Full
            $null = Backup-DbaDatabase -SqlInstance $global:instance2 -Database $dbname -BackupDirectory $backupdir -Type Log

            $results = Get-DbaLastBackup -SqlInstance $global:instance2 -Database $dbname

            $results.LastFullBackupIsCopyOnly | Should -Be $false
            $results.LastLogBackupIsCopyOnly  | Should -Be $false
        }
    }
}
