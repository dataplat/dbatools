#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0"}
param(
    $ModuleName = "dbatools",
    $PSDefaultParameterValues = ($TestConfig = Get-TestConfig).Defaults
)

Describe "Backup-DbaDbCertificate" -Tag "UnitTests" {
    Context "Parameter validation" {
        BeforeAll {
            $command = Get-Command Backup-DbaDbCertificate
            $expected = $TestConfig.CommonParameters
            $expected += @(
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
                "EnableException",
                "Confirm",
                "WhatIf"
            )
        }

        It "Has parameter: <_>" -ForEach $expected {
            $command | Should -HaveParameter $PSItem
        }

        It "Should have exactly the number of expected parameters ($($expected.Count))" {
            $hasparms = $command.Parameters.Values.Name
            Compare-Object -ReferenceObject $expected -DifferenceObject $hasparms | Should -BeNullOrEmpty
        }
    }
}

Describe "Backup-DbaDbCertificate" -Tag "IntegrationTests" {
    BeforeAll {
        $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

        $random = Get-Random
        $db1Name = "dbatoolscli_db1_$random"
        $db2Name = "dbatoolscli_db2_$random"
        $pw = ConvertTo-SecureString -String "GoodPass1234!" -AsPlainText -Force

        $db1 = New-DbaDatabase -SqlInstance $TestConfig.instance1 -Name $db1Name
        $null = New-DbaDbMasterKey -SqlInstance $TestConfig.instance1 -Database $db1Name -Password $pw

        $db2 = New-DbaDatabase -SqlInstance $TestConfig.instance1 -Name $db2Name
        $null = New-DbaDbMasterKey -SqlInstance $TestConfig.instance1 -Database $db2Name -Password $pw

        $cert1 = New-DbaDbCertificate -SqlInstance $TestConfig.instance1 -Database $db1Name -Password $pw -Name dbatoolscli_cert1_$random
        $cert2 = New-DbaDbCertificate -SqlInstance $TestConfig.instance1 -Database $db1Name -Password $pw -Name dbatoolscli_cert2_$random
        $cert3 = New-DbaDbCertificate -SqlInstance $TestConfig.instance1 -Database $db2Name -Password $pw -Name dbatoolscli_cert3_$random

        $PSDefaultParameterValues.Remove('*-Dba*:EnableException')
    }
    AfterAll {
        $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

        Remove-DbaDatabase -SqlInstance $TestConfig.instance1 -Database $db1Name, $db2Name
    }

    Context "Can backup a database certificate" {
        BeforeAll {
            $results = Backup-DbaDbCertificate -SqlInstance $TestConfig.instance1 -Database $db1Name -Certificate $cert1.Name -EncryptionPassword $pw -DecryptionPassword $pw
        }

        AfterAll {
            Remove-Item -Path $results.Path
            Remove-Item -Path $results.Key
        }

        It "Returns results with proper data" {
            $results.Certificate | Should -Be $cert1.Name
            $results.Status | Should -Match "Success"
            $results.DatabaseID | Should -Be $db1.ID
        }
    }

    Context "Can backup a database certificate with a filename (see #9485)" {
        BeforeAll {
            $results = Backup-DbaDbCertificate -SqlInstance $TestConfig.instance1 -Database $db1Name -Certificate $cert1.Name -EncryptionPassword $pw -DecryptionPassword $pw -FileBaseName "dbatoolscli_cert1_$random"
        }

        AfterAll {
            Remove-Item -Path $results.Path
            Remove-Item -Path $results.Key
        }

        It "Returns results with proper data" {
            $results.Certificate | Should -Be $cert1.Name
            $results.Status | Should -Match "Success"
            $results.DatabaseID | Should -Be $db1.ID
            [IO.Path]::GetFileNameWithoutExtension($results.Path) | Should -Be "dbatoolscli_cert1_$random"
        }
    }

    Context "Warns the caller if the cert cannot be found" {
        BeforeAll {
            $invalidDBCertName = "dbatoolscli_invalidCertName"
            $invalidDBCertName2 = "dbatoolscli_invalidCertName2"
            $results = Backup-DbaDbCertificate -SqlInstance $TestConfig.instance1 -Database $db1Name -Certificate $invalidDBCertName, $invalidDBCertName2, $cert2.Name -EncryptionPassword $pw -DecryptionPassword $pw -WarningAction SilentlyContinue
        }

        AfterAll {
            Remove-Item -Path $results.Path
            Remove-Item -Path $results.Key
        }

        It "Does warn" {
            $WarnVar | Should -BeLike "*Database certificate(s) * not found*"
        }
    }

    Context "Backs up all db certs for a database" {
        BeforeAll {
            $results = Backup-DbaDbCertificate -SqlInstance $TestConfig.instance1 -Database $db1Name -EncryptionPassword $pw -DecryptionPassword $pw
        }

        AfterAll {
            Remove-Item -Path $results.Path
            Remove-Item -Path $results.Key
        }

        It "Returns results with proper data" {
            $results | Should -HaveCount 2
            $results.Certificate | Should -Be $cert1.Name, $cert2.Name
        }
    }

    Context "Backs up all db certs for an instance" {
        BeforeAll {
            $results = Backup-DbaDbCertificate -SqlInstance $TestConfig.instance1 -EncryptionPassword $pw -DecryptionPassword $pw
        }

        AfterAll {
            Remove-Item -Path $results.Path
            Remove-Item -Path $results.Key
        }

        It "Returns results with proper data" {
            $results | Should -BeGreaterOrEqual 3
            $results.Certificate | Should -Contain $cert1.Name
            $results.Certificate | Should -Contain $cert2.Name
            $results.Certificate | Should -Contain $cert3.Name
        }
    }
}