#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaWsfcResourceType",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "ComputerName",
                "Credential",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $result = Get-DbaWsfcResourceType -ComputerName $env:COMPUTERNAME -EnableException
        }

        It "Returns the documented output type" {
            $result[0].PSObject.TypeNames | Should -Contain 'Microsoft.Management.Infrastructure.CimInstance#root/MSCluster/MSCluster_ResourceType'
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                'ClusterName',
                'ClusterFqdn',
                'Name',
                'DisplayName',
                'DllName',
                'RequiredDependencyTypes'
            )
            $actualProps = $result[0].PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }
    }
}