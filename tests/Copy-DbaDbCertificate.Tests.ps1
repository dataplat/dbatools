#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Copy-DbaDbCertificate",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Source",
                "SourceSqlCredential",
                "Destination",
                "DestinationSqlCredential",
                "Database",
                "ExcludeDatabase",
                "Certificate",
                "ExcludeCertificate",
                "SharedPath",
                "MasterKeyPassword",
                "EncryptionPassword",
                "DecryptionPassword",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Can create a database certificate" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

            # For all the backups that we want to clean up after the test, we create a directory that we can delete at the end.
            $backupPath = "$($TestConfig.Temp)\$CommandName-$(Get-Random)"
            $null = New-Item -Path $backupPath -ItemType Directory

            $securePassword = ConvertTo-SecureString -String "GoodPass1234!" -AsPlainText -Force

            # Create master key on instance2
            $masterKey = New-DbaDbMasterKey -SqlInstance $TestConfig.instance2 -Database master -SecurePassword $securePassword -Confirm:$false -ErrorAction SilentlyContinue

            # Create test databases
            $testDatabases = New-DbaDatabase -SqlInstance $TestConfig.instance2, $TestConfig.instance3 -Name dbatoolscopycred

            # Create master key and certificate on source
            $null = New-DbaDbMasterKey -SqlInstance $TestConfig.instance2 -Database dbatoolscopycred -SecurePassword $securePassword -Confirm:$false
            $certificateName = "Cert_$(Get-Random)"
            $null = New-DbaDbCertificate -SqlInstance $TestConfig.instance2 -Name $certificateName -Database dbatoolscopycred -Confirm:$false

            # Setup copy parameters
            $splatCopyCert = @{
                Source             = $TestConfig.instance2
                Destination        = $TestConfig.instance3
                EncryptionPassword = $securePassword
                MasterKeyPassword  = $securePassword
                Database           = "dbatoolscopycred"
                SharedPath         = $backupPath
                Confirm            = $false
            }

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove('*-Dba*:EnableException')
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

            $null = $testDatabases | Remove-DbaDatabase -Confirm:$false -ErrorAction SilentlyContinue
            if ($masterKey) {
                $masterKey | Remove-DbaDbMasterKey -Confirm:$false -ErrorAction SilentlyContinue
            }

            # Remove the backup directory.
            Remove-Item -Path $backupPath -Recurse -ErrorAction SilentlyContinue

            # As this is the last block we do not need to reset the $PSDefaultParameterValues.
        }

        It "Successfully copies a certificate" -Skip:$true {
            $results = Copy-DbaDbCertificate @splatCopyCert | Where-Object SourceDatabase -eq "dbatoolscopycred" | Select-Object -First 1

            $results.Notes | Should -BeNullOrEmpty
            $results.Status | Should -Be "Successful"

            $sourceDb = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database dbatoolscopycred
            $destDb = Get-DbaDatabase -SqlInstance $TestConfig.instance3 -Database dbatoolscopycred

            $results.SourceDatabaseID | Should -Be $sourceDb.ID
            $results.DestinationDatabaseID | Should -Be $destDb.ID

            Get-DbaDbCertificate -SqlInstance $TestConfig.instance3 -Database dbatoolscopycred -Certificate $certificateName | Should -Not -BeNullOrEmpty
        }
    }
}