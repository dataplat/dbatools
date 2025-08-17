#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Disable-DbaDbEncryption",
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
                "NoEncryptionKeyDrop",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*:Confirm"] = $false
        $passwd = ConvertTo-SecureString "dbatools.IO" -AsPlainText -Force

        # Setup master key if needed
        $masterkey = Get-DbaDbMasterKey -SqlInstance $TestConfig.instance2 -Database master
        if (-not $masterkey) {
            $global:delmasterkey = $true
            $masterkey = New-DbaServiceMasterKey -SqlInstance $TestConfig.instance2 -SecurePassword $passwd
        }

        # Setup master certificate if needed
        $mastercert = Get-DbaDbCertificate -SqlInstance $TestConfig.instance2 -Database master |
            Where-Object Name -notmatch "##" |
            Select-Object -First 1
        if (-not $mastercert) {
            $global:delmastercert = $true
            $mastercert = New-DbaDbCertificate -SqlInstance $TestConfig.instance2
        }

        # Create and configure test database
        $global:testDb = New-DbaDatabase -SqlInstance $TestConfig.instance2
        $testDb | New-DbaDbMasterKey -SecurePassword $passwd
        $testDb | New-DbaDbCertificate
        $testDb | New-DbaDbEncryptionKey -Force
        $testDb | Enable-DbaDbEncryption -EncryptorName $mastercert.Name -Force
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

    Context "When disabling encryption via pipeline" {
        BeforeAll {
            Start-Sleep -Seconds 10 # Allow encryption to complete
            $results = $testDb | Disable-DbaDbEncryption -NoEncryptionKeyDrop -WarningVariable warn 3> $null
        }

        It "Should complete without warnings" {
            $warn | Where-Object { $_ -NotLike "*Connect-DbaInstance*" } | Should -BeNullOrEmpty
        }

        It "Should disable encryption" {
            $results.EncryptionEnabled | Should -Be $false
        }
    }

    Context "When disabling encryption via parameters" {
        BeforeAll {
            $null = $testDb | Enable-DbaDbEncryption -EncryptorName $mastercert.Name -Force
            Start-Sleep -Seconds 10 # Allow encryption to complete

            $splatDisable = @{
                SqlInstance = $TestConfig.instance2
                Database    = $testDb.Name
            }
            $results = Disable-DbaDbEncryption @splatDisable -WarningVariable warn 3> $null
        }

        It "Should complete without warnings" {
            $warn | Where-Object { $_ -NotLike "*Connect-DbaInstance*" } | Should -BeNullOrEmpty
        }

        It "Should disable encryption" {
            $results.EncryptionEnabled | Should -Be $false
        }
    }
}