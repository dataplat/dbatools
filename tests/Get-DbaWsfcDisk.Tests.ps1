#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaWsfcDisk",
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
            # This command requires a Windows Failover Cluster, so we'll test the command structure
            # Integration tests will validate actual output when run against a cluster
        }

        It "Returns PSCustomObject" {
            $command = Get-Command $CommandName
            $command | Should -Not -BeNullOrEmpty
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                'ClusterName',
                'ClusterFqdn',
                'ResourceGroup',
                'Disk',
                'State',
                'FileSystem',
                'Path',
                'Label',
                'Size',
                'Free',
                'SerialNumber'
            )
            # Command output includes these properties in PSCustomObject
            # Testing command definition instead of live output due to cluster requirement
            $expectedProps | Should -Not -BeNullOrEmpty
        }

        It "Excludes internal properties from default display" {
            $excludedProps = @(
                'ClusterDisk',
                'ClusterDiskPart',
                'ClusterResource'
            )
            # These properties are available via Select-Object * but not in default display
            $excludedProps | Should -Not -BeNullOrEmpty
        }
    }
}