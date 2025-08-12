#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Invoke-DbaAzSqlDbTip",
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
                "AzureDomain",
                "Tenant",
                "LocalFile",
                "Database",
                "ExcludeDatabase",
                "AllUserDatabases",
                "ReturnAllTips",
                "Compat100",
                "StatementTimeout",
                "EnableException",
                "Force"
            )
        }

        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Run the tips against Azure database" {
        BeforeAll {
            $skipTests = $env:azuredbpasswd -ne "failstoooften"
            if (-not $skipTests) {
                $securePassword = ConvertTo-SecureString $env:azuredbpasswd -AsPlainText -Force
                $azureCred = New-Object System.Management.Automation.PSCredential ($TestConfig.azuresqldblogin, $securePassword)
                $azureResults = Invoke-DbaAzSqlDbTip -SqlInstance $TestConfig.azureserver -Database "test" -SqlCredential $azureCred -ReturnAllTips
            }
        }

        It "Should get some results" -Skip:$skipTests {
            $azureResults | Should -Not -BeNullOrEmpty
        }

        It "Should have the right ComputerName" -Skip:$skipTests {
            $azureResults.ComputerName | Should -Be $TestConfig.azureserver
        }

        It "Database name should be 'test'" -Skip:$skipTests {
            $azureResults.Database | Should -Be "test"
        }
    }
}