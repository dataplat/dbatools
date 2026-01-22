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
    Context "Can copy a database certificate" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # For all the backups that we want to clean up after the test, we create a directory that we can delete at the end.
            $backupPath = "$($TestConfig.Temp)\$CommandName-$(Get-Random)"
            $null = New-Item -Path $backupPath -ItemType Directory

            $securePassword = ConvertTo-SecureString -String "GoodPass1234!" -AsPlainText -Force

            # Create test databases
            $testDatabases = New-DbaDatabase -SqlInstance $TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2 -Name dbatoolscopycred

            # Create master key and certificate on source
            $null = New-DbaDbMasterKey -SqlInstance $TestConfig.InstanceCopy1 -Database dbatoolscopycred -SecurePassword $securePassword
            $certificateName = "Cert_$(Get-Random)"
            $null = New-DbaDbCertificate -SqlInstance $TestConfig.InstanceCopy1 -Name $certificateName -Database dbatoolscopycred

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = $testDatabases | Remove-DbaDatabase -ErrorAction SilentlyContinue

            # Remove the backup directory.
            Remove-Item -Path $backupPath -Recurse

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Successfully copies a certificate" {
            $splatCopyCert = @{
                Source             = $TestConfig.InstanceCopy1
                Destination        = $TestConfig.InstanceCopy2
                EncryptionPassword = $securePassword
                MasterKeyPassword  = $securePassword
                Database           = "dbatoolscopycred"
                SharedPath         = $backupPath
            }
            $results = Copy-DbaDbCertificate @splatCopyCert

            $results.Notes | Should -BeNullOrEmpty
            $results.Status | Should -Be "Successful"

            $sourceDb = Get-DbaDatabase -SqlInstance $TestConfig.InstanceCopy1 -Database dbatoolscopycred
            $destDb = Get-DbaDatabase -SqlInstance $TestConfig.InstanceCopy2 -Database dbatoolscopycred

            $results.SourceDatabaseID | Should -Be $sourceDb.ID
            $results.DestinationDatabaseID | Should -Be $destDb.ID

            Get-DbaDbCertificate -SqlInstance $TestConfig.InstanceCopy2 -Database dbatoolscopycred -Certificate $certificateName | Should -Not -BeNullOrEmpty
        }
    }

    Context "Output Validation" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # For all the backups that we want to clean up after the test, we create a directory that we can delete at the end.
            $backupPath = "$($TestConfig.Temp)\$CommandName-OutputValidation-$(Get-Random)"
            $null = New-Item -Path $backupPath -ItemType Directory

            $securePassword = ConvertTo-SecureString -String "GoodPass1234!" -AsPlainText -Force

            # Create test databases
            $testDatabases = New-DbaDatabase -SqlInstance $TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2 -Name dbatoolscopyoutputtest

            # Create master key and certificate on source
            $null = New-DbaDbMasterKey -SqlInstance $TestConfig.InstanceCopy1 -Database dbatoolscopyoutputtest -SecurePassword $securePassword
            $certificateName = "OutputTestCert_$(Get-Random)"
            $null = New-DbaDbCertificate -SqlInstance $TestConfig.InstanceCopy1 -Name $certificateName -Database dbatoolscopyoutputtest

            # Copy the certificate to get output
            $splatCopyCert = @{
                Source             = $TestConfig.InstanceCopy1
                Destination        = $TestConfig.InstanceCopy2
                EncryptionPassword = $securePassword
                MasterKeyPassword  = $securePassword
                Database           = "dbatoolscopyoutputtest"
                SharedPath         = $backupPath
            }
            $result = Copy-DbaDbCertificate @splatCopyCert

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = $testDatabases | Remove-DbaDatabase -ErrorAction SilentlyContinue

            # Remove the backup directory.
            Remove-Item -Path $backupPath -Recurse -ErrorAction SilentlyContinue

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Returns PSCustomObject" {
            $result.PSObject.TypeNames | Should -Contain "System.Management.Automation.PSCustomObject"
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                'DateTime',
                'SourceServer',
                'DestinationServer',
                'Name',
                'Type',
                'Status',
                'Notes'
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }

        It "Has the documented additional properties" {
            $result.PSObject.Properties.Name | Should -Contain 'SourceDatabase'
            $result.PSObject.Properties.Name | Should -Contain 'SourceDatabaseID'
            $result.PSObject.Properties.Name | Should -Contain 'DestinationDatabase'
            $result.PSObject.Properties.Name | Should -Contain 'DestinationDatabaseID'
        }
    }
    }
}