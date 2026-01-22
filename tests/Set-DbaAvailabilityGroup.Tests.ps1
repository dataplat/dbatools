#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Set-DbaAvailabilityGroup",
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
                "ClusterConnectionOption",
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

        $agname = "dbatoolsci_agroup"
        $splatPrimary = @{
            Primary      = $TestConfig.InstanceHadr
            Name         = $agname
            ClusterType  = "None"
            FailoverMode = "Manual"
            Certificate  = "dbatoolsci_AGCert"
        }
        $null = New-DbaAvailabilityGroup @splatPrimary

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        Remove-DbaAvailabilityGroup -SqlInstance $TestConfig.InstanceHadr -AvailabilityGroup $agname
        $null = Get-DbaEndpoint -SqlInstance $TestConfig.InstanceHadr -Type DatabaseMirroring | Remove-DbaEndpoint

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "sets ag properties" {
        It "returns modified results" {
            $results = Set-DbaAvailabilityGroup -SqlInstance $TestConfig.InstanceHadr -AvailabilityGroup $agname -DtcSupportEnabled:$false
            $results.AvailabilityGroup | Should -Be $agname
            $results.DtcSupportEnabled | Should -Be $false
        }
        It "returns newly modified results" {
            $results = Set-DbaAvailabilityGroup -SqlInstance $TestConfig.InstanceHadr -AvailabilityGroup $agname -DtcSupportEnabled
            $results.AvailabilityGroup | Should -Be $agname
            $results.DtcSupportEnabled | Should -Be $true
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $result = Set-DbaAvailabilityGroup -SqlInstance $TestConfig.InstanceHadr -AvailabilityGroup $agname -DtcSupportEnabled:$false -EnableException
        }

        It "Returns the documented output type" {
            $result | Should -BeOfType [Microsoft.SqlServer.Management.Smo.AvailabilityGroup]
        }

        It "Has the expected properties documented in .OUTPUTS" {
            $expectedProps = @(
                'Name',
                'AvailabilityReplicas',
                'AutomatedBackupPreference',
                'BasicAvailabilityGroup',
                'ClusterType',
                'DatabaseHealthTrigger',
                'DtcSupportEnabled',
                'FailureConditionLevel',
                'HealthCheckTimeout',
                'IsDistributedAvailabilityGroup'
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be available in output"
            }
        }

        It "Has additional SMO properties accessible" {
            $additionalProps = @(
                'Parent',
                'Databases'
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $additionalProps) {
                $actualProps | Should -Contain $prop -Because "SMO property '$prop' should be accessible"
            }
        }
    }
}