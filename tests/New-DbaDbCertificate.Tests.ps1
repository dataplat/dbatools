#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "New-DbaDbCertificate",
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
                "Name",
                "Database",
                "Subject",
                "StartDate",
                "ExpirationDate",
                "ActiveForServiceBrokerDialog",
                "SecurePassword",
                "InputObject",
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
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Create tempdb master key for testing
            $splatTempDbKey = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = "tempdb"
                Password    = $(ConvertTo-SecureString -String "GoodPass1234!" -AsPlainText -Force)
            }
            $tempdbmasterkey = New-DbaDbMasterKey @splatTempDbKey

            # Generate unique certificate names
            $certificateName1 = "Cert_$(Get-Random)"
            $certificateName2 = "Cert_$(Get-Random)"

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Cleanup master keys
            if ($tempdbmasterkey) {
                $tempdbmasterkey | Remove-DbaDbMasterKey
            }

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Successfully creates a new database certificate in default, master database" {
            $splatCert1 = @{
                SqlInstance = $TestConfig.InstanceSingle
                Name        = $certificateName1
            }
            $cert1 = New-DbaDbCertificate @splatCert1

            "$($cert1.name)" -match $certificateName1 | Should -Be $true

            # Cleanup
            $null = $cert1 | Remove-DbaDbCertificate
        }

        It "Successfully creates a new database certificate in the tempdb database" {
            $splatCert2 = @{
                SqlInstance = $TestConfig.InstanceSingle
                Name        = $certificateName2
                Database    = "tempdb"
            }
            $cert2 = New-DbaDbCertificate @splatCert2

            "$($cert2.Database)" -match "tempdb" | Should -Be $true

            # Cleanup
            $null = $cert2 | Remove-DbaDbCertificate
        }
    }

    Context "Output validation" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $outputCertName = "dbatoolsci_outcert_$(Get-Random)"
            $splatOutputCert = @{
                SqlInstance = $TestConfig.InstanceSingle
                Name        = $outputCertName
            }
            $result = New-DbaDbCertificate @splatOutputCert

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            if ($outputCertName) {
                $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
                $server.Databases["master"].Query("IF EXISTS (SELECT 1 FROM sys.certificates WHERE name = '$outputCertName') DROP CERTIFICATE [$outputCertName]")
            }
        }

        It "Returns output of the documented type" {
            $result | Should -Not -BeNullOrEmpty
            $result[0].psobject.TypeNames | Should -Contain "Microsoft.SqlServer.Management.Smo.Certificate"
        }

        It "Has the expected default display properties" {
            $result | Should -Not -BeNullOrEmpty
            $defaultProps = $result[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Database",
                "Name",
                "Subject",
                "StartDate",
                "ActiveForServiceBrokerDialog",
                "ExpirationDate",
                "Issuer",
                "LastBackupDate",
                "Owner",
                "PrivateKeyEncryptionType",
                "Serial"
            )
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }
    }
}