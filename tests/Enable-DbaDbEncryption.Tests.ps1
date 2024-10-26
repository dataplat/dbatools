#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0"}
param(
    $ModuleName = "dbatools",
    $PSDefaultParameterValues = ($TestConfig = Get-TestConfig).Defaults
)

Describe "Enable-DbaDbEncryption" -Tag "UnitTests" {
    Context "Parameter validation" {
        BeforeAll {
            $command = Get-Command Enable-DbaDbEncryption
            $expected = $TestConfig.CommonParameters
            $expected += @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "EncryptorName",
                "InputObject",
                "Force",
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

Describe "Enable-DbaDbEncryption" -Tag "IntegrationTests" {
    BeforeAll {
        $PSDefaultParameterValues["*:Confirm"] = $false
        $passwd = ConvertTo-SecureString "dbatools.IO" -AsPlainText -Force

        $masterkey = Get-DbaDbMasterKey -SqlInstance $TestConfig.instance2 -Database master
        if (-not $masterkey) {
            $global:delmasterkey = $true
            $masterkey = New-DbaServiceMasterKey -SqlInstance $TestConfig.instance2 -SecurePassword $passwd
        }

        $mastercert = Get-DbaDbCertificate -SqlInstance $TestConfig.instance2 -Database master |
            Where-Object Name -notmatch "##" |
            Select-Object -First 1

        if (-not $mastercert) {
            $global:delmastercert = $true
            $mastercert = New-DbaDbCertificate -SqlInstance $TestConfig.instance2
        }

        $global:testDb = New-DbaDatabase -SqlInstance $TestConfig.instance2
        $testDb | New-DbaDbMasterKey -SecurePassword $passwd
        $testDb | New-DbaDbCertificate
        $testDb | New-DbaDbEncryptionKey -Force
    }

    AfterAll {
        if ($testDb) {
            $testDb | Remove-DbaDatabase
        }
        if ($delmastercert) {
            $mastercert | Remove-DbaDbCertificate
        }
        if ($delmasterkey) {
            $masterkey | Remove-DbaDbMasterKey
        }
    }

    Context "When enabling encryption via pipeline" {
        It "Should enable encryption on a database" {
            $results = $testDb | Enable-DbaDbEncryption -EncryptorName $mastercert.Name -Force
            $results.EncryptionEnabled | Should -Be $true
        }
    }

    Context "When enabling encryption directly" {
        BeforeAll {
            $null = Disable-DbaDbEncryption -SqlInstance $TestConfig.instance2 -Database $testDb.Name
        }

        It "Should enable encryption on a database" {
            $results = Enable-DbaDbEncryption -SqlInstance $TestConfig.instance2 -EncryptorName $mastercert.Name -Database $testDb.Name -Force
            $results.EncryptionEnabled | Should -Be $true
        }
    }
}
