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
        BeforeAll {
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
        }

        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>
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
                Confirm     = $false
            }
            Get-DbaDbCertificate @splatRemove | Remove-DbaDbCertificate -Confirm:$false
        }

        It "Should find a certificate named $cert" {
            ($results.Name -match "dbatoolsci").Count -gt 0 | Should -Be $true
        }
    }
}