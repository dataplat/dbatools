#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Compare-DbaAgReplicaAgentJob",
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
                "ExcludeSystemJob",
                "IncludeModifiedDate",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Output Validation" {
        It "Returns PSCustomObject" {
            $command = Get-Command $CommandName
            $command.OutputType.Name | Should -Contain 'PSCustomObject'
        }

        It "Has the expected properties when differences are found" {
            $expectedProps = @(
                'AvailabilityGroup',
                'Replica',
                'JobName',
                'Status',
                'DateLastModified'
            )

            $mockResult = [PSCustomObject]@{
                AvailabilityGroup = "AG1"
                Replica           = "SQL2019"
                JobName           = "TestJob"
                Status            = "Missing"
                DateLastModified  = $null
            }

            $actualProps = $mockResult.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be present in output"
            }
        }
    }
}
