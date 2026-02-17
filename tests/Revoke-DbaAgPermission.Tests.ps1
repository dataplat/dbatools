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

        $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceHadr -InputFile "$($TestConfig.appveyorlabrepo)\sql2008-scripts\logins.sql" -ErrorAction SilentlyContinue
        $agname = "dbatoolsci_ag_revoke"

        $splatAvailabilityGroup = @{
            Primary      = $TestConfig.InstanceHadr
            Name         = $agname
            ClusterType  = "None"
            FailoverMode = "Manual"
            Certificate  = "dbatoolsci_AGCert"
        }
        $null = New-DbaAvailabilityGroup @splatAvailabilityGroup

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }
    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Remove-DbaAvailabilityGroup -SqlInstance $TestConfig.InstanceHadr -AvailabilityGroup $agname
        $null = Get-DbaEndpoint -SqlInstance $TestConfig.InstanceHadr -Type DatabaseMirroring | Remove-DbaEndpoint
        $null = Remove-DbaLogin -SqlInstance $TestConfig.InstanceHadr -Login "claudio", "port", "tester"

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }
    Context "revokes big perms" {
        It "returns results with proper data" {
            $results = Get-DbaLogin -SqlInstance $TestConfig.InstanceHadr -Login tester | Revoke-DbaAgPermission -Type EndPoint -OutVariable "global:dbatoolsciOutput"
            $results.Status | Should -Be "Success"
        }
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return a PSCustomObject" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [PSCustomObject]
        }

        It "Should have the expected properties" {
            $expectedProperties = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Name",
                "Permission",
                "Type",
                "Status"
            )
            $actualProperties = $global:dbatoolsciOutput[0].PSObject.Properties.Name
            Compare-Object -ReferenceObject $expectedProperties -DifferenceObject $actualProperties | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "PSCustomObject"
        }
    }
}