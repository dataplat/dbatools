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

    Context "Output Validation" {
        It "Returns the documented output type" {
            $command = Get-Command $CommandName
            $command.OutputType.Name | Should -Contain 'AvailabilityGroup'
        }

        It "Has the expected properties documented in .OUTPUTS" {
            # Testing that the documented properties exist in the SMO type
            $expectedProps = @(
                'Name',
                'PrimaryReplicaServerName',
                'LocalReplicaRole',
                'AutomatedBackupPreference',
                'FailureConditionLevel',
                'HealthCheckTimeout',
                'BasicAvailabilityGroup',
                'ClusterType',
                'ID',
                'UniqueId',
                'AvailabilityReplicas',
                'AvailabilityDatabases',
                'AvailabilityGroupListeners',
                'DatabaseReplicaStates',
                'RequiredSynchronizedSecondariesToCommit'
            )
            # Verify the SMO type has these properties
            $agType = [Microsoft.SqlServer.Management.Smo.AvailabilityGroup]
            foreach ($prop in $expectedProps) {
                $agType.GetProperties().Name | Should -Contain $prop -Because "property '$prop' should be available on AvailabilityGroup SMO object"
            }
        }
    }
}
<#
    Integration test are custom to the command you are writing for.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidence
#>