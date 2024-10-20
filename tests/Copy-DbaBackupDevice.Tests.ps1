param($ModuleName = 'dbatools')

Describe "Copy-DbaBackupDevice" {
    BeforeDiscovery {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $command = Get-Command Copy-DbaBackupDevice
        }
        $parms = @(
            'Source',
            'SourceSqlCredential',
            'Destination',
            'DestinationSqlCredential',
            'BackupDevice',
            'Force',
            'EnableException',
            'WhatIf',
            'Confirm'
        )
        It "Has required parameter: <_>" -ForEach $parms {
            $command | Should -HaveParameter $PSItem
        }
    }

    Context "Integration Tests" -Tag "IntegrationTests" {
        BeforeAll {
            $devicename = "dbatoolsci-backupdevice"
            $backupdir = (Get-DbaDefaultPath -SqlInstance $global:instance1).Backup
            $backupfilename = "$backupdir\$devicename.bak"
            $server = Connect-DbaInstance -SqlInstance $global:instance1
            $server.Query("EXEC master.dbo.sp_addumpdevice  @devtype = N'disk', @logicalname = N'$devicename',@physicalname = N'$backupfilename'")
            $server.Query("BACKUP DATABASE master TO DISK = '$backupfilename'")
        }

        AfterAll {
            $server.Query("EXEC master.dbo.sp_dropdevice @logicalname = N'$devicename'")
            $server1 = Connect-DbaInstance -SqlInstance $global:instance2
            try {
                $server1.Query("EXEC master.dbo.sp_dropdevice @logicalname = N'$devicename'")
            } catch {
                # don't care
            }
            Get-ChildItem -Path $backupfilename | Remove-Item
        }

        It "Should warn if it has a problem moving (issue for local to local)" {
            $warn = $null
            $results = Copy-DbaBackupDevice -Source $global:instance1 -Destination $global:instance2 -WarningVariable warn -WarningAction SilentlyContinue 3> $null
            if ($warn) {
                $warn | Should -Match "backup device to destination"
            } else {
                $results.Status | Should -Be "Successful"
            }
        }

        It "Should say skipped when copying again" {
            $results = Copy-DbaBackupDevice -Source $global:instance1 -Destination $global:instance2
            $results.Status | Should -Not -Be "Successful"
        }
    }
}
