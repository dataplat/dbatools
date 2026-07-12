#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Enable-DbaDbEncryption",
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
                "EncryptorName",
                "InputObject",
                "Force",
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

        $mastercert = Get-DbaDbCertificate -SqlInstance $TestConfig.InstanceSingle -Database master |
            Where-Object Name -notmatch "##" |
            Select-Object -First 1

        if (-not $mastercert) {
            $delmastercert = $true
            $mastercert = New-DbaDbCertificate -SqlInstance $TestConfig.InstanceSingle
        }

        $testDb = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle
        $testDb | New-DbaDbMasterKey -SecurePassword $passwd
        $testDb | New-DbaDbCertificate
        $testDb | New-DbaDbEncryptionKey -Force

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        if ($testDb) {
            $testDb | Remove-DbaDatabase -ErrorAction SilentlyContinue
        }
        if ($delmastercert) {
            $mastercert | Remove-DbaDbCertificate -ErrorAction SilentlyContinue
        }

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When enabling encryption via pipeline" {
        It "Should enable encryption on a database" {
            $results = @($testDb | Enable-DbaDbEncryption -EncryptorName $mastercert.Name -Force)
            $results[0].EncryptionEnabled | Should -Be $true
        }
    }

    Context "When enabling encryption directly" {
        It "Should enable encryption on a database" {
            # The pipeline test above starts an asynchronous TDE encryption scan and
            # ALTER DATABASE fails while any scan is still running, so wait for the
            # scan to settle before disabling encryption for this scenario
            $splatScanState = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = "master"
                Query       = "SELECT encryption_state FROM sys.dm_database_encryption_keys WHERE database_id = DB_ID('$($testDb.Name)')"
                As          = "SingleValue"
            }
            $scanDeadline = (Get-Date).AddSeconds(120)
            do {
                $scanState = Invoke-DbaQuery @splatScanState
                if ($scanState -notin 2, 4, 5, 6) {
                    break
                }
                Start-Sleep -Seconds 1
            } while ((Get-Date) -lt $scanDeadline)

            $null = Disable-DbaDbEncryption -SqlInstance $TestConfig.InstanceSingle -Database $testDb.Name
            $splatEnableEncryption = @{
                SqlInstance   = $TestConfig.InstanceSingle
                EncryptorName = $mastercert.Name
                Database      = $testDb.Name
                Force         = $true
            }
            $results = @(Enable-DbaDbEncryption @splatEnableEncryption)
            $results[0].EncryptionEnabled | Should -Be $true
        }
    }
}