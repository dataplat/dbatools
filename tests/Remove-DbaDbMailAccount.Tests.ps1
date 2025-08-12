#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaDbMailAccount",
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
                "Account",
                "ExcludeAccount",
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
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $accountname = "dbatoolsci_test_$(Get-Random)"
        $accountname2 = "dbatoolsci_test_$(Get-Random)"
        $createdAccounts = @()

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup all created accounts
        $existingAccounts = Get-DbaDbMailAccount -SqlInstance $server
        foreach ($account in $createdAccounts) {
            if ($account -in $existingAccounts.Name) {
                $null = Remove-DbaDbMailAccount -SqlInstance $server -Account $account -Confirm:$false
            }
        }

        # As this is the last block we do not need to reset the $PSDefaultParameterValues.
    }

    Context "When working with database mail accounts" {
        BeforeEach {
            # Create test accounts for each test
            $splatAccount1 = @{
                SqlInstance  = $server
                Name         = $accountname
                EmailAddress = "admin@ad.local"
            }
            $null = New-DbaDbMailAccount @splatAccount1
            $createdAccounts += $accountname

            $splatAccount2 = @{
                SqlInstance  = $server
                Name         = $accountname2
                EmailAddress = "admin@ad.local"
            }
            $null = New-DbaDbMailAccount @splatAccount2
            $createdAccounts += $accountname2
        }

        It "removes a database mail account" {
            (Get-DbaDbMailAccount -SqlInstance $server -Account $accountname) | Should -Not -BeNullOrEmpty
            Remove-DbaDbMailAccount -SqlInstance $server -Account $accountname -Confirm:$false
            (Get-DbaDbMailAccount -SqlInstance $server -Account $accountname) | Should -BeNullOrEmpty
        }

        It "supports piping database mail account" {
            (Get-DbaDbMailAccount -SqlInstance $server -Account $accountname) | Should -Not -BeNullOrEmpty
            Get-DbaDbMailAccount -SqlInstance $server -Account $accountname | Remove-DbaDbMailAccount -Confirm:$false
            (Get-DbaDbMailAccount -SqlInstance $server -Account $accountname) | Should -BeNullOrEmpty
        }

        It "removes all database mail accounts but excluded" {
            (Get-DbaDbMailAccount -SqlInstance $server -Account $accountname2) | Should -Not -BeNullOrEmpty
            (Get-DbaDbMailAccount -SqlInstance $server -ExcludeAccount $accountname2) | Should -Not -BeNullOrEmpty
            Remove-DbaDbMailAccount -SqlInstance $server -ExcludeAccount $accountname2 -Confirm:$false
            (Get-DbaDbMailAccount -SqlInstance $server -ExcludeAccount $accountname2) | Should -BeNullOrEmpty
            (Get-DbaDbMailAccount -SqlInstance $server -Account $accountname2) | Should -Not -BeNullOrEmpty
        }

        It "removes all database mail accounts" {
            (Get-DbaDbMailAccount -SqlInstance $server) | Should -Not -BeNullOrEmpty
            Remove-DbaDbMailAccount -SqlInstance $server -Confirm:$false
            (Get-DbaDbMailAccount -SqlInstance $server) | Should -BeNullOrEmpty
        }
    }
}