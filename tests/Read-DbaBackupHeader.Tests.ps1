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
Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $backupPath = "$($TestConfig.Temp)\$CommandName-$(Get-Random)"
        $null = New-Item -Path $backupPath -ItemType Directory
        $backupFile = "$backupPath\dbatoolsci_headertest.bak"
        $null = Backup-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database master -Type Full -FilePath $backupFile

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
        Remove-Item -Path $backupPath -Recurse -ErrorAction SilentlyContinue
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Output validation" {
        BeforeAll {
            $result = @(Read-DbaBackupHeader -SqlInstance $TestConfig.InstanceSingle -Path $backupFile)
        }

        It "Returns output of the documented type" {
            $result | Should -Not -BeNullOrEmpty
            $result[0] | Should -BeOfType System.Data.DataRow
        }

        It "Has the expected properties" {
            $result | Should -Not -BeNullOrEmpty
            $result[0].psobject.Properties.Name | Should -Contain "DatabaseName"
            $result[0].psobject.Properties.Name | Should -Contain "BackupFinishDate"
            $result[0].psobject.Properties.Name | Should -Contain "RecoveryModel"
            $result[0].psobject.Properties.Name | Should -Contain "BackupSize"
            $result[0].psobject.Properties.Name | Should -Contain "CompressedBackupSize"
            $result[0].psobject.Properties.Name | Should -Contain "ServerName"
            $result[0].psobject.Properties.Name | Should -Contain "SqlVersion"
            $result[0].psobject.Properties.Name | Should -Contain "BackupPath"
        }

        It "Has correct database name" {
            $result | Should -Not -BeNullOrEmpty
            $result[0].DatabaseName | Should -Be "master"
        }

        It "Returns simplified output with -Simple" {
            $simpleResult = @(Read-DbaBackupHeader -SqlInstance $TestConfig.InstanceSingle -Path $backupFile -Simple)
            $simpleResult | Should -Not -BeNullOrEmpty
            $simpleProps = $simpleResult[0].psobject.Properties.Name
            $expectedSimpleProps = @("DatabaseName", "BackupFinishDate", "RecoveryModel", "BackupSize", "CompressedBackupSize", "DatabaseCreationDate", "UserName", "ServerName", "SqlVersion", "BackupPath")
            foreach ($prop in $expectedSimpleProps) {
                $simpleProps | Should -Contain $prop -Because "property '$prop' should be in the simplified output"
            }
        }

        It "Returns file list with -FileList" {
            $fileListResult = @(Read-DbaBackupHeader -SqlInstance $TestConfig.InstanceSingle -Path $backupFile -FileList)
            $fileListResult | Should -Not -BeNullOrEmpty
            $fileListResult[0].psobject.Properties.Name | Should -Contain "LogicalName"
            $fileListResult[0].psobject.Properties.Name | Should -Contain "PhysicalName"
            $fileListResult[0].psobject.Properties.Name | Should -Contain "Type"
        }
    }
}