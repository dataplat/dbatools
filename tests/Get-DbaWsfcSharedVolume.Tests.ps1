#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaWsfcSharedVolume",
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
}

Describe $CommandName -Tag IntegrationTests {
    # These tests need a Windows failover cluster that has a cluster shared volume. No CI environment
    # has one, so $TestConfig.ClusterStorage is empty there and these tests skip. A lab that has a
    # cluster sets it, and then a regression has to fail these tests.
    Context "Retrieving the cluster shared volumes" -Skip:(-not $TestConfig.ClusterStorage) {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $sharedVolumes = @(Get-DbaWsfcSharedVolume -ComputerName $TestConfig.ClusterStorage)
            $wsfcCluster = Get-DbaWsfcCluster -ComputerName $TestConfig.ClusterStorage

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Returns at least one cluster shared volume" {
            # The command asked WMI for class ClusterSharedVolume, which does not exist in
            # root\MSCluster - the concrete class is MSCluster_ClusterSharedVolume. So it returned
            # nothing on every cluster, silently, and no test noticed because the lab had no CSV.
            $sharedVolumes | Should -Not -BeNullOrEmpty
        }

        It "Returns the mount point of the volume" {
            $sharedVolumes[0].Name | Should -BeLike "*ClusterStorage*"
        }

        It "Adds the cluster name and fqdn to every volume" {
            ($sharedVolumes | Where-Object ClusterName -ne $wsfcCluster.Name).Name | Should -BeNullOrEmpty
            ($sharedVolumes | Where-Object ClusterFqdn -ne $wsfcCluster.Fqdn).Name | Should -BeNullOrEmpty
        }
    }
}