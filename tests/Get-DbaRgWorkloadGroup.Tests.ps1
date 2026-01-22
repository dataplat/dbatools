#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaRgWorkloadGroup",
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
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $result = Get-DbaRgWorkloadGroup -SqlInstance $TestConfig.instance1 -EnableException
        }

        It "Returns the documented output type" {
            $result | Should -Not -BeNullOrEmpty
            $result[0] | Should -BeOfType [Microsoft.SqlServer.Management.Smo.WorkloadGroup]
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                'ComputerName',
                'InstanceName',
                'SqlInstance',
                'Id',
                'Name',
                'ExternalResourcePoolName',
                'GroupMaximumRequests',
                'Importance',
                'IsSystemObject',
                'MaximumDegreeOfParallelism',
                'RequestMaximumCpuTimeInSeconds',
                'RequestMaximumMemoryGrantPercentage',
                'RequestMemoryGrantTimeoutInSeconds'
            )
            $actualProps = $result[0].PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }
    }
}
<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>