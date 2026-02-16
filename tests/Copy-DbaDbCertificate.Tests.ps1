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
            $results = Copy-DbaDbCertificate @splatCopyCert -OutVariable "global:dbatoolsciOutput"

            $results.Notes | Should -BeNullOrEmpty
            $results.Status | Should -Be "Successful"

            $sourceDb = Get-DbaDatabase -SqlInstance $TestConfig.InstanceCopy1 -Database dbatoolscopycred
            $destDb = Get-DbaDatabase -SqlInstance $TestConfig.InstanceCopy2 -Database dbatoolscopycred

            $results.SourceDatabaseID | Should -Be $sourceDb.ID
            $results.DestinationDatabaseID | Should -Be $destDb.ID

            Get-DbaDbCertificate -SqlInstance $TestConfig.InstanceCopy2 -Database dbatoolscopycred -Certificate $certificateName | Should -Not -BeNullOrEmpty
        }
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return a PSCustomObject" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [PSCustomObject]
        }

        It "Should have the custom dbatools type name" {
            $global:dbatoolsciOutput[0].PSObject.TypeNames | Should -Contain "dbatools.MigrationObject"
        }

        It "Should have the correct default display columns" {
            $expectedColumns = @(
                "DateTime",
                "SourceServer",
                "DestinationServer",
                "Name",
                "Type",
                "Status",
                "Notes"
            )
            $defaultColumns = $global:dbatoolsciOutput[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            Compare-Object -ReferenceObject $expectedColumns -DifferenceObject $defaultColumns | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "PSCustomObject"
        }
    }
}