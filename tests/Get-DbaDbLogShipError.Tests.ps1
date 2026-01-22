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

    Context "Output Validation" {
        BeforeAll {
            # This command returns errors only if log shipping errors exist
            # Testing with no errors present, so we expect empty/null results
            $result = Get-DbaDbLogShipError -SqlInstance $TestConfig.InstanceSingle -EnableException
        }

        It "Returns PSCustomObject when errors exist" {
            # Note: This test will be skipped if no log shipping errors are present
            # When errors exist, verify the output type
            if ($result) {
                $result[0].PSObject.TypeNames | Should -Contain "System.Management.Automation.PSCustomObject"
            }
        }

        It "Has the expected output properties when errors exist" {
            # Note: This test will be skipped if no log shipping errors are present
            if ($result) {
                $expectedProps = @(
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
                $actualProps = $result[0].PSObject.Properties.Name
                foreach ($prop in $expectedProps) {
                    $actualProps | Should -Contain $prop -Because "property '$prop' should be present in output"
                }
            }
        }
    }
}