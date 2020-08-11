$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'ExcludeDatabase', 'IncludeCopyOnly', 'Force', 'Since', 'RecoveryFork', 'Last', 'LastFull', 'LastDiff', 'LastLog', 'DeviceType', 'Raw', 'LastLsn', 'Type', 'EnableException', 'IncludeMirror', 'AgCheck'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $DestBackupDir = 'C:\Temp\backups'
        if (-Not (Test-Path $DestBackupDir)) {
            New-Item -ItemType Container -Path $DestBackupDir
        }
        $random = Get-Random
        $dbname = "dbatoolsci_history_$random"
        $null = Get-DbaDatabase -SqlInstance $script:instance1 -Database $dbname | Remove-DbaDatabase -Confirm:$false
        $null = Restore-DbaDatabase -SqlInstance $script:instance1 -Path $script:appveyorlabrepo\singlerestore\singlerestore.bak -DatabaseName $dbname -DestinationFilePrefix $dbname
        $db = Get-DbaDatabase -SqlInstance $script:instance1 -Database $dbname
        $db | Backup-DbaDatabase -Type Full -BackupDirectory $DestBackupDir
        $db | Backup-DbaDatabase -Type Differential -BackupDirectory $DestBackupDir
        $db | Backup-DbaDatabase -Type Log -BackupDirectory $DestBackupDir
        $db | Backup-DbaDatabase -Type Log -BackupDirectory $DestBackupDir
        $null = Get-DbaDatabase -SqlInstance $script:instance1 -Database master | Backup-DbaDatabase -Type Full
        $db | Backup-DbaDatabase -Type Full -BackupDirectory $DestBackupDir -BackupFileName CopyOnly.bak -CopyOnly
    }

    AfterAll {
        $null = Get-DbaDatabase -SqlInstance $script:instance1 -Database $dbname | Remove-DbaDatabase -Confirm:$false
    }

    Context "Get last history for single database" {
        $results = Get-DbaDbBackupHistory -SqlInstance $script:instance1 -Database $dbname -Last
        It "Should be 4 backups returned" {
            $results.count | Should Be 4
        }
        It "First backup should be a Full Backup" {
            $results[0].Type | Should be "Full"
        }
        It "Duration should be meaningful" {
            ($results[0].end - $results[0].start).TotalSeconds | Should Be $results[0].Duration.TotalSeconds
        }
        It "Last Backup Should be a log backup" {
            $results[-1].Type | Should Be "Log"
        }
    }

    Context "Get last history for all databases" {
        $results = Get-DbaDbBackupHistory -SqlInstance $script:instance1
        It "Should be more than one database" {
            ($results | Where-Object Database -match "master").Count | Should BeGreaterThan 0
        }
    }

    Context "ExcludeDatabase is honored" {
        $results = Get-DbaDbBackupHistory -SqlInstance $script:instance1 -ExcludeDatabase 'master'
        It "Should not report about excluded database master" {
            ($results | Where-Object Database -match "master").Count | Should Be 0
        }
        $results = Get-DbaDbBackupHistory -SqlInstance $script:instance1 -ExcludeDatabase 'master' -Type Full
        It "Should not report about excluded database master" {
            ($results | Where-Object Database -match "master").Count | Should Be 0
        }
        $results = Get-DbaDbBackupHistory -SqlInstance $script:instance1 -ExcludeDatabase 'master' -LastFull
        It "Should not report about excluded database master" {
            ($results | Where-Object Database -match "master").Count | Should Be 0
        }
    }

    Context "LastFull should work with multiple databases" {
        $results = Get-DbaDbBackupHistory -SqlInstance $script:instance1 -Database $dbname, master -lastfull
        It "Should return 2 records" {
            $results.count | Should Be 2
        }
    }

    Context "Testing IncludeCopyOnly with LastFull" {
        $results = Get-DbaDbBackupHistory -SqlInstance $script:instance1 -LastFull -Database $dbname
        $resultsCo = Get-DbaDbBackupHistory -SqlInstance $script:instance1 -LastFull -IncludeCopyOnly -Database $dbname
        It "Should return the CopyOnly Backup" {
            ($resultsCo.BackupSetID -ne $Results.BackupSetID) | Should Be $True
        }
    }

    Context "Testing IncludeCopyOnly with Last" {
        $resultsCo = Get-DbaDbBackupHistory -SqlInstance $script:instance1 -Last -IncludeCopyOnly -Database $dbname
        It "Should return just the CopyOnly Full Backup" {
            ($resultsCo | Measure-Object).count | Should Be 1
        }
    }

    Context "Testing TotalSize regression test for #3517" {
        It "supports large numbers" {
            $historyObject = New-Object Sqlcollaborative.Dbatools.Database.BackupHistory
            $server = connect-dbainstance $script:instance1
            $cast = $server.Query('select cast(1000000000000000 as numeric(20,0)) AS TotalSize')
            $historyObject.TotalSize = $cast.TotalSize
            ($historyObject.TotalSize.Byte) | Should -Be 1000000000000000
        }
    }
}