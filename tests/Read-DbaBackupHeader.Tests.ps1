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
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $backupPath = "$($TestConfig.Temp)\$CommandName-$(Get-Random)"
        $null = New-Item -Path $backupPath -ItemType Directory

        $splatBackup = @{
            SqlInstance   = $TestConfig.instance2
            Database      = "master"
            Path          = $backupPath
            BackupFileName = "headertest.bak"
        }
        $null = Backup-DbaDatabase @splatBackup

        $backupFile = "$backupPath\headertest.bak"

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
        Remove-Item -Path $backupPath -Recurse -ErrorAction SilentlyContinue
    }

    Context "When reading backup headers" {
        BeforeAll {
            $result = @(Read-DbaBackupHeader -SqlInstance $TestConfig.instance2 -Path $backupFile -OutVariable "global:dbatoolsciOutput")
        }

        It "Should return results" {
            $result | Should -Not -BeNullOrEmpty
        }

        It "Should have the expected DatabaseName" {
            $result[0].DatabaseName | Should -Be "master"
        }

        It "Should have a BackupFinishDate" {
            $result[0].BackupFinishDate | Should -Not -BeNullOrEmpty
        }

        It "Should have a BackupSize as dbasize" {
            $result[0].BackupSize | Should -BeOfType [dbasize]
        }

        It "Should have a SqlVersion" {
            $result[0].SqlVersion | Should -Not -BeNullOrEmpty
        }

        It "Should have a BackupPath matching the input" {
            $result[0].BackupPath | Should -Be $backupFile
        }

        It "Should have a FileList" {
            $result[0].FileList | Should -Not -BeNullOrEmpty
        }
    }

    Context "When using -Simple" {
        BeforeAll {
            $simpleResult = Read-DbaBackupHeader -SqlInstance $TestConfig.instance2 -Path $backupFile -Simple
        }

        It "Should return results" {
            $simpleResult | Should -Not -BeNullOrEmpty
        }

        It "Should have the expected simple properties" {
            $expectedProps = @(
                "DatabaseName",
                "BackupFinishDate",
                "RecoveryModel",
                "BackupSize",
                "CompressedBackupSize",
                "DatabaseCreationDate",
                "UserName",
                "ServerName",
                "SqlVersion",
                "BackupPath"
            )
            $actualProps = $simpleResult[0].PSObject.Properties.Name
            Compare-Object -ReferenceObject $expectedProps -DifferenceObject $actualProps | Should -BeNullOrEmpty
        }
    }

    Context "When using -FileList" {
        BeforeAll {
            $fileListResult = Read-DbaBackupHeader -SqlInstance $TestConfig.instance2 -Path $backupFile -FileList
        }

        It "Should return results" {
            $fileListResult | Should -Not -BeNullOrEmpty
        }

        It "Should have LogicalName property" {
            $fileListResult[0].LogicalName | Should -Not -BeNullOrEmpty
        }

        It "Should have Type property" {
            $fileListResult[0].Type | Should -Not -BeNullOrEmpty
        }
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return the correct type" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [System.Data.DataRow]
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "System\.Data\.DataRow"
        }
    }
}