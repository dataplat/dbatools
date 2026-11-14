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

            $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $dbName

            $masterkey = New-DbaDbMasterKey -SqlInstance $TestConfig.InstanceSingle -Database $dbName -Password $masterKeyPassword
            $cert = New-DbaDbCertificate -SqlInstance $TestConfig.InstanceSingle -Database $dbName
            $backup = Backup-DbaDbCertificate -SqlInstance $TestConfig.InstanceSingle -Certificate $cert.Name -Database $dbName -EncryptionPassword $certificatePassword -Path $backupPath
            $cert | Remove-DbaDbCertificate

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }
        AfterEach {
            $null = Remove-DbaDbCertificate -SqlInstance $TestConfig.InstanceSingle -Certificate $cert.Name -Database $dbName -ErrorAction SilentlyContinue
        }
        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbName

            # Remove the backup directory.
            Remove-Item -Path $backupPath -Recurse

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "restores the db cert when passing in a .cer file" {
            $results = Restore-DbaDbCertificate -SqlInstance $TestConfig.InstanceSingle -Path $backup.ExportPath -Password $certificatePassword -Database $dbName -EncryptionPassword $certificatePassword
            $results.Parent.Name | Should -Be $dbName
            $results.Name | Should -Not -BeNullOrEmpty
            $results.PrivateKeyEncryptionType | Should -Be "Password"
            $results | Remove-DbaDbCertificate
            # TODO: Create a test for password generated cert
            # From what I can tell, what matters is creation, not restore.
        }

        It "restores the db cert when passing in a folder" {
            $folder = Split-Path $backup.ExportPath -Parent
            $results = Restore-DbaDbCertificate -SqlInstance $TestConfig.InstanceSingle -Path $folder -Password $certificatePassword -Database $dbName -EncryptionPassword $certificatePassword
            $results.Parent.Name | Should -Be $dbName
            $results.Name | Should -Not -BeNullOrEmpty
            $results.PrivateKeyEncryptionType | Should -Be "Password"
            $results | Remove-DbaDbCertificate
        }

        It "restores the db cert and encrypts with master key" {
            $folder = Split-Path $backup.ExportPath -Parent
            $results = Restore-DbaDbCertificate -SqlInstance $TestConfig.InstanceSingle -Path $folder -Password $certificatePassword -Database $dbName
            $results.Parent.Name | Should -Be $dbName
            $results.Name | Should -Not -BeNullOrEmpty
            $results.PrivateKeyEncryptionType | Should -Be "MasterKey"
            $results | Remove-DbaDbCertificate
        }
    }

    Context "Several paths and folders without certificates (#10835)" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $multiBackupPath = "$($TestConfig.Temp)\$CommandName-$(Get-Random)"
            $null = New-Item -Path $multiBackupPath -ItemType Directory

            $multiDbName = "dbatoolsci_restorecert_$(Get-Random)"
            $multiMasterKeyPassword = ConvertTo-SecureString -String "GoodPass1234!" -AsPlainText -Force
            $multiCertificatePassword = ConvertTo-SecureString -String "GoodPass1234!!" -AsPlainText -Force

            $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $multiDbName
            $null = New-DbaDbMasterKey -SqlInstance $TestConfig.InstanceSingle -Database $multiDbName -Password $multiMasterKeyPassword

            # Two certificates in one folder, so that -Path can name both files or the folder
            $multiBackups = foreach ($certificateName in "dbatoolsci_restorecert_a", "dbatoolsci_restorecert_b") {
                $multiCert = New-DbaDbCertificate -SqlInstance $TestConfig.InstanceSingle -Database $multiDbName -Name $certificateName
                Backup-DbaDbCertificate -SqlInstance $TestConfig.InstanceSingle -Certificate $multiCert.Name -Database $multiDbName -EncryptionPassword $multiCertificatePassword -Path $multiBackupPath
                $null = $multiCert | Remove-DbaDbCertificate
            }

            $emptyFolder = "$multiBackupPath\dbatoolsci_empty"
            $null = New-Item -Path $emptyFolder -ItemType Directory

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterEach {
            $null = Get-DbaDbCertificate -SqlInstance $TestConfig.InstanceSingle -Database $multiDbName | Where-Object Name -like "dbatoolsci_restorecert_*" | Remove-DbaDbCertificate -ErrorAction SilentlyContinue
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $multiDbName -ErrorAction SilentlyContinue
            Remove-Item -Path $multiBackupPath -Recurse -ErrorAction SilentlyContinue

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "restores every certificate once when passing in several .cer files" {
            # The files of -Path were processed once per entry of -Path, so the second round failed on certificates that already existed
            $splatRestoreFiles = @{
                SqlInstance        = $TestConfig.InstanceSingle
                Path               = $multiBackups.ExportPath
                Password           = $multiCertificatePassword
                Database           = $multiDbName
                EncryptionPassword = $multiCertificatePassword
            }
            $results = Restore-DbaDbCertificate @splatRestoreFiles
            @($results).Count | Should -Be 2
            ($results.Name | Sort-Object -Unique).Count | Should -Be 2
            $WarnVar | Should -BeNullOrEmpty
        }

        It "warns when a folder holds no certificate file" {
            # This used to return nothing without a word, which also hid that a login without sysadmin cannot list a folder
            $splatRestoreEmpty = @{
                SqlInstance = $TestConfig.InstanceSingle
                Path        = $emptyFolder
                Password    = $multiCertificatePassword
                Database    = $multiDbName
            }
            $results = Restore-DbaDbCertificate @splatRestoreEmpty -WarningAction SilentlyContinue
            $results | Should -BeNullOrEmpty
            $WarnVar | Should -BeLike "*No certificate file (.cer) found*"
        }
    }
}