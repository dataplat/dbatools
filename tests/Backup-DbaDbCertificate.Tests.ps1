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
        $random = Get-Random
        $db1Name = "dbatoolscli_$random"
        $db1 = New-DbaDatabase -SqlInstance $TestConfig.instance1 -Name $db1Name
        $pw = ConvertTo-SecureString -String "GoodPass1234!" -AsPlainText -Force
        if (-not (Get-DbaDbMasterKey -SqlInstance $TestConfig.instance1 -Database $db1Name)) {
            $masterkey = New-DbaDbMasterKey -SqlInstance $TestConfig.instance1 -Database $db1Name -Password $pw -Confirm:$false
        }

        $cert = New-DbaDbCertificate -SqlInstance $TestConfig.instance1 -Database $db1Name -Confirm:$false -Password $pw -Name dbatoolscli_cert1_$random
        $cert2 = New-DbaDbCertificate -SqlInstance $TestConfig.instance1 -Database $db1Name -Confirm:$false -Password $pw -Name dbatoolscli_cert2_$random
    }
    AfterAll {
        Remove-DbaDatabase -SqlInstance $TestConfig.instance1 -Database $db1Name -Confirm:$false
    }

    Context "Can create and backup a database certificate" {
        It "backs up the db cert" {
            $results = Backup-DbaDbCertificate -SqlInstance $TestConfig.instance1 -Certificate $cert.Name -Database $db1Name -EncryptionPassword $pw -DecryptionPassword $pw
            $null = Get-ChildItem -Path $results.Path -ErrorAction Ignore | Remove-Item -Confirm:$false -ErrorAction Ignore
            $results.Certificate | Should -Be $cert.Name
            $results.Status | Should -Match "Success"
            $results.DatabaseID | Should -Be (Get-DbaDatabase -SqlInstance $TestConfig.instance1 -Database $db1Name).ID
        }

        It "backs up the db cert with a filename (see #9485)" {
            $results = Backup-DbaDbCertificate -SqlInstance $TestConfig.instance1 -Certificate $cert.Name -Database $db1Name -EncryptionPassword $pw -DecryptionPassword $pw -FileBaseName "dbatoolscli_cert1_$random"
            $results.Certificate | Should -Be $cert.Name
            $results.Status | Should -Match "Success"
            $results.DatabaseID | Should -Be (Get-DbaDatabase -SqlInstance $TestConfig.instance1 -Database $db1Name).ID
            [IO.Path]::GetFileNameWithoutExtension($results.Path) | Should -Be "dbatoolscli_cert1_$random"
            $null = Get-ChildItem -Path $results.Path -ErrorAction Ignore | Remove-Item -Confirm:$false -ErrorAction Ignore
        }

        It "warns the caller if the cert cannot be found" {
            $invalidDBCertName = "dbatoolscli_invalidCertName"
            $invalidDBCertName2 = "dbatoolscli_invalidCertName2"
            $results = Backup-DbaDbCertificate -SqlInstance $TestConfig.instance1 -Certificate $invalidDBCertName, $invalidDBCertName2, $cert2.Name -Database $db1Name -EncryptionPassword $pw -DecryptionPassword $pw -WarningVariable warnVariable 3> $null
            $null = Get-ChildItem -Path $results.Path -ErrorAction Ignore | Remove-Item -Confirm:$false -ErrorAction Ignore
            $warnVariable | Should -BeLike "*Database certificate(s) * not found*"
        }

        It "backs up all db certs for a database" -Skip {
            $results = Backup-DbaDbCertificate -SqlInstance $TestConfig.instance1 -Database $db1Name -EncryptionPassword $pw -DecryptionPassword $pw
            $null = Get-ChildItem -Path $results.Path -ErrorAction Ignore | Remove-Item -Confirm:$false -ErrorAction Ignore
            $results.length | Should -Be 2
            $results.Certificate | Should -Be $cert.Name, $cert2.Name
        }

        It "backs up all db certs for an instance" -Skip {
            $results = Backup-DbaDbCertificate -SqlInstance $TestConfig.instance1 -EncryptionPassword $pw
            $null = Get-ChildItem -Path $results.Path -ErrorAction Ignore | Remove-Item -Confirm:$false -ErrorAction Ignore
        }

    }
}
