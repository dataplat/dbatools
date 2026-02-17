#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Invoke-DbaAdvancedRestore",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "BackupHistory",
                "SqlInstance",
                "SqlCredential",
                "OutputScriptOnly",
                "VerifyOnly",
                "RestoreTime",
                "StandbyDirectory",
                "NoRecovery",
                "MaxTransferSize",
                "BlockSize",
                "BufferCount",
                "Continue",
                "StorageCredential",
                "WithReplace",
                "KeepReplication",
                "KeepCDC",
                "PageRestore",
                "ExecuteAs",
                "StopBefore",
                "StopMark",
                "StopAfterDate",
                "Checksum",
                "Restart",
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

        # For all the backups that we want to clean up after the test, we create a directory that we can delete at the end.
        $backupPath = "$($TestConfig.Temp)\$CommandName-$(Get-Random)"
        $null = New-Item -Path $backupPath -ItemType Directory

        $testDbName = "dbatoolsci_advrestore_$(Get-Random)"
        $sourceDbName = "dbatoolsci_advrsrc_$(Get-Random)"

        # Create a source database and back it up
        $null = New-DbaDatabase -SqlInstance $TestConfig.instance2 -Name $sourceDbName
        $splatBackup = @{
            SqlInstance     = $TestConfig.instance2
            Database        = $sourceDbName
            BackupDirectory = $backupPath
            Type            = "Full"
        }
        $null = Backup-DbaDatabase @splatBackup

        # Build the restore pipeline: Get backup info, format to rename database and files, test, then restore
        $backupInfo = Get-DbaBackupInformation -SqlInstance $TestConfig.instance2 -Path $backupPath

        $splatFormat = @{
            ReplaceDatabaseName = $testDbName
            ReplaceDbNameInFile = $true
        }
        $formattedInfo = $backupInfo | Format-DbaBackupInformation @splatFormat

        $testedInfo = $formattedInfo | Test-DbaBackupInformation -SqlInstance $TestConfig.instance2

        # Perform the actual restore using Invoke-DbaAdvancedRestore
        $splatRestore = @{
            SqlInstance = $TestConfig.instance2
            WithReplace = $true
        }
        $global:dbatoolsciOutput = $testedInfo | Invoke-DbaAdvancedRestore @splatRestore

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup all created objects.
        Remove-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $testDbName, $sourceDbName -Confirm:$false -ErrorAction SilentlyContinue

        # Remove the backup directory.
        Remove-Item -Path $backupPath -Recurse -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When restoring a database through the backup pipeline" {
        It "Should complete the restore successfully" {
            $global:dbatoolsciOutput | Should -Not -BeNullOrEmpty
            $global:dbatoolsciOutput[0].RestoreComplete | Should -BeTrue
        }

        It "Should restore to the correct database name" {
            $global:dbatoolsciOutput[0].Database | Should -Be $testDbName
        }

        It "Should show WithReplace was used" {
            $global:dbatoolsciOutput[0].WithReplace | Should -BeTrue
        }
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return a PSCustomObject" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [PSCustomObject]
        }

        It "Should have the expected properties" {
            $expectedProperties = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Database",
                "DatabaseName",
                "DatabaseOwner",
                "Owner",
                "NoRecovery",
                "WithReplace",
                "KeepReplication",
                "RestoreComplete",
                "BackupFilesCount",
                "RestoredFilesCount",
                "BackupSizeMB",
                "CompressedBackupSizeMB",
                "BackupFile",
                "RestoredFile",
                "RestoredFileFull",
                "RestoreDirectory",
                "BackupSize",
                "CompressedBackupSize",
                "BackupStartTime",
                "BackupEndTime",
                "RestoreTargetTime",
                "Script",
                "BackupFileRaw",
                "FileRestoreTime",
                "DatabaseRestoreTime",
                "ExitError"
            )
            $actualProperties = $global:dbatoolsciOutput[0].PSObject.Properties.Name
            Compare-Object -ReferenceObject $expectedProperties -DifferenceObject $actualProperties | Should -BeNullOrEmpty
        }

        It "Should have the correct default display columns" {
            $expectedColumns = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "BackupFile",
                "BackupFilesCount",
                "BackupSize",
                "CompressedBackupSize",
                "Database",
                "Owner",
                "DatabaseRestoreTime",
                "FileRestoreTime",
                "NoRecovery",
                "RestoreComplete",
                "RestoredFile",
                "RestoredFilesCount",
                "Script",
                "RestoreDirectory",
                "WithReplace"
            )
            $defaultColumns = $global:dbatoolsciOutput[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            Compare-Object -ReferenceObject $expectedColumns -DifferenceObject $defaultColumns | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "PSCustomObject"
        }
    }
}