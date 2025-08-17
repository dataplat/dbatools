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

            # Check if master key exists and create if needed
            if (-not (Get-DbaDbMasterKey -SqlInstance $TestConfig.instance1 -Database master)) {
                $splatMasterKey = @{
                    SqlInstance = $TestConfig.instance1
                    Database    = "master"
                    Password    = $(ConvertTo-SecureString -String "GoodPass1234!" -AsPlainText -Force)
                    Confirm     = $false
                }
                $masterkey = New-DbaDbMasterKey @splatMasterKey
            }

            # Create tempdb master key for testing
            $splatTempDbKey = @{
                SqlInstance = $TestConfig.instance1
                Database    = "tempdb"
                Password    = $(ConvertTo-SecureString -String "GoodPass1234!" -AsPlainText -Force)
                Confirm     = $false
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
                $tempdbmasterkey | Remove-DbaDbMasterKey -Confirm:$false
            }
            if ($masterKey) {
                $masterkey | Remove-DbaDbMasterKey -Confirm:$false
            }

            # As this is the last block we do not need to reset the $PSDefaultParameterValues.
        }

        It "Successfully creates a new database certificate in default, master database" {
            $splatCert1 = @{
                SqlInstance = $TestConfig.instance1
                Name        = $certificateName1
                Confirm     = $false
            }
            $cert1 = New-DbaDbCertificate @splatCert1

            "$($cert1.name)" -match $certificateName1 | Should -Be $true

            # Cleanup
            $null = $cert1 | Remove-DbaDbCertificate -Confirm:$false
        }

        It "Successfully creates a new database certificate in the tempdb database" {
            $splatCert2 = @{
                SqlInstance = $TestConfig.instance1
                Name        = $certificateName2
                Database    = "tempdb"
                Confirm     = $false
            }
            $cert2 = New-DbaDbCertificate @splatCert2

            "$($cert2.Database)" -match "tempdb" | Should -Be $true

            # Cleanup
            $null = $cert2 | Remove-DbaDbCertificate -Confirm:$false
        }
    }
}