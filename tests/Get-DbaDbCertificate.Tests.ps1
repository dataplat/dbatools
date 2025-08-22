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

            # Check and create master key if needed
            if (-not (Get-DbaDbMasterKey -SqlInstance $TestConfig.instance1 -Database master)) {
                $masterkey = New-DbaDbMasterKey -SqlInstance $TestConfig.instance1 -Database master -Password $(ConvertTo-SecureString -String "GoodPass1234!" -AsPlainText -Force) -Confirm:$false
            }

            # Create test objects
            $tempdbmasterkey = New-DbaDbMasterKey -SqlInstance $TestConfig.instance1 -Database tempdb -Password $(ConvertTo-SecureString -String "GoodPass1234!" -AsPlainText -Force) -Confirm:$false
            $certificateName1 = "Cert_$(Get-Random)"
            $certificateName2 = "Cert_$(Get-Random)"
            $cert1 = New-DbaDbCertificate -SqlInstance $TestConfig.instance1 -Name $certificateName1 -Confirm:$false
            $cert2 = New-DbaDbCertificate -SqlInstance $TestConfig.instance1 -Name $certificateName2 -Database tempdb -Confirm:$false

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Cleanup all created objects
            $null = $cert1 | Remove-DbaDbCertificate -Confirm:$false
            $null = $cert2 | Remove-DbaDbCertificate -Confirm:$false
            if ($tempdbmasterkey) { $tempdbmasterkey | Remove-DbaDbMasterKey -Confirm:$false }
            if ($masterKey) { $masterkey | Remove-DbaDbMasterKey -Confirm:$false }

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Returns database certificate created in default, master database" {
            $cert = Get-DbaDbCertificate -SqlInstance $TestConfig.instance1 -Certificate $certificateName1
            "$($cert.Database)" -match "master" | Should -BeTrue
            $cert.DatabaseId | Should -Be (Get-DbaDatabase -SqlInstance $TestConfig.instance1 -Database master).Id
        }

        It "Returns database certificate created in tempdb database, looked up by certificate name" {
            $cert = Get-DbaDbCertificate -SqlInstance $TestConfig.instance1 -Database tempdb
            "$($cert.Name)" -match $certificateName2 | Should -BeTrue
            $cert.DatabaseId | Should -Be (Get-DbaDatabase -SqlInstance $TestConfig.instance1 -Database tempdb).Id
        }

        It "Returns database certificates excluding those in the master database" {
            $cert = Get-DbaDbCertificate -SqlInstance $TestConfig.instance1 -ExcludeDatabase master
            "$($cert.Database)" -notmatch "master" | Should -BeTrue
        }
    }
}