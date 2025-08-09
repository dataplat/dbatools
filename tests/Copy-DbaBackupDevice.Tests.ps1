#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0"}
param(
    $ModuleName  = "dbatools",
    $CommandName = "Copy-DbaBackupDevice",
    $PSDefaultParameterValues = ($TestConfig = Get-TestConfig).Defaults
)

Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        BeforeAll {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Source",
                "SourceSqlCredential",
                "Destination",
                "DestinationSqlCredential",
                "BackupDevice",
                "Force",
                "EnableException"
            )
        }

        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

        # For all the backups that we want to clean up after the test, we create a directory that we can delete at the end.
        # Other files can be written there as well, maybe we change the name of that variable later. But for now we focus on backups.
        $backupPath = "$($TestConfig.Temp)\$CommandName-$(Get-Random)"
        $null = New-Item -Path $backupPath -ItemType Directory

        # Explain what needs to be set up for the test:
        # To test copying backup devices, we need to create a backup device on the source instance
        # and test copying it to the destination instance.

        # Set variables. They are available in all the It blocks.
        $deviceName     = "dbatoolsci-backupdevice-$(Get-Random)"
        $backupFileName = "$backupPath\$deviceName.bak"
        $sourceServer   = Connect-DbaInstance -SqlInstance $TestConfig.instance1
        $destServer     = Connect-DbaInstance -SqlInstance $TestConfig.instance2

        # Create the objects.
        $sourceServer.Query("EXEC master.dbo.sp_addumpdevice @devtype = N'disk', @logicalname = N'$deviceName', @physicalname = N'$backupFileName'")
        $sourceServer.Query("BACKUP DATABASE master TO DISK = '$backupFileName'")

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove('*-Dba*:EnableException')
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

        # Cleanup all created objects.
        $sourceServer.Query("EXEC master.dbo.sp_dropdevice @logicalname = N'$deviceName'")
        try {
            $destServer.Query("EXEC master.dbo.sp_dropdevice @logicalname = N'$deviceName'")
        } catch {
            # Device may not exist, ignore error
        }

        # Remove the backup directory.
        Remove-Item -Path $backupPath -Recurse -ErrorAction SilentlyContinue

        # As this is the last block we do not need to reset the $PSDefaultParameterValues.
    }

    Context "When copying backup device between instances" {
        It "Should copy the backup device successfully or warn about local copy" {
            $results = Copy-DbaBackupDevice -Source $TestConfig.instance1 -Destination $TestConfig.instance2 -WarningVariable WarnVar -WarningAction SilentlyContinue 3> $null

            if ($WarnVar) {
                $WarnVar | Should -Match "backup device to destination"
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
