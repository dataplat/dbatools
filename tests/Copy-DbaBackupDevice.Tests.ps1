#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0"}
param(
    $ModuleName = "dbatools",
    $PSDefaultParameterValues = ($TestConfig = Get-TestConfig).Defaults
)

Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan

Describe "Copy-DbaBackupDevice" -Tag "UnitTests" {
    Context "Parameter validation" {
        BeforeAll {
            $command = Get-Command Copy-DbaBackupDevice
            $expected = $TestConfig.CommonParameters
            $expected += @(
                "Source",
                "SourceSqlCredential", 
                "Destination",
                "DestinationSqlCredential",
                "BackupDevice",
                "Force",
                "EnableException",
                "Confirm",
                "WhatIf"
            )
        }

        It "Has parameter: <_>" -ForEach $expected {
            $command | Should -HaveParameter $PSItem
        }

        It "Should have exactly the number of expected parameters ($($expected.Count))" {
            $hasparms = $command.Parameters.Values.Name
            Compare-Object -ReferenceObject $expected -DifferenceObject $hasparms | Should -BeNullOrEmpty
        }
    }
}

if (-not $env:appveyor) {
    Describe "Copy-DbaBackupDevice" -Tag "IntegrationTests" {
        BeforeAll {
            $deviceName = "dbatoolsci-backupdevice"
            $backupDir = (Get-DbaDefaultPath -SqlInstance $TestConfig.instance1).Backup
            $backupFileName = "$backupDir\$deviceName.bak"
            $sourceServer = Connect-DbaInstance -SqlInstance $TestConfig.instance1
            $sourceServer.Query("EXEC master.dbo.sp_addumpdevice  @devtype = N'disk', @logicalname = N'$deviceName',@physicalname = N'$backupFileName'")
            $sourceServer.Query("BACKUP DATABASE master TO DISK = '$backupFileName'")
        }

        AfterAll {
            $sourceServer.Query("EXEC master.dbo.sp_dropdevice @logicalname = N'$deviceName'")
            $destServer = Connect-DbaInstance -SqlInstance $TestConfig.instance2
            try {
                $destServer.Query("EXEC master.dbo.sp_dropdevice @logicalname = N'$deviceName'")
            } catch {
                # Device may not exist, ignore error
            }
            Get-ChildItem -Path $backupFileName | Remove-Item
        }

        Context "When copying backup device between instances" {
            It "Should copy the backup device successfully or warn about local copy" {
                $results = Copy-DbaBackupDevice -Source $TestConfig.instance1 -Destination $TestConfig.instance2 -WarningVariable warning -WarningAction SilentlyContinue 3> $null
                
                if ($warning) {
                    $warning | Should -Match "backup device to destination"
                } else {
                    $results.Status | Should -Be "Successful"
                }
            }

            It "Should skip copying when device already exists" {
                $results = Copy-DbaBackupDevice -Source $TestConfig.instance1 -Destination $TestConfig.instance2
                $results.Status | Should -Not -Be "Successful"
            }
        }
    }
}
