#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaAgListener",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Listener",
                "AvailabilityGroup",
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

        $agName = "dbatoolsci_ag_removelistener"
        $splatAg = @{
            Primary      = $TestConfig.instanceHadr
            Name         = $agName
            ClusterType  = "None"
            FailoverMode = "Manual"
            Certificate  = "dbatoolsci_AGCert"
        }
        $ag = New-DbaAvailabilityGroup @splatAg

        $splatListener = @{
            IPAddress = "127.0.20.1"
            Port      = 14330
        }
        $agListener = $ag | Add-DbaAgListener @splatListener

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Remove-DbaAvailabilityGroup -SqlInstance $TestConfig.instanceHadr -AvailabilityGroup $agName
        $null = Get-DbaEndpoint -SqlInstance $TestConfig.instanceHadr -Type DatabaseMirroring | Remove-DbaEndpoint

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When removing a listener" {
        It "Returns results with proper data" {
            $results = Remove-DbaAgListener -SqlInstance $TestConfig.instanceHadr -Listener $agListener.Name
            $results.Status | Should -Be "Removed"
        }
    }
}