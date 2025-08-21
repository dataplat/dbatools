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
            $global:TestConfig = Get-TestConfig
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $masterKeyPassword = ConvertTo-SecureString -String "GoodPass1234!" -AsPlainText -Force
            $certificatePassword = ConvertTo-SecureString -AsPlainText "GoodPass1234!!" -Force

            $masterkey = New-DbaDbMasterKey -SqlInstance $TestConfig.instance1 -Database tempdb -Password $masterKeyPassword
            $cert = New-DbaDbCertificate -SqlInstance $TestConfig.instance1 -Database tempdb
            $backup = Backup-DbaDbCertificate -SqlInstance $TestConfig.instance1 -Certificate $cert.Name -Database tempdb -EncryptionPassword $certificatePassword
            $cert | Remove-DbaDbCertificate

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }
        AfterEach {
            $null = Remove-DbaDbCertificate -SqlInstance $TestConfig.instance1 -Certificate $cert.Name -Database tempdb -ErrorAction SilentlyContinue
        }
        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = $masterkey | Remove-DbaDbMasterKey
            $null = Remove-Item -Path $backup.ExportPath, $backup.ExportKey -ErrorAction SilentlyContinue

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "restores the db cert when passing in a .cer file" {
            $results = Restore-DbaDbCertificate -SqlInstance $TestConfig.instance1 -Path $backup.ExportPath -Password $certificatePassword -Database tempdb -EncryptionPassword $certificatePassword
            $results.Parent.Name | Should -Be "tempdb"
            $results.Name | Should -Not -BeNullOrEmpty
            $results.PrivateKeyEncryptionType | Should -Be "Password"
            $results | Remove-DbaDbCertificate
            # TODO: Create a test for password generated cert
            # From what I can tell, what matters is creation, not restore.
        }

        It "restores the db cert when passing in a folder" {
            $folder = Split-Path $backup.ExportPath -Parent
            $results = Restore-DbaDbCertificate -SqlInstance $TestConfig.instance1 -Path $folder -Password $certificatePassword -Database tempdb -EncryptionPassword $certificatePassword
            $results.Parent.Name | Should -Be "tempdb"
            $results.Name | Should -Not -BeNullOrEmpty
            $results.PrivateKeyEncryptionType | Should -Be "Password"
            $results | Remove-DbaDbCertificate
        }

        It "restores the db cert and encrypts with master key" {
            $folder = Split-Path $backup.ExportPath -Parent
            $results = Restore-DbaDbCertificate -SqlInstance $TestConfig.instance1 -Path $folder -Password $certificatePassword -Database tempdb
            $results.Parent.Name | Should -Be "tempdb"
            $results.Name | Should -Not -BeNullOrEmpty
            $results.PrivateKeyEncryptionType | Should -Be "MasterKey"
            $results | Remove-DbaDbCertificate
        }
    }
}