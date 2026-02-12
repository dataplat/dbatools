#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Invoke-DbaAgFailover",
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
                "InputObject",
                "Force",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
Describe $CommandName -Tag IntegrationTests {
    Context "Output validation" -Skip:(-not $TestConfig.InstanceHadr) {
        BeforeAll {
            $agObjects = Get-DbaAvailabilityGroup -SqlInstance $TestConfig.InstanceHadr
        }

        It "Returns output of the documented type" {
            if (-not $agObjects) { Set-ItResult -Skipped -Because "no availability groups found on HADR instance" }
            $agObjects[0].psobject.TypeNames | Should -Contain "Microsoft.SqlServer.Management.Smo.AvailabilityGroup"
        }

        It "Has the expected SMO properties documented in .OUTPUTS" {
            if (-not $agObjects) { Set-ItResult -Skipped -Because "no availability groups found on HADR instance" }
            $expectedProperties = @(
                "Name",
                "PrimaryReplicaServerName",
                "LocalReplicaRole",
                "AutomatedBackupPreference",
                "FailureConditionLevel",
                "HealthCheckTimeout",
                "BasicAvailabilityGroup",
                "ClusterType"
            )
            foreach ($prop in $expectedProperties) {
                $agObjects[0].psobject.Properties.Name | Should -Contain $prop -Because "property '$prop' should exist on the AvailabilityGroup object"
            }
        }
    }
}