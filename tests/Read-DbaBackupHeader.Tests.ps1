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
                "StorageCredential",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $singleBackupPath = "$($TestConfig.AppveyorLabRepo)\singlerestore\singlerestore.bak"
    }

    Context "Reading a single backup file" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $headerResults = Read-DbaBackupHeader -SqlInstance $TestConfig.InstanceSingle -Path $singleBackupPath
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Returns one header row for a single-backup-set file" {
            @($headerResults).Count | Should -BeExactly 1
        }

        It "Reads the core header fields" {
            $headerResults.DatabaseName | Should -Be "singlerestore"
            $headerResults.Position | Should -BeExactly 1
            $headerResults.BackupTypeDescription | Should -Be "Database"
        }

        It "Attaches the embedded file list" {
            @($headerResults.FileList).Count | Should -BeExactly 2
            ($headerResults.FileList | Where-Object Type -eq "D").LogicalName | Should -Be "singlerestore"
            ($headerResults.FileList | Where-Object Type -eq "L").LogicalName | Should -Be "singlerestore_log"
        }
    }

    Context "Simple and FileList output modes" {
        It "Returns the trimmed view with -Simple" {
            $simpleResults = Read-DbaBackupHeader -SqlInstance $TestConfig.InstanceSingle -Path $singleBackupPath -Simple
            # characterization: current behavior returns exactly these ten properties,
            # do not "fix" without a surface-diff decision
            $expectedProperties = @(
                "BackupFinishDate",
                "BackupPath",
                "BackupSize",
                "CompressedBackupSize",
                "DatabaseCreationDate",
                "DatabaseName",
                "RecoveryModel",
                "ServerName",
                "SqlVersion",
                "UserName"
            )
            ($simpleResults.PSObject.Properties.Name | Sort-Object) | Should -Be $expectedProperties
        }

        It "Returns the raw file list rows with -FileList" {
            $fileListResults = Read-DbaBackupHeader -SqlInstance $TestConfig.InstanceSingle -Path $singleBackupPath -FileList
            @($fileListResults).Count | Should -BeExactly 2
            ($fileListResults | Where-Object Type -eq "D").LogicalName | Should -Be "singlerestore"
            ($fileListResults | Where-Object Type -eq "L").LogicalName | Should -Be "singlerestore_log"
        }
    }

    Context "Pipeline input" {
        It "Accepts backup files from Get-ChildItem" {
            $pipedResults = Get-ChildItem -Path $singleBackupPath | Read-DbaBackupHeader -SqlInstance $TestConfig.InstanceSingle
            @($pipedResults).Count | Should -BeExactly 1
            $pipedResults.DatabaseName | Should -Be "singlerestore"
        }
    }

    Context "Unreadable path" {
        It "Warns and returns nothing for a missing file" {
            $splatMissing = @{
                SqlInstance   = $TestConfig.InstanceSingle
                Path          = "$($TestConfig.AppveyorLabRepo)\dbatoolsci_missing_$(Get-Random).bak"
                WarningAction = "SilentlyContinue"
            }
            $missingResults = Read-DbaBackupHeader @splatMissing
            $missingResults | Should -BeNullOrEmpty
            $WarnVar | Should -Match "does not exist or access denied"
        }
    }
}