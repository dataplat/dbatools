#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Restore-DbaDbCertificate",
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
                "KeyFilePath",
                "EncryptionPassword",
                "Database",
                "Name",
                "DecryptionPassword",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Can create a database certificate" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # For all the backups that we want to clean up after the test, we create a directory that we can delete at the end.
            # Other files can be written there as well, maybe we change the name of that variable later. But for now we focus on backups.
            $backupPath = "$($TestConfig.Temp)\$CommandName-$(Get-Random)"
            $null = New-Item -Path $backupPath -ItemType Directory

            $dbName = "certificate-$(Get-Random)"
            $masterKeyPassword = ConvertTo-SecureString -String "GoodPass1234!" -AsPlainText -Force
            $certificatePassword = ConvertTo-SecureString -AsPlainText "GoodPass1234!!" -Force

            $null = New-DbaDatabase -SqlInstance $TestConfig.instance1 -Name $dbName

            $masterkey = New-DbaDbMasterKey -SqlInstance $TestConfig.instance1 -Database $dbName -Password $masterKeyPassword
            $cert = New-DbaDbCertificate -SqlInstance $TestConfig.instance1 -Database $dbName
            $backup = Backup-DbaDbCertificate -SqlInstance $TestConfig.instance1 -Certificate $cert.Name -Database $dbName -EncryptionPassword $certificatePassword -Path $backupPath
            $cert | Remove-DbaDbCertificate

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }
        AfterEach {
            $null = Remove-DbaDbCertificate -SqlInstance $TestConfig.instance1 -Certificate $cert.Name -Database $dbName -ErrorAction SilentlyContinue
        }
        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = Remove-DbaDatabase -SqlInstance $TestConfig.instance1 -Database $dbName

            # Remove the backup directory.
            Remove-Item -Path $backupPath -Recurse

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "restores the db cert when passing in a .cer file" {
            $results = Restore-DbaDbCertificate -SqlInstance $TestConfig.instance1 -Path $backup.ExportPath -Password $certificatePassword -Database $dbName -EncryptionPassword $certificatePassword
            $results.Parent.Name | Should -Be $dbName
            $results.Name | Should -Not -BeNullOrEmpty
            $results.PrivateKeyEncryptionType | Should -Be "Password"
            $results | Remove-DbaDbCertificate
            # TODO: Create a test for password generated cert
            # From what I can tell, what matters is creation, not restore.
        }

        It "restores the db cert when passing in a folder" {
            $folder = Split-Path $backup.ExportPath -Parent
            $results = Restore-DbaDbCertificate -SqlInstance $TestConfig.instance1 -Path $folder -Password $certificatePassword -Database $dbName -EncryptionPassword $certificatePassword
            $results.Parent.Name | Should -Be $dbName
            $results.Name | Should -Not -BeNullOrEmpty
            $results.PrivateKeyEncryptionType | Should -Be "Password"
            $results | Remove-DbaDbCertificate
        }

        It "restores the db cert and encrypts with master key" {
            $folder = Split-Path $backup.ExportPath -Parent
            $results = Restore-DbaDbCertificate -SqlInstance $TestConfig.instance1 -Path $folder -Password $certificatePassword -Database $dbName
            $results.Parent.Name | Should -Be $dbName
            $results.Name | Should -Not -BeNullOrEmpty
            $results.PrivateKeyEncryptionType | Should -Be "MasterKey"
            $results | Remove-DbaDbCertificate
        }
    }
}