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
                "AzureCredential",
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

    Context "Output Validation" {
        BeforeAll {
            $backupPath = "C:\temp\dbatools_advancedrestore_test.bak"
            $testDb = "dbatoolsci_AdvancedRestore_$(Get-Random)"

            # Create a test database and backup
            $null = New-DbaDatabase -SqlInstance $TestConfig.instance1 -Name $testDb -EnableException
            $null = Backup-DbaDatabase -SqlInstance $TestConfig.instance1 -Database $testDb -Path $backupPath -EnableException

            # Get backup information for the restore
            $backupInfo = Get-DbaBackupInformation -SqlInstance $TestConfig.instance1 -Path $backupPath -EnableException

            # Format for restore
            $formatted = Format-DbaBackupInformation -BackupHistory $backupInfo -ReplaceDatabaseName "$($testDb)_restored" -EnableException

            # Perform the restore
            $result = Invoke-DbaAdvancedRestore -BackupHistory $formatted -SqlInstance $TestConfig.instance1 -WithReplace -EnableException
        }

        AfterAll {
            # Clean up test databases and backup file
            Remove-DbaDatabase -SqlInstance $TestConfig.instance1 -Database $testDb, "$($testDb)_restored" -Confirm:$false -EnableException
            if (Test-Path $backupPath) {
                Remove-Item $backupPath -Force
            }
        }

        It "Returns PSCustomObject" {
            $result.PSObject.TypeNames | Should -Contain "System.Management.Automation.PSCustomObject"
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
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
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }

        It "Has additional properties available" {
            $additionalProps = @(
                "DatabaseName",
                "DatabaseOwner",
                "BackupSizeMB",
                "CompressedBackupSizeMB",
                "RestoredFileFull",
                "BackupStartTime",
                "BackupEndTime",
                "RestoreTargetTime",
                "BackupFileRaw",
                "KeepReplication"
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $additionalProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be available via Select-Object *"
            }
        }
    }

    Context "Output with -VerifyOnly" {
        BeforeAll {
            $backupPath = "C:\temp\dbatools_advancedrestore_verify_test.bak"
            $testDb = "dbatoolsci_AdvancedRestore_Verify_$(Get-Random)"

            # Create a test database and backup
            $null = New-DbaDatabase -SqlInstance $TestConfig.instance1 -Name $testDb -EnableException
            $null = Backup-DbaDatabase -SqlInstance $TestConfig.instance1 -Database $testDb -Path $backupPath -EnableException

            # Get backup information
            $backupInfo = Get-DbaBackupInformation -SqlInstance $TestConfig.instance1 -Path $backupPath -EnableException

            # Format for restore
            $formatted = Format-DbaBackupInformation -BackupHistory $backupInfo -ReplaceDatabaseName "$($testDb)_verify" -EnableException

            # Perform verify
            $result = Invoke-DbaAdvancedRestore -BackupHistory $formatted -SqlInstance $TestConfig.instance1 -VerifyOnly -EnableException
        }

        AfterAll {
            # Clean up test database and backup file
            Remove-DbaDatabase -SqlInstance $TestConfig.instance1 -Database $testDb -Confirm:$false -EnableException
            if (Test-Path $backupPath) {
                Remove-Item $backupPath -Force
            }
        }

        It "Returns System.String when -VerifyOnly specified" {
            $result | Should -BeOfType [System.String]
        }

        It "Returns verification result" {
            $result | Should -BeIn @("Verify successful", "Verify failed")
        }
    }

    Context "Output with -OutputScriptOnly" {
        BeforeAll {
            $backupPath = "C:\temp\dbatools_advancedrestore_script_test.bak"
            $testDb = "dbatoolsci_AdvancedRestore_Script_$(Get-Random)"

            # Create a test database and backup
            $null = New-DbaDatabase -SqlInstance $TestConfig.instance1 -Name $testDb -EnableException
            $null = Backup-DbaDatabase -SqlInstance $TestConfig.instance1 -Database $testDb -Path $backupPath -EnableException

            # Get backup information
            $backupInfo = Get-DbaBackupInformation -SqlInstance $TestConfig.instance1 -Path $backupPath -EnableException

            # Format for restore
            $formatted = Format-DbaBackupInformation -BackupHistory $backupInfo -ReplaceDatabaseName "$($testDb)_script" -EnableException

            # Get script only
            $result = Invoke-DbaAdvancedRestore -BackupHistory $formatted -SqlInstance $TestConfig.instance1 -OutputScriptOnly -EnableException
        }

        AfterAll {
            # Clean up test database and backup file
            Remove-DbaDatabase -SqlInstance $TestConfig.instance1 -Database $testDb -Confirm:$false -EnableException
            if (Test-Path $backupPath) {
                Remove-Item $backupPath -Force
            }
        }

        It "Returns System.String when -OutputScriptOnly specified" {
            $result | Should -BeOfType [System.String]
        }

        It "Returns T-SQL RESTORE script" {
            $result | Should -Match "RESTORE"
        }
    }
}
<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>