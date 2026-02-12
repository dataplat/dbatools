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

    Context "Output validation" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $outputBackupPath = "$($TestConfig.Temp)\$CommandName-output-$(Get-Random)"
            $null = New-Item -Path $outputBackupPath -ItemType Directory

            $outputDbName = "dbatoolsci_certoutput-$(Get-Random)"
            $outputMasterKeyPassword = ConvertTo-SecureString -String "GoodPass1234!" -AsPlainText -Force
            $outputCertificatePassword = ConvertTo-SecureString -AsPlainText "GoodPass1234!!" -Force

            $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $outputDbName
            $null = New-DbaDbMasterKey -SqlInstance $TestConfig.InstanceSingle -Database $outputDbName -Password $outputMasterKeyPassword
            $outputCert = New-DbaDbCertificate -SqlInstance $TestConfig.InstanceSingle -Database $outputDbName
            $outputBackup = Backup-DbaDbCertificate -SqlInstance $TestConfig.InstanceSingle -Certificate $outputCert.Name -Database $outputDbName -EncryptionPassword $outputCertificatePassword -Path $outputBackupPath
            $outputCert | Remove-DbaDbCertificate

            $outputResult = Restore-DbaDbCertificate -SqlInstance $TestConfig.InstanceSingle -Path $outputBackup.ExportPath -Password $outputCertificatePassword -Database $outputDbName -EncryptionPassword $outputCertificatePassword

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $null = Remove-DbaDbCertificate -SqlInstance $TestConfig.InstanceSingle -Certificate $outputCert.Name -Database $outputDbName -ErrorAction SilentlyContinue
            $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $outputDbName -ErrorAction SilentlyContinue
            Remove-Item -Path $outputBackupPath -Recurse -ErrorAction SilentlyContinue
        }

        It "Returns output that is not null" {
            $outputResult | Should -Not -BeNullOrEmpty
        }

        It "Returns output of the documented type" {
            if (-not $outputResult) { Set-ItResult -Skipped -Because "no result to validate" }
            $outputResult[0].psobject.TypeNames | Should -Contain "Microsoft.SqlServer.Management.Smo.Certificate"
        }

        It "Has the expected default display properties" {
            if (-not $outputResult) { Set-ItResult -Skipped -Because "no result to validate" }
            $defaultProps = $outputResult[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Database",
                "Name",
                "Subject",
                "StartDate",
                "ActiveForServiceBrokerDialog",
                "ExpirationDate",
                "Issuer",
                "LastBackupDate",
                "Owner",
                "PrivateKeyEncryptionType",
                "Serial"
            )
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }
    }
}