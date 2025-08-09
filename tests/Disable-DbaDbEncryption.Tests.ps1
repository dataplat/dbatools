#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Disable-DbaDbEncryption",
    $PSDefaultParameterValues = ($TestConfig = Get-TestConfig).Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        BeforeAll {
            $command = Get-Command $CommandName
            $expected = $TestConfig.CommonParameters
            $expected += @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "InputObject",
                "NoEncryptionKeyDrop",
                "EnableException"
            )
        }

        It "Has parameter: <PSItem>" -TestCases ($expected | ForEach-Object { @{ PSItem = $PSItem } }) {
            $command | Should -HaveParameter $PSItem
        }

        It "Should have exactly the number of expected parameters ($($expected.Count))" {
            $hasParameters = $command.Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            Compare-Object -ReferenceObject $expected -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
        
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
        
        # Store for use in contexts
        $global:mastercert = $mastercert
        
        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
        
        if ($testDb) {
            $testDb | Remove-DbaDatabase -Confirm:$false
        }
        if ($delmastercert) {
            $mastercert | Remove-DbaDbCertificate -Confirm:$false
        }
        if ($delmasterkey) {
            $masterkey | Remove-DbaDbMasterKey -Confirm:$false
        }
    }

    Context "When disabling encryption via pipeline" {
        BeforeAll {
            Start-Sleep -Seconds 10 # Allow encryption to complete
            $results = $testDb | Disable-DbaDbEncryption -NoEncryptionKeyDrop -WarningVariable WarnVar 3> $null
        }

        It "Should complete without warnings" {
            $WarnVar | Where-Object { $PSItem -NotLike "*Connect-DbaInstance*" } | Should -BeNullOrEmpty
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
            $results = Disable-DbaDbEncryption @splatDisable -WarningVariable WarnVar 3> $null
        }

        It "Should complete without warnings" {
            $WarnVar | Where-Object { $PSItem -NotLike "*Connect-DbaInstance*" } | Should -BeNullOrEmpty
        }

        It "Should disable encryption" {
            $results.EncryptionEnabled | Should -Be $false
        }
    }
}