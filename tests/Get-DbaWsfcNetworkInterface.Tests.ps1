#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaWsfcNetworkInterface",
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

    Context "Output Validation" -Skip:$($env:COMPUTERNAME -notin $TestConfig.DbatoolsCluster) {
        BeforeAll {
            $result = Get-DbaWsfcNetworkInterface -ComputerName $TestConfig.instance1 -EnableException
        }

        It "Returns the documented output type" {
            $result | Should -BeOfType [System.Management.ManagementObject]
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                'ClusterName',
                'ClusterFqdn',
                'Name',
                'Network',
                'Node',
                'Adapter',
                'Address',
                'DhcpEnabled',
                'IPv4Addresses',
                'IPv6Addresses'
            )
            $actualProps = $result[0].PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }

        It "Has ClusterName and ClusterFqdn properties added by dbatools" {
            $result[0].PSObject.Properties.Name | Should -Contain 'ClusterName'
            $result[0].PSObject.Properties.Name | Should -Contain 'ClusterFqdn'
        }
    }
}