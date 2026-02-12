#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaXESession",
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
                "Session",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Verifying command output" {
        BeforeAll {
            $results = Get-DbaXESession -SqlInstance $TestConfig.InstanceSingle -Session system_health
        }

        It "returns some results" {
            $multiResults = Get-DbaXESession -SqlInstance $TestConfig.InstanceSingle
            $multiResults.Count -gt 1 | Should -Be $true
        }

        It "returns only the system_health session" {
            $results.Name -eq "system_health" | Should -Be $true
        }

        It "Returns output of the documented type" {
            $results | Should -Not -BeNullOrEmpty
            $results[0].psobject.TypeNames | Should -Contain "Microsoft.SqlServer.Management.XEvent.Session"
        }

        It "Has the expected default display properties" {
            $defaultProps = $results[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Name",
                "Status",
                "StartTime",
                "AutoStart",
                "State",
                "Targets",
                "TargetFile",
                "Events",
                "MaxMemory",
                "MaxEventSize"
            )
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }
    }
}