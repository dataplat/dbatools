#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaWsfcCluster",
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
            $result = Get-DbaWsfcCluster -ComputerName $env:COMPUTERNAME -EnableException
        }

        It "Returns the documented output type" {
            $result.PSObject.TypeNames | Should -Contain 'Microsoft.Management.Infrastructure.CimInstance#root/MSCluster/MSCluster_Cluster'
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                'Name',
                'Fqdn',
                'State',
                'DrainOnShutdown',
                'DynamicQuorumEnabled',
                'EnableSharedVolumes',
                'SharedVolumesRoot',
                'QuorumPath',
                'QuorumType',
                'QuorumTypeValue',
                'RequestReplyTimeout'
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }

        It "Has State property added by dbatools" {
            $result.PSObject.Properties.Name | Should -Contain 'State' -Because "State is added via Add-Member"
        }
    }
}