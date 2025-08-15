#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDbEncryptionKey",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Validate parameters" {
        BeforeAll {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "ExcludeDatabase",
                "InputObject",
                "EnableException"
            )
        }

        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

        # For all the backups that we want to clean up after the test, we create a directory that we can delete at the end.
        # Other files can be written there as well, maybe we change the name of that variable later. But for now we focus on backups.
        $backupPath = "$($TestConfig.Temp)\$CommandName-$(Get-Random)"
        $null = New-Item -Path $backupPath -ItemType Directory

        # Explain what needs to be set up for the test:
        # We need to create a database with encryption key which requires a service master key and certificate

        # Set variables. They are available in all the It blocks.
        $encryptionPassword = ConvertTo-SecureString "dbatools.IO" -AsPlainText -Force
        $shouldDeleteMasterKey = $false
        $shouldDeleteMasterCert = $false
        $testDbName = "dbatoolsci_encryptiontest_$(Get-Random)"

        # Create the objects.
        $masterKey = Get-DbaDbMasterKey -SqlInstance $TestConfig.instance2 -Database master
        if (-not $masterKey) {
            $shouldDeleteMasterKey = $true
            $masterKey = New-DbaServiceMasterKey -SqlInstance $TestConfig.instance2 -SecurePassword $encryptionPassword
        }

        $masterCert = Get-DbaDbCertificate -SqlInstance $TestConfig.instance2 -Database master | Where-Object Name -notmatch "##" | Select-Object -First 1
        if (-not $masterCert) {
            $shouldDeleteMasterCert = $true
            $masterCert = New-DbaDbCertificate -SqlInstance $TestConfig.instance2
        }

        $testDb = New-DbaDatabase -SqlInstance $TestConfig.instance2 -Name $testDbName
        $testDb | New-DbaDbMasterKey -SecurePassword $encryptionPassword
        $testDb | New-DbaDbCertificate
        $testDb | New-DbaDbEncryptionKey -Force

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove('*-Dba*:EnableException')
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

        # Cleanup all created objects.
        if ($testDb) {
            $testDb | Remove-DbaDatabase
        }
        if ($shouldDeleteMasterCert) {
            $masterCert | Remove-DbaDbCertificate
        }
        if ($shouldDeleteMasterKey) {
            $masterKey | Remove-DbaDbMasterKey
        }

        # Remove the backup directory.
        Remove-Item -Path $backupPath -Recurse -ErrorAction SilentlyContinue

        # As this is the last block we do not need to reset the $PSDefaultParameterValues.
    }

    Context "Command actually works" {
        It "should get an encryption key on a database using piping" {
            $encryptionKeyResults = $testDb | Get-DbaDbEncryptionKey
            $encryptionKeyResults.EncryptionType | Should -Be "ServerCertificate"
        }

        It "should get an encryption key on a database" {
            $encryptionKeyResults = Get-DbaDbEncryptionKey -SqlInstance $TestConfig.instance2 -Database $testDbName
            $encryptionKeyResults.EncryptionType | Should -Be "ServerCertificate"
        }
    }
}