#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaAvailabilityGroup",
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
                "AvailabilityGroup",
                "IsPrimary",
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
        $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

        # Set variables. They are available in all the It blocks.
        $agName = "dbatoolsci_agroup"

        # Create the objects.
        $splatAg = @{
            Primary      = $TestConfig.instance3
            Name         = $agName
            ClusterType  = "None"
            FailoverMode = "Manual"
            Certificate  = "dbatoolsci_AGCert"
            Confirm      = $false
        }
        $null = New-DbaAvailabilityGroup @splatAg

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove('*-Dba*:EnableException')
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

        # Cleanup all created objects.
        $null = Remove-DbaAvailabilityGroup -SqlInstance $TestConfig.instance3 -AvailabilityGroup $agName
        $null = Get-DbaEndpoint -SqlInstance $TestConfig.instance3 -Type DatabaseMirroring | Remove-DbaEndpoint

        # As this is the last block we do not need to reset the $PSDefaultParameterValues.
    }

    Context "When retrieving availability groups" {
        It "Returns results with proper data" {
            $results = Get-DbaAvailabilityGroup -SqlInstance $TestConfig.instance3
            $results.AvailabilityGroup | Should -Contain $agName
        }

        It "Returns a single result when specifying availability group name" {
            $results = Get-DbaAvailabilityGroup -SqlInstance $TestConfig.instance3 -AvailabilityGroup $agName
            $results.AvailabilityGroup | Should -Be $agName
        }
    }
} #$TestConfig.instance2 for appveyor