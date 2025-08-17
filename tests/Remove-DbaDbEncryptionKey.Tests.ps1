#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaDbEncryptionKey",
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
                "Database",
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

        $encryptionPasswd = ConvertTo-SecureString "dbatools.IO" -AsPlainText -Force
        $masterKeyExists = Get-DbaDbMasterKey -SqlInstance $TestConfig.instance2 -Database master
        if (-not $masterKeyExists) {
            $delmasterkey = $true
            $masterKeyExists = New-DbaServiceMasterKey -SqlInstance $TestConfig.instance2 -SecurePassword $encryptionPasswd
        }
        $masterCertExists = Get-DbaDbCertificate -SqlInstance $TestConfig.instance2 -Database master | Where-Object Name -notmatch "##" | Select-Object -First 1
        if (-not $masterCertExists) {
            $delmastercert = $true
            $masterCertExists = New-DbaDbCertificate -SqlInstance $TestConfig.instance2
        }

        $testDatabase = New-DbaDatabase -SqlInstance $TestConfig.instance2
        $testDatabase | New-DbaDbMasterKey -SecurePassword $encryptionPasswd
        $testDatabase | New-DbaDbCertificate
        $testDbEncryptionKey = $testDatabase | New-DbaDbEncryptionKey -Force

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        if ($testDatabase) {
            $testDatabase | Remove-DbaDatabase
        }
        if ($delmastercert) {
            $masterCertExists | Remove-DbaDbCertificate
        }
        if ($delmasterkey) {
            $masterKeyExists | Remove-DbaDbMasterKey
        }
    }

    Context "Command actually works" {
        It "should remove encryption key on a database using piping" {
            $results = $testDbEncryptionKey | Remove-DbaDbEncryptionKey
            $results.Status | Should -Be "Success"
            $testDatabase.Refresh()
            $testDatabase | Get-DbaDbEncryptionKey | Should -Be $null
        }
        It "should remove encryption key on a database" {
            $null = $testDatabase | New-DbaDbEncryptionKey -Force
            $results = Remove-DbaDbEncryptionKey -SqlInstance $TestConfig.instance2 -Database $testDatabase.Name
            $results.Status | Should -Be "Success"
            $testDatabase.Refresh()
            $testDatabase | Get-DbaDbEncryptionKey | Should -Be $null
        }
    }
}