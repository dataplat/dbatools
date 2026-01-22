#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Enable-DbaReplDistributor",
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
                "DistributionDatabase",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Output Validation" {
        BeforeAll {
            # Note: This test requires a SQL Server instance that is not already configured as a distributor
            # Skipping actual execution in unit tests - output validation is based on code analysis
            # Integration tests should validate actual output structure
        }

        It "Should document the expected output type" {
            $help = Get-Help $CommandName
            $help.returnValues.returnValue.type.name | Should -Be 'Microsoft.SqlServer.Replication.ReplicationServer'
        }

        It "Should have the expected default display properties documented" {
            $expectedProps = @(
                'ComputerName',
                'InstanceName',
                'SqlInstance',
                'IsDistributor',
                'IsPublisher',
                'DistributionServer',
                'DistributionDatabase'
            )
            # Verify properties are documented in help
            $help = Get-Help $CommandName -Full
            $outputSection = $help.returnValues.returnValue.description.Text
            foreach ($prop in $expectedProps) {
                $outputSection | Should -BeLike "*$prop*" -Because "property '$prop' should be documented in .OUTPUTS"
            }
        }
    }
}