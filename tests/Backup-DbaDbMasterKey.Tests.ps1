#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Backup-DbaDbMasterKey",
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
                "Credential",
                "Database",
                "ExcludeDatabase",
                "SecurePassword",
                "Path",
                "FileBaseName",
                "InputObject",
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
        # Other files can be written there as well, maybe we change the name of that variable later. But for now we focus on backups.
        $backupPath = "$($TestConfig.Temp)\$CommandName-$(Get-Random)"
        $null = New-Item -Path $backupPath -ItemType Directory

        # Explain what needs to be set up for the test:
        # To test backing up a database master key, we need a database with a master key created.
        # We'll create the master key if it doesn't exist, and track files created for cleanup.

        # Set variables. They are available in all the It blocks.
        $random = Get-Random
        $testInstance = $TestConfig.instance1
        $testDatabase = "dbatoolscli_db_$random"
        $masterKeyPass = ConvertTo-SecureString -String "GoodPass1234!" -AsPlainText -Force

        $null = New-DbaDatabase -SqlInstance $testInstance -Name $testDatabase
        $null = New-DbaDbMasterKey -SqlInstance $testInstance -Database $testDatabase -Password $masterKeyPass

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup all created objects.
        Remove-DbaDatabase -SqlInstance $testInstance -Database $testDatabase

        # Remove the backup directory.
        Remove-Item -Path $backupPath -Recurse -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Can backup a database master key" {
        It "Backs up the database master key" {
            $splatBackup = @{
                SqlInstance    = $testInstance
                Database       = $testDatabase
                SecurePassword = $masterKeyPass
                Path           = $backupPath
                Confirm        = $false
            }
            $results = Backup-DbaDbMasterKey @splatBackup
            $results | Should -Not -BeNullOrEmpty
            $results.Database | Should -Be $testDatabase
            $results.Status | Should -Be "Success"
            $results.DatabaseID | Should -Be (Get-DbaDatabase -SqlInstance $testInstance -Database $testDatabase).ID

            # File will be cleaned up with the backupPath directory in AfterAll
        }

        It "Backs up the database master key with a specific filename (see #9484)" {
            $random = Get-Random
            $splatBackupWithName = @{
                SqlInstance    = $testInstance
                Database       = $testDatabase
                SecurePassword = $masterKeyPass
                Path           = $backupPath
                FileBaseName   = "dbatoolscli_dbmasterkey_$random"
                Confirm        = $false
            }
            $results = Backup-DbaDbMasterKey @splatBackupWithName
            $results | Should -Not -BeNullOrEmpty
            $results.Database | Should -Be $testDatabase
            $results.Status | Should -Be "Success"
            $results.DatabaseID | Should -Be (Get-DbaDatabase -SqlInstance $testInstance -Database $testDatabase).ID
            [IO.Path]::GetFileNameWithoutExtension($results.Path) | Should -Be "dbatoolscli_dbmasterkey_$random"

            # File will be cleaned up with the backupPath directory in AfterAll
        }
    }
}