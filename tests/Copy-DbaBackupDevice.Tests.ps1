#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Copy-DbaBackupDevice",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
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
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Explain what needs to be set up for the test:
        # A backup device is a logical name plus a physical file. The command copies both, so the
        # source needs a device whose physical file really exists - the file is what the BITS
        # transfer moves. The device is created in the source instance's own default backup
        # directory so the physical file is local to that instance, and master is backed up to it
        # to bring the file into existence.

        # The command refuses to run when the module-scope $script:isWindows flag is not true. That
        # flag is set while dbatools.psm1 executes, but a Pester run reaches the module with the
        # flag unset, so every leg below would take the refusal branch and assert nothing. Pin it
        # to the real platform value for the duration of the suite and put the original back in
        # AfterAll. The refusal branch itself is covered by its own Context, which flips the same
        # flag the other way - the established idiom for this guard.
        $originalIsWindows = InModuleScope -ModuleName dbatools -ScriptBlock { $script:isWindows }
        InModuleScope -ModuleName dbatools -ScriptBlock { $script:isWindows = $true }

        # Set variables. They are available in all the It blocks.
        $deviceName = "dbatoolsci-backupdevice-$(Get-Random)"
        $sourceServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy1
        $destServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy2
        $sourceBackupFile = Join-Path -Path $sourceServer.BackupDirectory -ChildPath "$deviceName.bak"
        $destBackupFile = Join-Path -Path $destServer.BackupDirectory -ChildPath "$deviceName.bak"
        $destAdminShareFile = "\\$($destServer.ComputerName)\C`$$($destBackupFile.Substring(2))"

        # Create the objects.
        $sourceServer.Query("EXEC master.dbo.sp_addumpdevice @devtype = N'disk', @logicalname = N'$deviceName', @physicalname = N'$sourceBackupFile'")
        $sourceServer.Query("BACKUP DATABASE master TO DISK = '$sourceBackupFile' WITH INIT")

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup all created objects.
        $sourceServer.Query("EXEC master.dbo.sp_dropdevice @logicalname = N'$deviceName'")
        $destServer.BackupDevices.Refresh()
        if ($destServer.BackupDevices.Name -contains $deviceName) {
            $destServer.Query("EXEC master.dbo.sp_dropdevice @logicalname = N'$deviceName'")
        }
        Remove-Item -Path "\\$($sourceServer.ComputerName)\C`$$($sourceBackupFile.Substring(2))" -ErrorAction SilentlyContinue
        Remove-Item -Path $destAdminShareFile -ErrorAction SilentlyContinue

        $splatRestorePlatform = @{
            ModuleName  = "dbatools"
            Parameters  = @{ OriginalValue = $originalIsWindows }
            ScriptBlock = { $script:isWindows = $OriginalValue }
        }
        InModuleScope @splatRestorePlatform

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When previewing the copy with WhatIf" {
        BeforeAll {
            $splatWhatIf = @{
                Source          = $TestConfig.InstanceCopy1
                Destination     = $TestConfig.InstanceCopy2
                BackupDevice    = $deviceName
                WhatIf          = $true
                WarningVariable = "whatIfWarning"
                WarningAction   = "SilentlyContinue"
            }
            $whatIfResults = Copy-DbaBackupDevice @splatWhatIf
            $destServer.BackupDevices.Refresh()
        }

        It "Should emit no result objects because every status is gated by ShouldProcess" {
            @($whatIfResults).Count | Should -Be 0
        }

        It "Should not create the backup device on the destination" {
            $destServer.BackupDevices.Name | Should -Not -Contain $deviceName
        }

        It "Should not transfer the physical backup file to the destination" {
            Test-DbaPath -SqlInstance $destServer -Path $destBackupFile | Should -BeFalse
        }
    }

    Context "When copying backup device between instances" {
        BeforeAll {
            $splatCopy = @{
                Source          = $TestConfig.InstanceCopy1
                Destination     = $TestConfig.InstanceCopy2
                BackupDevice    = $deviceName
                WarningVariable = "copyWarning"
                WarningAction   = "SilentlyContinue"
            }
            $copyResults = Copy-DbaBackupDevice @splatCopy
            $destServer.BackupDevices.Refresh()
        }

        It "Should report the device as copied" {
            $copyResults.Status | Should -Be "Successful"
            $copyResults.Name | Should -Be $deviceName
            $copyResults.Type | Should -Be "Backup Device"
        }

        It "Should create the backup device on the destination" {
            $destServer.BackupDevices.Name | Should -Contain $deviceName
        }

        It "Should transfer the physical backup file to the destination" {
            Test-DbaPath -SqlInstance $destServer -Path $destBackupFile | Should -BeTrue
        }

        It "Should skip copying when the device already exists and Force is not used" {
            $splatSkip = @{
                Source       = $TestConfig.InstanceCopy1
                Destination  = $TestConfig.InstanceCopy2
                BackupDevice = $deviceName
            }
            $skipResults = Copy-DbaBackupDevice @splatSkip
            $skipResults.Status | Should -Be "Skipped"
            $skipResults.Notes | Should -Be "Already exists on destination"
        }
    }

    Context "When the host is not Windows" {
        It "Should warn and do nothing" {
            # Pinned by flipping the module-scope platform flag rather than by mocking the
            # connection, and restored in a finally so it cannot leak into the other contexts.
            InModuleScope -ModuleName dbatools -ScriptBlock {
                $savedIsWindows = $script:isWindows
                try {
                    $script:isWindows = $false
                    $splatNonWindows = @{
                        Source          = "dbatoolsci-src"
                        Destination     = "dbatoolsci-dst"
                        WarningVariable = "nonWindowsWarning"
                        WarningAction   = "SilentlyContinue"
                    }
                    $nonWindowsResults = @(Copy-DbaBackupDevice @splatNonWindows)
                    $nonWindowsResults.Count | Should -Be 0

                    # strip the bracketed [timestamp]/[function] prefix added by Write-Message
                    $payloads = $nonWindowsWarning | ForEach-Object { $PSItem.Message -replace "^(\[[^\]]*\]\s*)+", "" }
                    $payloads | Should -Contain "Copy-DbaBackupDevice does not support Linux yet though it looks doable"
                } finally {
                    $script:isWindows = $savedIsWindows
                }
            }
        }
    }
}
