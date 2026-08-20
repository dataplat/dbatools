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
}

Describe $CommandName -Tag IntegrationTests {
    # These tests need a Windows failover cluster. No CI environment has one, so
    # $TestConfig.ClusterStorage is empty there and these tests skip. A lab that has a cluster sets
    # it, and then a regression has to fail these tests.
    Context "Retrieving the cluster" -Skip:(-not $TestConfig.ClusterStorage) {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $wsfcCluster = Get-DbaWsfcCluster -ComputerName $TestConfig.ClusterStorage

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Returns the name and fqdn of the cluster" {
            $wsfcCluster.Name | Should -Be $TestConfig.ClusterStorage
            $wsfcCluster.Fqdn | Should -BeLike "$($TestConfig.ClusterStorage).*"
        }

        It "Returns the quorum type as a readable string" {
            $wsfcCluster.QuorumType | Should -Not -BeNullOrEmpty
            $wsfcCluster.QuorumTypeValue | Should -BeOfType [uint32]
        }

        It "Does not add an empty State property" {
            # MSCluster_Cluster has no State property, so the command built its State NoteProperty
            # from an undefined variable and it was always empty, in the object and in the default view.
            $wsfcCluster.PSObject.Properties.Name | Should -Not -Contain "State"
        }
    }
}