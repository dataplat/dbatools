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

        It "Returns output of the expected type" {
            $results | Should -Not -BeNullOrEmpty
            $results[0].psobject.TypeNames | Should -Contain "dbatools.MigrationObject"
        }

        It "Has the expected default display properties" {
            if (-not $results) { Set-ItResult -Skipped -Because "no result to validate" }
            $defaultProps = $results[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @("DateTime", "SourceServer", "DestinationServer", "Name", "Type", "Status", "Notes")
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }

        It "Has the expected additional properties" {
            if (-not $results) { Set-ItResult -Skipped -Because "no result to validate" }
            $results[0].psobject.Properties.Name | Should -Contain "SourceDatabase"
            $results[0].psobject.Properties.Name | Should -Contain "SourceDatabaseID"
            $results[0].psobject.Properties.Name | Should -Contain "DestinationDatabase"
            $results[0].psobject.Properties.Name | Should -Contain "DestinationDatabaseID"
        }
    }
}