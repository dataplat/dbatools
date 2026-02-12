#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Backup-DbaDbCertificate",
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

        # For all the backups that we want to clean up after the test, we create a directory that we can delete at the end.
        # Other files can be written there as well, maybe we change the name of that variable later. But for now we focus on backups.
        $backupPath = "$($TestConfig.Temp)\$CommandName-$(Get-Random)"
        $null = New-Item -Path $backupPath -ItemType Directory
        $PSDefaultParameterValues["Backup-DbaDbCertificate:Path"] = $backupPath

        $random = Get-Random
        $db1Name = "dbatoolscli_db1_$random"
        $db2Name = "dbatoolscli_db2_$random"
        $pw = ConvertTo-SecureString -String "GoodPass1234!" -AsPlainText -Force

        $db1 = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $db1Name
        $null = New-DbaDbMasterKey -SqlInstance $TestConfig.InstanceSingle -Database $db1Name -Password $pw

        $db2 = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $db2Name
        $null = New-DbaDbMasterKey -SqlInstance $TestConfig.InstanceSingle -Database $db2Name -Password $pw

        $cert1 = New-DbaDbCertificate -SqlInstance $TestConfig.InstanceSingle -Database $db1Name -Password $pw -Name "dbatoolscli_cert1_$random"
        $cert2 = New-DbaDbCertificate -SqlInstance $TestConfig.InstanceSingle -Database $db1Name -Password $pw -Name "dbatoolscli_cert2_$random"
        $cert3 = New-DbaDbCertificate -SqlInstance $TestConfig.InstanceSingle -Database $db2Name -Password $pw -Name "dbatoolscli_cert3_$random"

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }
    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $db1Name, $db2Name

        # Remove the backup directory.
        Remove-Item -Path $backupPath -Recurse

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Can backup a database certificate" {
        It "Returns results with proper data" {
            $splatBackupCert = @{
                SqlInstance        = $TestConfig.InstanceSingle
                Database           = $db1Name
                Certificate        = $cert1.Name
                EncryptionPassword = $pw
                DecryptionPassword = $pw
            }
            $results = Backup-DbaDbCertificate @splatBackupCert

            $results.Certificate | Should -Be $cert1.Name
            $results.Status | Should -BeExactly "Success"
            $results.DatabaseID | Should -Be $db1.ID
        }

        It "Returns output of the documented type" {
            $results | Should -Not -BeNullOrEmpty
            $results | Should -BeOfType PSCustomObject
        }

        It "Has the expected default display properties" {
            $defaultProps = $results.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @("ComputerName", "InstanceName", "SqlInstance", "Database", "DatabaseID", "Certificate", "Path", "Key", "Status")
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }

        It "Has the expected excluded properties" {
            $defaultProps = $results.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $excludedProps = @("exportPathCert", "exportPathKey", "ExportPath", "ExportKey")
            foreach ($prop in $excludedProps) {
                $defaultProps | Should -Not -Contain $prop -Because "property '$prop' should be excluded from the default display set"
            }
        }
    }

    Context "Can backup a database certificate with a filename (see #9485)" {
        It "Returns results with proper data" {
            $splatBackupCertWithName = @{
                SqlInstance        = $TestConfig.InstanceSingle
                Database           = $db1Name
                Certificate        = $cert1.Name
                EncryptionPassword = $pw
                DecryptionPassword = $pw
                FileBaseName       = "dbatoolscli_cert1_$random"
            }
            $results = Backup-DbaDbCertificate @splatBackupCertWithName

            $results.Certificate | Should -Be $cert1.Name
            $results.Status | Should -BeExactly "Success"
            $results.DatabaseID | Should -Be $db1.ID
            [IO.Path]::GetFileNameWithoutExtension($results.Path) | Should -Be "dbatoolscli_cert1_$random"
        }
    }

    Context "Warns the caller if the cert cannot be found" {
        It "Does warn" {
            $invalidDBCertName = "dbatoolscli_invalidCertName"
            $invalidDBCertName = "dbatoolscli_invalidCertName"
            $invalidDBCertName2 = "dbatoolscli_invalidCertName2"
            $splatBackupInvalidCert = @{
                SqlInstance        = $TestConfig.InstanceSingle
                Database           = $db1Name
                Certificate        = @($invalidDBCertName, $invalidDBCertName2, $cert2.Name)
                EncryptionPassword = $pw
                DecryptionPassword = $pw
                WarningAction      = "SilentlyContinue"
            }
            $results = Backup-DbaDbCertificate @splatBackupInvalidCert

            $WarnVar | Should -Match "Database certificate\(s\) .* not found"
        }
    }

    Context "Backs up all db certs for a database" {
        It "Returns results with proper data" {
            $splatBackupDbCerts = @{
                SqlInstance        = $TestConfig.InstanceSingle
                Database           = $db1Name
                EncryptionPassword = $pw
                DecryptionPassword = $pw
            }
            $results = Backup-DbaDbCertificate @splatBackupDbCerts

            $results | Should -HaveCount 2
            $results.Certificate | Should -Be $cert1.Name, $cert2.Name
        }
    }

    Context "Backs up all db certs for an instance" {
        It "Returns results with proper data" {
            $splatBackupAllCerts = @{
                SqlInstance        = $TestConfig.InstanceSingle
                EncryptionPassword = $pw
                DecryptionPassword = $pw
            }
            $results = Backup-DbaDbCertificate @splatBackupAllCerts

            $results | Should -HaveCount 3
            $results.Certificate | Should -Be $cert1.Name, $cert2.Name, $cert3.Name
        }
    }
}
