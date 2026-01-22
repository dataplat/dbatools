#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Read-DbaBackupHeader",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Path",
                "Simple",
                "FileList",
                "AzureCredential",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $TestConfig.instance1 -EnableException
            $dbName = "dbatoolsci_readbackupheader_$(Get-Random)"
            $backupPath = Join-Path $TestConfig.appveyorlabrepo "backupheader\full_simple.bak"
            
            # Create test database and backup if needed
            if (-not (Test-Path $backupPath)) {
                $null = New-DbaDatabase -SqlInstance $server -Name $dbName -EnableException
                $backupPath = Backup-DbaDatabase -SqlInstance $server -Database $dbName -Path C:\temp -EnableException | Select-Object -ExpandProperty Path
            }
        }

        AfterAll {
            if ($dbName -and (Get-DbaDatabase -SqlInstance $TestConfig.instance1 -Database $dbName)) {
                Remove-DbaDatabase -SqlInstance $TestConfig.instance1 -Database $dbName -Confirm:$false
            }
            if ($backupPath -and (Test-Path $backupPath) -and $backupPath -like "*dbatoolsci_*") {
                Remove-Item $backupPath -ErrorAction SilentlyContinue
            }
        }

        It "Returns DataRow objects" {
            $result = Read-DbaBackupHeader -SqlInstance $TestConfig.instance1 -Path $backupPath -EnableException
            $result | Should -BeOfType [System.Data.DataRow]
        }

        It "Has the expected dbatools-added properties" {
            $result = Read-DbaBackupHeader -SqlInstance $TestConfig.instance1 -Path $backupPath -EnableException
            $expectedProps = @(
                'FileList',
                'SqlVersion',
                'BackupPath'
            )
            $actualProps = $result.Table.Columns.ColumnName
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be added by dbatools"
            }
        }

        It "Has BackupSize and CompressedBackupSize as dbasize objects" {
            $result = Read-DbaBackupHeader -SqlInstance $TestConfig.instance1 -Path $backupPath -EnableException
            $result.BackupSize | Should -BeOfType [dbasize]
            $result.BackupSize.Byte | Should -BeGreaterThan 0
        }

        It "Has essential backup metadata columns" {
            $result = Read-DbaBackupHeader -SqlInstance $TestConfig.instance1 -Path $backupPath -EnableException
            $essentialProps = @(
                'DatabaseName',
                'BackupFinishDate',
                'RecoveryModel',
                'UserName',
                'ServerName',
                'BackupType',
                'Position'
            )
            $actualProps = $result.Table.Columns.ColumnName
            foreach ($prop in $essentialProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should exist from ReadBackupHeader"
            }
        }
    }

    Context "Output with -Simple" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $TestConfig.instance1 -EnableException
            $dbName = "dbatoolsci_readbackupheader_simple_$(Get-Random)"
            $backupPath = Join-Path $TestConfig.appveyorlabrepo "backupheader\full_simple.bak"
            
            if (-not (Test-Path $backupPath)) {
                $null = New-DbaDatabase -SqlInstance $server -Name $dbName -EnableException
                $backupPath = Backup-DbaDatabase -SqlInstance $server -Database $dbName -Path C:\temp -EnableException | Select-Object -ExpandProperty Path
            }
        }

        AfterAll {
            if ($dbName -and (Get-DbaDatabase -SqlInstance $TestConfig.instance1 -Database $dbName)) {
                Remove-DbaDatabase -SqlInstance $TestConfig.instance1 -Database $dbName -Confirm:$false
            }
            if ($backupPath -and (Test-Path $backupPath) -and $backupPath -like "*dbatoolsci_*") {
                Remove-Item $backupPath -ErrorAction SilentlyContinue
            }
        }

        It "Returns only simplified columns when -Simple is specified" {
            $result = Read-DbaBackupHeader -SqlInstance $TestConfig.instance1 -Path $backupPath -Simple -EnableException
            $expectedProps = @(
                'DatabaseName',
                'BackupFinishDate',
                'RecoveryModel',
                'BackupSize',
                'CompressedBackupSize',
                'DatabaseCreationDate',
                'UserName',
                'ServerName',
                'SqlVersion',
                'BackupPath'
            )
            $actualProps = $result.PSObject.Properties.Name
            # Check that all expected properties exist
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in -Simple output"
            }
        }
    }

    Context "Output with -FileList" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $TestConfig.instance1 -EnableException
            $dbName = "dbatoolsci_readbackupheader_filelist_$(Get-Random)"
            $backupPath = Join-Path $TestConfig.appveyorlabrepo "backupheader\full_simple.bak"
            
            if (-not (Test-Path $backupPath)) {
                $null = New-DbaDatabase -SqlInstance $server -Name $dbName -EnableException
                $backupPath = Backup-DbaDatabase -SqlInstance $server -Database $dbName -Path C:\temp -EnableException | Select-Object -ExpandProperty Path
            }
        }

        AfterAll {
            if ($dbName -and (Get-DbaDatabase -SqlInstance $TestConfig.instance1 -Database $dbName)) {
                Remove-DbaDatabase -SqlInstance $TestConfig.instance1 -Database $dbName -Confirm:$false
            }
            if ($backupPath -and (Test-Path $backupPath) -and $backupPath -like "*dbatoolsci_*") {
                Remove-Item $backupPath -ErrorAction SilentlyContinue
            }
        }

        It "Returns file list objects when -FileList is specified" {
            $result = Read-DbaBackupHeader -SqlInstance $TestConfig.instance1 -Path $backupPath -FileList -EnableException
            $result | Should -Not -BeNullOrEmpty
            # Check for key file list properties
            $fileListProps = @(
                'LogicalName',
                'PhysicalName',
                'Type',
                'FileGroupName',
                'Size'
            )
            $actualProps = $result[0].PSObject.Properties.Name
            foreach ($prop in $fileListProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in file list output"
            }
        }
    }
}
<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>