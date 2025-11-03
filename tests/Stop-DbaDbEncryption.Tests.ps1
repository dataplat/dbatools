#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Stop-DbaDbEncryption",
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
                "Parallel",
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

        $passwd = ConvertTo-SecureString "dbatools.IO" -AsPlainText -Force
        $mastercert = Get-DbaDbCertificate -SqlInstance $TestConfig.instance2 -Database master | Where-Object Name -notmatch "##" | Select-Object -First 1
        if (-not $mastercert) {
            $delmastercert = $true
            $mastercert = New-DbaDbCertificate -SqlInstance $TestConfig.instance2
        }

        $db = New-DbaDatabase -SqlInstance $TestConfig.instance2
        $db | New-DbaDbMasterKey -SecurePassword $passwd
        $db | New-DbaDbCertificate
        $db | New-DbaDbEncryptionKey -Force
        $db | Enable-DbaDbEncryption -EncryptorName $mastercert.Name -Force

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        if ($db) {
            $db | Remove-DbaDatabase
        }
        if ($delmastercert) {
            $mastercert | Remove-DbaDbCertificate
        }

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Command actually works" {
        It "should disable encryption on a database with piping" {
            # Give it time to finish encrypting or it'll error
            Start-Sleep 10
            $results = Stop-DbaDbEncryption -SqlInstance $TestConfig.instance2 -WarningVariable warn
            $warn | Should -BeNullOrEmpty
            foreach ($result in $results) {
                $result.EncryptionEnabled | Should -Be $false
            }
        }
    }

    Context "Parallel processing" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $passwd = ConvertTo-SecureString "dbatools.IO" -AsPlainText -Force
            $parallelMastercert = Get-DbaDbCertificate -SqlInstance $TestConfig.instance2 -Database master | Where-Object Name -notmatch "##" | Select-Object -First 1
            if (-not $parallelMastercert) {
                $parallelDelmastercert = $true
                $parallelMastercert = New-DbaDbCertificate -SqlInstance $TestConfig.instance2
            }

            $parallelDatabases = @()
            1..3 | ForEach-Object {
                $parallelDb = New-DbaDatabase -SqlInstance $TestConfig.instance2
                $parallelDb | New-DbaDbMasterKey -SecurePassword $passwd
                $parallelDb | New-DbaDbCertificate
                $parallelDb | New-DbaDbEncryptionKey -Force
                $parallelDb | Enable-DbaDbEncryption -EncryptorName $parallelMastercert.Name -Force
                $parallelDatabases += $parallelDb
            }

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            if ($parallelDatabases) {
                $parallelDatabases | Remove-DbaDatabase
            }
            if ($parallelDelmastercert) {
                $parallelMastercert | Remove-DbaDbCertificate
            }

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "should disable encryption with -Parallel switch" {
            # Give it time to finish encrypting or it'll error
            Start-Sleep 10
            $results = Stop-DbaDbEncryption -SqlInstance $TestConfig.instance2 -Parallel -WarningVariable warn
            $warn | Should -BeNullOrEmpty
            $results.Count | Should -BeGreaterOrEqual 3
            $results.EncryptionEnabled | Should -All -Be $false
        }
    }
}