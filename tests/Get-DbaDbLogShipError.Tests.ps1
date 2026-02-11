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

    Context "Output validation" {
        BeforeAll {
            $result = @(Get-DbaDbLogShipError -SqlInstance $TestConfig.InstanceSingle)
        }

        It "Returns no errors on an instance without log shipping" {
            $result.Count | Should -BeExactly 0
        }

        It "Has the expected output properties when results exist" {
            if (-not $result) { Set-ItResult -Skipped -Because "no log shipping errors on test instance" }
            $expectedProperties = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Database",
                "Instance",
                "Action",
                "SessionID",
                "SequenceNumber",
                "LogTime",
                "Message"
            )
            foreach ($prop in $expectedProperties) {
                $result[0].PSObject.Properties[$prop] | Should -Not -BeNullOrEmpty -Because "property '$prop' should exist on the output object"
            }
        }
    }
}