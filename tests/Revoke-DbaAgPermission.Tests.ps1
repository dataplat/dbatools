#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Revoke-DbaAgPermission",
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
                "Login",
                "AvailabilityGroup",
                "Type",
                "Permission",
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

        $null = Invoke-DbaQuery -SqlInstance $TestConfig.instance3 -InputFile "$($TestConfig.appveyorlabrepo)\sql2008-scripts\logins.sql" -ErrorAction SilentlyContinue
        $agname = "dbatoolsci_ag_revoke"

        $splatAvailabilityGroup = @{
            Primary      = $TestConfig.instance3
            Name         = $agname
            ClusterType  = "None"
            FailoverMode = "Manual"
            Confirm      = $false
            Certificate  = "dbatoolsci_AGCert"
        }
        $null = New-DbaAvailabilityGroup @splatAvailabilityGroup

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }
    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Remove-DbaAvailabilityGroup -SqlInstance $TestConfig.instance3 -AvailabilityGroup $agname -Confirm:$false
        $null = Get-DbaEndpoint -SqlInstance $TestConfig.instance3 -Type DatabaseMirroring | Remove-DbaEndpoint -Confirm:$false
        $null = Remove-DbaLogin -SqlInstance $TestConfig.instance3 -Login "claudio", "port", "tester" -Confirm:$false

        # As this is the last block we do not need to reset the $PSDefaultParameterValues.
    }
    Context "revokes big perms" {
        It "returns results with proper data" {
            $results = Get-DbaLogin -SqlInstance $TestConfig.instance3 -Login tester | Revoke-DbaAgPermission -Type EndPoint
            $results.Status | Should -Be "Success"
        }
    }
} #$TestConfig.instance2 for appveyor