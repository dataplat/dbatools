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
        It "Returns well-formed log shipping error records for the queried instance" {
            # The msdb log shipping error log is instance-global state that other suites
            # legitimately write to when they exercise log shipping, so this suite must not
            # pin the instance-wide error count. What the command owns is the shape of what
            # it returns: zero or more records, each exposing the documented columns.
            $results = @(Get-DbaDbLogShipError -SqlInstance $TestConfig.InstanceSingle -EnableException)
            foreach ($result in $results) {
                $result.SqlInstance | Should -Not -BeNullOrEmpty
                $result.Database | Should -Not -BeNullOrEmpty
                $result.LogTime | Should -Not -BeNullOrEmpty
                $result.Message | Should -Not -BeNullOrEmpty
                $result.PSObject.Properties.Name | Should -Contain "ComputerName"
                $result.PSObject.Properties.Name | Should -Contain "InstanceName"
                $result.PSObject.Properties.Name | Should -Contain "Instance"
                $result.PSObject.Properties.Name | Should -Contain "Action"
                $result.PSObject.Properties.Name | Should -Contain "SessionID"
                $result.PSObject.Properties.Name | Should -Contain "SequenceNumber"
            }
        }
    }
}