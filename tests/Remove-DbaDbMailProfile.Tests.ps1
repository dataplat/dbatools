#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName   = "dbatools",
    $CommandName = "Remove-DbaDbMailProfile",
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
                "Profile",
                "ExcludeProfile",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    BeforeEach {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $profileName = "dbatoolsci_test_$(Get-Random)"
        $profileName2 = "dbatoolsci_test_$(Get-Random)"

        $null = New-DbaDbMailProfile -SqlInstance $server -Name $profileName
        $null = New-DbaDbMailProfile -SqlInstance $server -Name $profileName2

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "commands work as expected" {
        It "removes a database mail profile" {
            (Get-DbaDbMailProfile -SqlInstance $server -Profile $profileName) | Should -Not -BeNullOrEmpty
            Remove-DbaDbMailProfile -SqlInstance $server -Profile $profileName -Confirm:$false
            (Get-DbaDbMailProfile -SqlInstance $server -Profile $profileName) | Should -BeNullOrEmpty
        }

        It "supports piping database mail profile" {
            (Get-DbaDbMailProfile -SqlInstance $server -Profile $profileName) | Should -Not -BeNullOrEmpty
            Get-DbaDbMailProfile -SqlInstance $server -Profile $profileName | Remove-DbaDbMailProfile -Confirm:$false
            (Get-DbaDbMailProfile -SqlInstance $server -Profile $profileName) | Should -BeNullOrEmpty
        }

        It "removes all database mail profiles but excluded" {
            (Get-DbaDbMailProfile -SqlInstance $server -Profile $profileName2) | Should -Not -BeNullOrEmpty
            (Get-DbaDbMailProfile -SqlInstance $server -ExcludeProfile $profileName2) | Should -Not -BeNullOrEmpty
            Remove-DbaDbMailProfile -SqlInstance $server -ExcludeProfile $profileName2 -Confirm:$false
            (Get-DbaDbMailProfile -SqlInstance $server -ExcludeProfile $profileName2) | Should -BeNullOrEmpty
            (Get-DbaDbMailProfile -SqlInstance $server -Profile $profileName2) | Should -Not -BeNullOrEmpty
        }

        It "removes all database mail profiles" {
            (Get-DbaDbMailProfile -SqlInstance $server) | Should -Not -BeNullOrEmpty
            Remove-DbaDbMailProfile -SqlInstance $server -Confirm:$false
            (Get-DbaDbMailProfile -SqlInstance $server) | Should -BeNullOrEmpty
        }
    }
}