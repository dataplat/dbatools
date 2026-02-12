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

        Context "Output validation" {
            BeforeAll {
                $script:outputValidationResult = Set-DbaAvailabilityGroup -SqlInstance $TestConfig.InstanceHadr -AvailabilityGroup $agname -HealthCheckTimeout $($agname | Get-DbaAvailabilityGroup -SqlInstance $TestConfig.InstanceHadr | Select-Object -ExpandProperty HealthCheckTimeout)
            }

            It "Returns output of the documented type" {
                $script:outputValidationResult[0].psobject.TypeNames | Should -Contain "Microsoft.SqlServer.Management.Smo.AvailabilityGroup"
            }

            It "Has the expected properties" {
                $script:outputValidationResult[0].psobject.Properties.Name | Should -Contain "Name"
                $script:outputValidationResult[0].psobject.Properties.Name | Should -Contain "AutomatedBackupPreference"
                $script:outputValidationResult[0].psobject.Properties.Name | Should -Contain "BasicAvailabilityGroup"
                $script:outputValidationResult[0].psobject.Properties.Name | Should -Contain "ClusterType"
                $script:outputValidationResult[0].psobject.Properties.Name | Should -Contain "DatabaseHealthTrigger"
                $script:outputValidationResult[0].psobject.Properties.Name | Should -Contain "DtcSupportEnabled"
                $script:outputValidationResult[0].psobject.Properties.Name | Should -Contain "FailureConditionLevel"
                $script:outputValidationResult[0].psobject.Properties.Name | Should -Contain "HealthCheckTimeout"
                $script:outputValidationResult[0].psobject.Properties.Name | Should -Contain "IsDistributedAvailabilityGroup"
            }
        }
    }

}
