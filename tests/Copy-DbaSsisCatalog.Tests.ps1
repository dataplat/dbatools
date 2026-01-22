#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Copy-DbaSsisCatalog",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Source",
                "Destination",
                "SourceSqlCredential",
                "DestinationSqlCredential",
                "Project",
                "Folder",
                "Environment",
                "CreateCatalogPassword",
                "EnableSqlClr",
                "Force",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Output Validation" {
        It "Returns no output by design" {
            # Copy-DbaSsisCatalog is a migration command that performs operations via side effects
            # and does not return objects. This test validates the documented behavior continues
            # in the C# migration to dbatools 3.0.
            $command = Get-Command $CommandName
            $command.OutputType | Should -BeNullOrEmpty -Because "Copy-DbaSsisCatalog should not return any objects"
        }

        It "Has documented .OUTPUTS section stating None" {
            $help = Get-Help $CommandName
            $help.returnValues.returnValue.type.name | Should -Match "^None" -Because "documentation should explicitly state no output is returned"
        }
    }
}