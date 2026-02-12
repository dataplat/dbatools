#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaRgResourcePool",
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
                "Type",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "When getting resource pools" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $allResults = Get-DbaRgResourcePool -SqlInstance $TestConfig.InstanceSingle
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Gets Results" {
            $allResults | Should -Not -BeNullOrEmpty
        }
    }

    Context "When getting resource pools using -Type parameter" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $typeResults = Get-DbaRgResourcePool -SqlInstance $TestConfig.InstanceSingle -Type Internal
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Gets Results with Type filter" {
            $typeResults | Should -Not -BeNullOrEmpty
        }
    }

    Context "Output validation" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $result = Get-DbaRgResourcePool -SqlInstance $TestConfig.InstanceSingle
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Returns output of the documented type" {
            $result | Should -Not -BeNullOrEmpty
            $result[0].psobject.TypeNames | Should -Contain "Microsoft.SqlServer.Management.Smo.ResourcePool"
        }

        It "Has the expected default display properties" {
            $defaultProps = $result[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Id",
                "Name",
                "CapCpuPercentage",
                "IsSystemObject",
                "MaximumCpuPercentage",
                "MaximumIopsPerVolume",
                "MaximumMemoryPercentage",
                "MinimumCpuPercentage",
                "MinimumIopsPerVolume",
                "MinimumMemoryPercentage",
                "WorkloadGroups"
            )
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }
    }
}