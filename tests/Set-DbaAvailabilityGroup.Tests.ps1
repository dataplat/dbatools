#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Set-DbaAvailabilityGroup",
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
                "AvailabilityGroup",
                "AllAvailabilityGroups",
                "DtcSupportEnabled",
                "ClusterType",
                "AutomatedBackupPreference",
                "FailureConditionLevel",
                "HealthCheckTimeout",
                "BasicAvailabilityGroup",
                "DatabaseHealthTrigger",
                "IsDistributedAvailabilityGroup",
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

        # Set variables. They are available in all the It blocks.
        $agName = "dbatoolsci_agroup"

        # Create the objects.
        $splatNewAg = @{
            Primary      = $TestConfig.instance3
            Name         = $agName
            ClusterType  = "None"
            FailoverMode = "Manual"
            Confirm      = $false
            Certificate  = "dbatoolsci_AGCert"
        }
        $null = New-DbaAvailabilityGroup @splatNewAg

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }
    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup all created objects.
        $null = Remove-DbaAvailabilityGroup -SqlInstance $TestConfig.instance3 -AvailabilityGroup $agName -Confirm $false
        $null = Get-DbaEndpoint -SqlInstance $TestConfig.instance3 -Type DatabaseMirroring | Remove-DbaEndpoint -Confirm $false

        # As this is the last block we do not need to reset the $PSDefaultParameterValues.
    }
    Context "sets ag properties" {
        It "returns modified results" {
            $splatSetAg = @{
                SqlInstance       = $TestConfig.instance3
                AvailabilityGroup = $agName
                Confirm           = $false
                DtcSupportEnabled = $false
            }
            $results = Set-DbaAvailabilityGroup @splatSetAg
            $results.AvailabilityGroup | Should -Be $agName
            $results.DtcSupportEnabled | Should -Be $false
        }
        It "returns newly modified results" {
            $results = Set-DbaAvailabilityGroup -SqlInstance $TestConfig.instance3 -AvailabilityGroup $agName -Confirm $false -DtcSupportEnabled
            $results.AvailabilityGroup | Should -Be $agName
            $results.DtcSupportEnabled | Should -Be $true
        }
    }
} #$TestConfig.instance2 for appveyor