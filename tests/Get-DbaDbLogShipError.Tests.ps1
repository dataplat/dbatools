#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDbLogShipError",
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
                "Database",
                "ExcludeDatabase",
                "Action",
                "DateTimeFrom",
                "DateTimeTo",
                "Primary",
                "Secondary",
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

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Return values" {
        It "Get the log shipping errors" {
            $results = @(Get-DbaDbLogShipError -SqlInstance $TestConfig.InstanceSingle)
            $results.Status.Count | Should -BeExactly 0
        }
    }

    Context "When databases are excluded" {
        It "Accepts -ExcludeDatabase and returns nothing for an instance without log shipping" {
            # -ExcludeDatabase was declared and documented but never applied to the results (#10607). An instance
            # without log shipping has no errors to filter, so this only proves the parameter is wired and harmless.
            $results = @(Get-DbaDbLogShipError -SqlInstance $TestConfig.InstanceSingle -ExcludeDatabase master)
            $results.Status.Count | Should -BeExactly 0
            $WarnVar | Should -BeNullOrEmpty
        }
    }
}
