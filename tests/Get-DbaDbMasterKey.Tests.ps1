#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
        $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDbMasterKey",
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
                "InputObject",
                "EnableException"
            )
        }

        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $dbname = "dbatoolsci_test_$(Get-Random)"
        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance1
        $null = $server.Query("Create Database [$dbname]")
        $splatMasterKey = @{
            SqlInstance = $TestConfig.instance1
                        Database    = $dbname
                        Password    = (ConvertTo-SecureString -AsPlainText -Force -String "ThisIsAPassword!")
                        Confirm     = $false
        }
        $null = New-DbaDbMasterKey @splatMasterKey
    }

    AfterAll {
        Remove-DbaDbMasterKey -SqlInstance $TestConfig.instance1 -Database $dbname -Confirm:$false
        Remove-DbaDatabase -SqlInstance $TestConfig.instance1 -Database $dbname -Confirm:$false
    }

    Context "Gets DbMasterKey" {
        BeforeAll {
            $results = Get-DbaDbMasterKey -SqlInstance $TestConfig.instance1 | Where-Object Database -eq $dbname
        }

        It "Gets results" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should be the key on $dbname" {
            $results.Database | Should -BeExactly $dbname
        }

        It "Should be encrypted by the server" {
            $results.isEncryptedByServer | Should -BeTrue
        }
    }

    Context "Gets DbMasterKey when using -database" {
        BeforeAll {
            $results = Get-DbaDbMasterKey -SqlInstance $TestConfig.instance1 -Database $dbname
        }

        It "Gets results" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should be the key on $dbname" {
            $results.Database | Should -BeExactly $dbname
        }

        It "Should be encrypted by the server" {
            $results.isEncryptedByServer | Should -BeTrue
        }
    }

    Context "Gets no DbMasterKey when using -ExcludeDatabase" {
        BeforeAll {
            $results = Get-DbaDbMasterKey -SqlInstance $TestConfig.instance1 -ExcludeDatabase $dbname
        }

        It "Gets no results" {
            $results | Should -BeNullOrEmpty
        }
    }
}