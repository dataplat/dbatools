#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Copy-DbaDataCollector",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Source",
                "SourceSqlCredential",
                "Destination",
                "DestinationSqlCredential",
                "CollectionSet",
                "ExcludeCollectionSet",
                "NoServerReconfig",
                "Force",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Output Validation" {
        BeforeAll {
            # This command requires Data Collector to be configured, which may not be available in test environments
            # We'll test the output structure using WhatIf to avoid actual modifications
            $result = Copy-DbaDataCollector -Source $TestConfig.instance1 -Destination $TestConfig.instance2 -WhatIf -ErrorAction SilentlyContinue
        }

        It "Returns PSCustomObject" {
            if ($result) {
                $result.PSObject.TypeNames | Should -Contain 'System.Management.Automation.PSCustomObject'
            } else {
                Set-ItResult -Skipped -Because "Data Collector may not be configured in test environment"
            }
        }

        It "Has the expected default display properties" {
            if ($result) {
                $expectedProps = @(
                    'DateTime',
                    'SourceServer',
                    'DestinationServer',
                    'Name',
                    'Type',
                    'Status',
                    'Notes'
                )
                $actualProps = $result[0].PSObject.Properties.Name
                foreach ($prop in $expectedProps) {
                    $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
                }
            } else {
                Set-ItResult -Skipped -Because "Data Collector may not be configured in test environment"
            }
        }
    }
}