#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDbCertificate",
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
                "ExcludeDatabase",
                "Certificate",
                "Subject",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Can get a database certificate" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $certificateName1 = "Cert_$(Get-Random)"
            $certificateName2 = "Cert_$(Get-Random)"
            $dbName = "dbatoolscli_db1_$(Get-Random)"
            $pw = ConvertTo-SecureString -String "GoodPass1234!" -AsPlainText -Force

            $null = New-DbaDatabase -SqlInstance $TestConfig.instance1 -Name $dbName
            $null = New-DbaDbMasterKey -SqlInstance $TestConfig.instance1 -Database $dbName -Password $pw

            $cert1 = New-DbaDbCertificate -SqlInstance $TestConfig.instance1 -Database $dbName -Password $pw -Name $certificateName1
            $cert2 = New-DbaDbCertificate -SqlInstance $TestConfig.instance1 -Database $dbName -Password $pw -Name $certificateName2

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Cleanup all created objects
            Remove-DbaDatabase -SqlInstance $TestConfig.instance1 -Database $dbName

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Returns database certificate by certificate name" {
            $cert = Get-DbaDbCertificate -SqlInstance $TestConfig.instance1 -Certificate $certificateName1
            $cert.Database | Should -Match $dbName
            $cert.Name | Should -Match $certificateName1
        }

        It "Returns database certificates by database name" {
            $cert = Get-DbaDbCertificate -SqlInstance $TestConfig.instance1 -Database $dbName
            $cert | Should -HaveCount 2
            $cert.Name | Should -BeIn $certificateName1, $certificateName2
        }

        It "Returns database certificates excluding those in the test database" {
            $cert = Get-DbaDbCertificate -SqlInstance $TestConfig.instance1 -ExcludeDatabase $dbName
            $cert.Database | Should -Not -Match $dbName
            $cert.Name | Should -Not -BeIn $certificateName1, $certificateName2
        }
    }
}