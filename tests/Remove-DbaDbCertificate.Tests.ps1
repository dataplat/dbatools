#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName   = "dbatools",
    $CommandName = "Remove-DbaDbCertificate",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "Certificate",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Can remove a database certificate" {
        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            if ($masterKey) { $masterkey | Remove-DbaDbMasterKey -Confirm:$false }

            # As this is the last block we do not need to reset the $PSDefaultParameterValues.
        }

        It "Successfully removes database certificate in master" {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            if (-not (Get-DbaDbMasterKey -SqlInstance $TestConfig.instance1 -Database master)) {
                $masterkey = New-DbaDbMasterKey -SqlInstance $TestConfig.instance1 -Database master -Password $(ConvertTo-SecureString -String "GoodPass1234!" -AsPlainText -Force) -Confirm:$false
            }

            # Create and then remove a database certificate for testing
            $results = New-DbaDbCertificate -SqlInstance $TestConfig.instance1 -Confirm:$false | Remove-DbaDbCertificate -Confirm:$false

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")

            "$($results.Status)" -match "Success" | Should -Be $true
        }
    }
}