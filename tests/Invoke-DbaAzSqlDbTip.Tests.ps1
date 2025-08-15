#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Invoke-DbaAzSqlDbTip",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

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

Describe $CommandName -Tag IntegrationTests -Skip:($env:azuredbpasswd -ne "failstoooften") {
    Context "Run the tips against Azure database" {
        BeforeAll {
            $securePassword = ConvertTo-SecureString $env:azuredbpasswd -AsPlainText -Force
            $splatCredential = @{
                UserName    = $TestConfig.azuresqldblogin
                Password    = $securePassword
                ErrorAction = "Stop"
            }
            $cred = New-Object System.Management.Automation.PSCredential @splatCredential

            $splatInvokeTips = @{
                SqlInstance     = $TestConfig.azureserver
                Database        = "test"
                SqlCredential   = $cred
                ReturnAllTips   = $true
                EnableException = $true
            }
            $results = Invoke-DbaAzSqlDbTip @splatInvokeTips
        }

        It "Should get some results" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should have the right ComputerName" {
            $results.ComputerName | Should -Be $TestConfig.azureserver
        }

        It "Database name should be 'test'" {
            $results.Database | Should -Be "test"
        }
    }
}