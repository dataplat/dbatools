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
        $mastercert = Get-DbaDbCertificate -SqlInstance $TestConfig.InstanceSingle -Database master | Where-Object Name -notmatch "##" | Select-Object -First 1
        if (-not $mastercert) {
            $delmastercert = $true
            $mastercert = New-DbaDbCertificate -SqlInstance $TestConfig.InstanceSingle
        }

        $db = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle
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
            # Wait for encryption to complete before trying to disable
            $timeout = 120
            $elapsed = 0
            $encrypted = $false
            do {
                Start-Sleep -Seconds 2
                $elapsed += 2
                $db.Refresh()
                $dbState = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database master -Query "SELECT encryption_state FROM sys.dm_database_encryption_keys WHERE database_id = DB_ID('$($db.Name)')"
                $encrypted = ($dbState.encryption_state -eq 3)
            } while (-not $encrypted -and $elapsed -lt $timeout)

            $results = Stop-DbaDbEncryption -SqlInstance $TestConfig.InstanceSingle -WarningVariable warn
            $warn | Should -BeNullOrEmpty
            foreach ($result in $results) {
                $result.EncryptionEnabled | Should -Be $false
            }
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Wait for encryption to complete before testing output
            $timeout = 120
            $elapsed = 0
            $encrypted = $false
            do {
                Start-Sleep -Seconds 2
                $elapsed += 2
                $db.Refresh()
                $dbState = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database master -Query "SELECT encryption_state FROM sys.dm_database_encryption_keys WHERE database_id = DB_ID('$($db.Name)')"
                $encrypted = ($dbState.encryption_state -eq 3)
            } while (-not $encrypted -and $elapsed -lt $timeout)

            $result = Stop-DbaDbEncryption -SqlInstance $TestConfig.InstanceSingle -EnableException

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Returns PSCustomObject" {
            $result.PSObject.TypeNames | Should -Contain "System.Management.Automation.PSCustomObject"
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "DatabaseName",
                "EncryptionEnabled"
            )
            $actualProps = $result[0].PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }
    }

    Context "Parallel processing" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $passwd = ConvertTo-SecureString "dbatools.IO" -AsPlainText -Force
            $parallelMastercert = Get-DbaDbCertificate -SqlInstance $TestConfig.InstanceSingle -Database master | Where-Object Name -notmatch "##" | Select-Object -First 1
            if (-not $parallelMastercert) {
                $parallelDelmastercert = $true
                $parallelMastercert = New-DbaDbCertificate -SqlInstance $TestConfig.InstanceSingle
            }

            $parallelDatabases = @()
            1..3 | ForEach-Object {
                $parallelDb = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle
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
            # Wait for encryption to complete on all databases before trying to disable
            $timeout = 120
            $elapsed = 0
            $allEncrypted = $false
            do {
                Start-Sleep -Seconds 2
                $elapsed += 2
                $encryptedCount = 0
                foreach ($parallelDb in $parallelDatabases) {
                    $parallelDb.Refresh()
                    $dbState = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database master -Query "SELECT encryption_state FROM sys.dm_database_encryption_keys WHERE database_id = DB_ID('$($parallelDb.Name)')"
                    if ($dbState.encryption_state -eq 3) {
                        $encryptedCount++
                    }
                }
                $allEncrypted = ($encryptedCount -eq $parallelDatabases.Count)
            } while (-not $allEncrypted -and $elapsed -lt $timeout)

            $results = Stop-DbaDbEncryption -SqlInstance $TestConfig.InstanceSingle -Parallel -WarningVariable warn
            $warn | Should -BeNullOrEmpty
            $results.Count | Should -BeGreaterOrEqual 3
            foreach ($result in $results) {
                $result.EncryptionEnabled | Should -Be $false
            }
        }
    }

    Context "Output with -Parallel" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $passwd = ConvertTo-SecureString "dbatools.IO" -AsPlainText -Force
            $parallelOutputMastercert = Get-DbaDbCertificate -SqlInstance $TestConfig.InstanceSingle -Database master | Where-Object Name -notmatch "##" | Select-Object -First 1
            if (-not $parallelOutputMastercert) {
                $parallelOutputDelmastercert = $true
                $parallelOutputMastercert = New-DbaDbCertificate -SqlInstance $TestConfig.InstanceSingle
            }

            $parallelOutputDatabases = @()
            1..2 | ForEach-Object {
                $parallelOutputDb = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle
                $parallelOutputDb | New-DbaDbMasterKey -SecurePassword $passwd
                $parallelOutputDb | New-DbaDbCertificate
                $parallelOutputDb | New-DbaDbEncryptionKey -Force
                $parallelOutputDb | Enable-DbaDbEncryption -EncryptorName $parallelOutputMastercert.Name -Force
                $parallelOutputDatabases += $parallelOutputDb
            }

            # Wait for encryption to complete on all databases
            $timeout = 120
            $elapsed = 0
            $allEncrypted = $false
            do {
                Start-Sleep -Seconds 2
                $elapsed += 2
                $encryptedCount = 0
                foreach ($parallelOutputDb in $parallelOutputDatabases) {
                    $parallelOutputDb.Refresh()
                    $dbState = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database master -Query "SELECT encryption_state FROM sys.dm_database_encryption_keys WHERE database_id = DB_ID('$($parallelOutputDb.Name)')"
                    if ($dbState.encryption_state -eq 3) {
                        $encryptedCount++
                    }
                }
                $allEncrypted = ($encryptedCount -eq $parallelOutputDatabases.Count)
            } while (-not $allEncrypted -and $elapsed -lt $timeout)

            $parallelResult = Stop-DbaDbEncryption -SqlInstance $TestConfig.InstanceSingle -Parallel -EnableException

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            if ($parallelOutputDatabases) {
                $parallelOutputDatabases | Remove-DbaDatabase
            }
            if ($parallelOutputDelmastercert) {
                $parallelOutputMastercert | Remove-DbaDbCertificate
            }

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Includes Status and Error properties when -Parallel specified" {
            $parallelResult[0].PSObject.Properties.Name | Should -Contain "Status"
            $parallelResult[0].PSObject.Properties.Name | Should -Contain "Error"
        }
    }
}