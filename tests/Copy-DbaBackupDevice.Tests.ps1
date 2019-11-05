$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'Source', 'SourceSqlCredential', 'Destination', 'DestinationSqlCredential', 'BackupDevice', 'Force', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

if (-not $env:appveyor) {
    Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
        Context "Setup" {
            BeforeAll {
                $devicename = "dbatoolsci-backupdevice"
                $backupdir = (Get-DbaDefaultPath -SqlInstance $script:instance1).Backup
                $backupfilename = "$backupdir\$devicename.bak"
                $server = Connect-DbaInstance -SqlInstance $script:instance1
                $server.Query("EXEC master.dbo.sp_addumpdevice  @devtype = N'disk', @logicalname = N'$devicename',@physicalname = N'$backupfilename'")
                $server.Query("BACKUP DATABASE master TO DISK = '$backupfilename'")
            }
            AfterAll {
                $server.Query("EXEC master.dbo.sp_dropdevice @logicalname = N'$devicename'")
                $server1 = Connect-DbaInstance -SqlInstance $script:instance2
                try {
                    $server1.Query("EXEC master.dbo.sp_dropdevice @logicalname = N'$devicename'")
                } catch {
                    # don't care
                }
            }

            $results = Copy-DbaBackupDevice -Source $script:instance1 -Destination $script:instance2 -WarningVariable warn -WarningAction SilentlyContinue
            if ($warn) {
                It "warns if it has a problem moving (issue for local to local)" {
                    $warn -match "backup device to destination" | Should Be $true
                }
            } else {
                It "should report success" {
                    $results.Status | Should Be "Successful"
                }
            }

            $results = Copy-DbaBackupDevice -Source $script:instance1 -Destination $script:instance2
            It "Should say skipped" {
                $results.Status -ne "Successful" | Should be $true
            }
        }
    }
}