#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Backup-DbaDbCertificate",
    $PSDefaultParameterValues = ($TestConfig = Get-TestConfig).Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Certificate",
                "Database",
                "ExcludeDatabase",
                "EncryptionPassword",
                "DecryptionPassword",
                "Path",
                "Suffix",
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

        $random = Get-Random
        $db1Name = "dbatoolscli_db1_$random"
        $db2Name = "dbatoolscli_db2_$random"
        $pw = ConvertTo-SecureString -String "GoodPass1234!" -AsPlainText -Force

        $db1 = New-DbaDatabase -SqlInstance $TestConfig.instance1 -Name $db1Name
        $null = New-DbaDbMasterKey -SqlInstance $TestConfig.instance1 -Database $db1Name -Password $pw

        $db2 = New-DbaDatabase -SqlInstance $TestConfig.instance1 -Name $db2Name
        $null = New-DbaDbMasterKey -SqlInstance $TestConfig.instance1 -Database $db2Name -Password $pw

        $cert1 = New-DbaDbCertificate -SqlInstance $TestConfig.instance1 -Database $db1Name -Password $pw -Name "dbatoolscli_cert1_$random"
        $cert2 = New-DbaDbCertificate -SqlInstance $TestConfig.instance1 -Database $db1Name -Password $pw -Name "dbatoolscli_cert2_$random"
        $cert3 = New-DbaDbCertificate -SqlInstance $TestConfig.instance1 -Database $db2Name -Password $pw -Name "dbatoolscli_cert3_$random"

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }
    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        Remove-DbaDatabase -SqlInstance $TestConfig.instance1 -Database $db1Name, $db2Name -Confirm:$false

        # As this is the last block we do not need to reset the $PSDefaultParameterValues.
    }

    Context "Can backup a database certificate" {
        It "Returns results with proper data" {
            $splatBackupCert = @{
                SqlInstance        = $TestConfig.instance1
                Database           = $db1Name
                Certificate        = $cert1.Name
                EncryptionPassword = $pw
                DecryptionPassword = $pw
            }
            $results = Backup-DbaDbCertificate @splatBackupCert

            try {
                $results.Certificate | Should -Be $cert1.Name
                $results.Status | Should -BeExactly "Success"
                $results.DatabaseID | Should -Be $db1.ID
            } catch {
                Remove-Item -Path $results.Path -ErrorAction SilentlyContinue
                Remove-Item -Path $results.Key -ErrorAction SilentlyContinue
            }
        }
    }

    Context "Can backup a database certificate with a filename (see #9485)" {
        It "Returns results with proper data" {
            $splatBackupCertWithName = @{
                SqlInstance        = $TestConfig.instance1
                Database           = $db1Name
                Certificate        = $cert1.Name
                EncryptionPassword = $pw
                DecryptionPassword = $pw
                FileBaseName       = "dbatoolscli_cert1_$random"
            }
            $results = Backup-DbaDbCertificate @splatBackupCertWithName

            try {
                $results.Certificate | Should -Be $cert1.Name
                $results.Status | Should -BeExactly "Success"
                $results.DatabaseID | Should -Be $db1.ID
                [IO.Path]::GetFileNameWithoutExtension($results.Path) | Should -Be "dbatoolscli_cert1_$random"
            } catch {
                Remove-Item -Path $results.Path -ErrorAction SilentlyContinue
                Remove-Item -Path $results.Key -ErrorAction SilentlyContinue
            }
        }
    }

    Context "Warns the caller if the cert cannot be found" {
        It "Does warn" {
            $invalidDBCertName = "dbatoolscli_invalidCertName"
            $invalidDBCertName2 = "dbatoolscli_invalidCertName2"
            $splatBackupInvalidCert = @{
                SqlInstance        = $TestConfig.instance1
                Database           = $db1Name
                Certificate        = @($invalidDBCertName, $invalidDBCertName2, $cert2.Name)
                EncryptionPassword = $pw
                DecryptionPassword = $pw
                WarningAction      = "SilentlyContinue"
            }
            $results = Backup-DbaDbCertificate @splatBackupInvalidCert

            try {
                $WarnVar | Should -Match "Database certificate\(s\) .* not found"
            } catch {
                Remove-Item -Path $results.Path -ErrorAction SilentlyContinue
                Remove-Item -Path $results.Key -ErrorAction SilentlyContinue
            }
        }
    }

    Context "Backs up all db certs for a database" {
        It "Returns results with proper data" {
            $splatBackupDbCerts = @{
                SqlInstance        = $TestConfig.instance1
                Database           = $db1Name
                EncryptionPassword = $pw
                DecryptionPassword = $pw
            }
            $results = Backup-DbaDbCertificate @splatBackupDbCerts

            try {
                $results | Should -HaveCount 2
                $results.Certificate | Should -Be $cert1.Name, $cert2.Name
            } catch {
                Remove-Item -Path $results.Path -ErrorAction SilentlyContinue
                Remove-Item -Path $results.Key -ErrorAction SilentlyContinue
            }
        }
    }

    Context "Backs up all db certs for an instance" {
        It "Returns results with proper data" {
            $splatBackupAllCerts = @{
                SqlInstance        = $TestConfig.instance1
                EncryptionPassword = $pw
                DecryptionPassword = $pw
            }
            $results = Backup-DbaDbCertificate @splatBackupAllCerts

            try {
                $results | Should -HaveCount 3
                $results.Certificate | Should -Be $cert1.Name, $cert2.Name, $cert3.Name
            } catch {
                Remove-Item -Path $results.Path -ErrorAction SilentlyContinue
                Remove-Item -Path $results.Key -ErrorAction SilentlyContinue
            }
        }
    }
}