param($ModuleName = 'dbatools')

Describe "Copy-DbaBackupDevice" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Copy-DbaBackupDevice
        }

        It "has all the required parameters" {
            $params = @(
                "Source",
                "SourceSqlCredential",
                "Destination",
                "DestinationSqlCredential",
                "BackupDevice",
                "Force",
                "EnableException"
            )
            It "has the required parameter: <_>" -ForEach $params {
                $CommandUnderTest | Should -HaveParameter $PSItem
            }
        }
    }

    Context "Integration Tests" -Skip:($null -ne $env:appveyor) {
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

        It "Should copy the backup device with a warning" {
            $results = Copy-DbaBackupDevice -Source $global:instance1 -Destination $global:instance2 -WarningVariable warn -WarningAction SilentlyContinue
            $warn | Should -Match "backup device to destination"
        }

        It "Should report success when copying the backup device" {
            $results = Copy-DbaBackupDevice -Source $global:instance1 -Destination $global:instance2 -WarningAction SilentlyContinue
            $results.Status | Should -Be "Successful"
        }

        It "Should skip copying when the backup device already exists" {
            $results = Copy-DbaBackupDevice -Source $global:instance1 -Destination $global:instance2
            $results.Status | Should -Not -Be "Successful"
        }
    }
}
