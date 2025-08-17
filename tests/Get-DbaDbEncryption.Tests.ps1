#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDbEncryption",
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
                "ExcludeDatabase",
                "IncludeSystemDBs",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Test Retriving Certificate" {
        BeforeAll {
            $random = Get-Random
            $cert = "dbatoolsci_getcert$random"
            $password = ConvertTo-SecureString -String Get-Random -AsPlainText -Force

            $splatCertificate = @{
                SqlInstance = $TestConfig.instance1
                Name        = $cert
                Password    = $password
            }
            New-DbaDbCertificate @splatCertificate

            $results = Get-DbaDbEncryption -SqlInstance $TestConfig.instance1
        }

        AfterAll {
            $splatRemove = @{
                SqlInstance = $TestConfig.instance1
                Certificate = $cert
            }
            Get-DbaDbCertificate @splatRemove | Remove-DbaDbCertificate
        }

        It "Should find a certificate named $cert" {
            ($results.Name -match "dbatoolsci").Count -gt 0 | Should -Be $true
        }
    }
}