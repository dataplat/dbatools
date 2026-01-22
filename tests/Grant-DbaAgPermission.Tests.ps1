#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Grant-DbaAgPermission",
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
        $agName = "dbatoolsci_ag_grant"
        $splatAvailabilityGroup = @{
            Primary      = $TestConfig.InstanceHadr
            Name         = $agName
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

        $null = Remove-DbaAvailabilityGroup -SqlInstance $TestConfig.InstanceHadr -AvailabilityGroup $agName
        $null = Get-DbaEndpoint -SqlInstance $TestConfig.InstanceHadr -Type DatabaseMirroring | Remove-DbaEndpoint
        $null = Remove-DbaLogin -SqlInstance $TestConfig.InstanceHadr -Login "claudio", "port", "tester"

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "grants big perms" {
        It "returns results with proper data" {
            $results = Get-DbaLogin -SqlInstance $TestConfig.InstanceHadr -Login tester | Grant-DbaAgPermission -Type EndPoint
            $results.Status | Should -Be "Success"
            $results.Status | Should -Be "Success"
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $result = Get-DbaLogin -SqlInstance $TestConfig.InstanceHadr -Login tester | Grant-DbaAgPermission -Type EndPoint -Permission Connect -EnableException
        }

        It "Returns PSCustomObject" {
            $result.PSObject.TypeNames | Should -Contain 'System.Management.Automation.PSCustomObject'
        }

        It "Has the expected properties" {
            $expectedProps = @(
                'ComputerName',
                'InstanceName',
                'SqlInstance',
                'Name',
                'Permission',
                'Type',
                'Status'
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in output"
            }
        }

        It "Type property is always 'Grant'" {
            $result.Type | Should -Be "Grant"
        }

        It "Status property is 'Success' for successful grants" {
            $result.Status | Should -Be "Success"
        }
    }

    Context "Output with AvailabilityGroup type" {
        BeforeAll {
            $result = Get-DbaLogin -SqlInstance $TestConfig.InstanceHadr -Login tester | Grant-DbaAgPermission -Type AvailabilityGroup -AvailabilityGroup $agName -Permission Alter -EnableException
        }

        It "Returns output for AvailabilityGroup permission grants" {
            $result | Should -Not -BeNullOrEmpty
            $result.Permission | Should -Be "Alter"
        }

        It "Has the same property structure as Endpoint grants" {
            $expectedProps = @('ComputerName', 'InstanceName', 'SqlInstance', 'Name', 'Permission', 'Type', 'Status')
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop
            }
        }
    }
}