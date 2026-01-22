#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaWsfcResourceGroup",
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
                "Name",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $result = Get-DbaWsfcResourceGroup -ComputerName $env:COMPUTERNAME -EnableException
        }

        It "Returns the documented output type" {
            $result | Should -BeOfType [Microsoft.Management.Infrastructure.CimInstance]
            $result.CimClass.CimClassName | Should -BeLike "*MSCluster_ResourceGroup"
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                'ClusterName',
                'ClusterFqdn',
                'Name',
                'State',
                'PersistentState',
                'OwnerNode'
            )
            $actualProps = $result[0].PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }

        It "Has State property added by dbatools" {
            $result[0].State | Should -BeIn @('Online', 'Offline', 'Failed', 'Unknown')
        }

        It "Has ClusterName property added by dbatools" {
            $result[0].PSObject.Properties.Name | Should -Contain 'ClusterName'
        }

        It "Has ClusterFqdn property added by dbatools" {
            $result[0].PSObject.Properties.Name | Should -Contain 'ClusterFqdn'
        }
    }
}