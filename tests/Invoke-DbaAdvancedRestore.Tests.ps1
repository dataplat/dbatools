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
    Context "Output validation with script" {
        BeforeAll {
            $backupPathRestore = "$($TestConfig.Temp)\$CommandName-restore-$(Get-Random)"
            $null = New-Item -Path $backupPathRestore -ItemType Directory
            $backupFileRestore = "$backupPathRestore\master_outputtest.bak"
            $null = Backup-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database master -Type Full -FilePath $backupFileRestore
            $backupHistoryRestore = Get-DbaBackupInformation -SqlInstance $TestConfig.InstanceSingle -Path $backupFileRestore
            $resultRestore = $backupHistoryRestore | Invoke-DbaAdvancedRestore -SqlInstance $TestConfig.InstanceSingle -WithReplace -OutputScriptOnly
        }
        AfterAll {
            Remove-Item -Path $backupPathRestore -Recurse -ErrorAction SilentlyContinue
        }

        It "Returns T-SQL script as a string when using -OutputScriptOnly" {
            $resultRestore | Should -Not -BeNullOrEmpty
            $resultRestore | Should -BeOfType [string]
            $resultRestore | Should -BeLike "RESTORE DATABASE*"
        }
    }

    Context "Output validation with actual restore" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $dbNameOutput = "dbatoolsci_advrestore_$(Get-Random)"
            $backupPathActual = "$($TestConfig.Temp)\$CommandName-actual-$(Get-Random)"
            $null = New-Item -Path $backupPathActual -ItemType Directory
            $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $dbNameOutput
            $backupFileActual = "$backupPathActual\$($dbNameOutput)_outputtest.bak"
            $null = Backup-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbNameOutput -Type Full -FilePath $backupFileActual
            $backupHistoryActual = Get-DbaBackupInformation -SqlInstance $TestConfig.InstanceSingle -Path $backupFileActual
            $resultActual = $backupHistoryActual | Invoke-DbaAdvancedRestore -SqlInstance $TestConfig.InstanceSingle -WithReplace
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }
        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbNameOutput -Confirm:$false -ErrorAction SilentlyContinue
            Remove-Item -Path $backupPathActual -Recurse -ErrorAction SilentlyContinue
        }

        It "Returns output that is not null" {
            $resultActual | Should -Not -BeNullOrEmpty
        }

        It "Has the expected default display properties" {
            $defaultProps = $resultActual[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @(
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
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }

        It "Has the expected additional properties" {
            $resultActual[0].psobject.Properties.Name | Should -Contain "DatabaseName"
            $resultActual[0].psobject.Properties.Name | Should -Contain "DatabaseOwner"
            $resultActual[0].psobject.Properties.Name | Should -Contain "BackupSizeMB"
            $resultActual[0].psobject.Properties.Name | Should -Contain "CompressedBackupSizeMB"
            $resultActual[0].psobject.Properties.Name | Should -Contain "RestoredFileFull"
            $resultActual[0].psobject.Properties.Name | Should -Contain "BackupStartTime"
            $resultActual[0].psobject.Properties.Name | Should -Contain "BackupEndTime"
        }

        It "Has RestoreComplete set to true on successful restore" {
            $resultActual[0].RestoreComplete | Should -BeTrue
        }
    }
}