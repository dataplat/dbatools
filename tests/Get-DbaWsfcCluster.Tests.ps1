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

        It "Reports the quorum path as the witness path of a disk witness" {
            $wsfcCluster.WitnessPath | Should -Be $wsfcCluster.QuorumPath
        }
    }

    # This needs a cluster whose witness is a file share, which is a different cluster from the one
    # with the shared storage. Same rule as above: empty in CI, set by a lab that has one.
    Context "Retrieving the witness of a file share witness cluster" -Skip:(-not $TestConfig.ClusterWitness) {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $witnessCluster = Get-DbaWsfcCluster -ComputerName $TestConfig.ClusterWitness
            $witnessResource = Get-DbaWsfcResource -ComputerName $TestConfig.ClusterWitness | Where-Object Type -eq "File Share Witness"

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Uses a file share witness" {
            $witnessResource | Should -Not -BeNullOrEmpty -Because "the rest of this context tests what such a cluster reports"
        }

        It "Returns the share path of the witness" {
            # This is what issue #10573 asked for. MSCluster_Cluster has no property that carries it:
            # QuorumPath stays empty for a file share witness, and the path only exists in the private
            # properties of the witness resource.
            $witnessCluster.QuorumPath | Should -BeNullOrEmpty
            $witnessCluster.WitnessPath | Should -Be $witnessResource.PrivateProperties.SharePath
            $witnessCluster.WitnessPath | Should -BeLike "\\*"
        }
    }
}