#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaWsfcNode",
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
    # Characterization tests (2026-07-06, Track A): pin the observed behavior of the live
    # implementation ahead of the C# port. InstanceMulti2 is the FCI network name; querying it
    # reaches the underlying WSFC (wincluster in the lab, with sqlnode1 and sqlnode2 as members).
    # root\MSCluster CIM requires domain auth — this gate must run via PSDirect (Invoke-Command
    # -VMName workstation -Credential lab\cl); the SSH-key gate channel lacks network creds for
    # WMI/CIM and will produce zero results.
    Context "When querying the lab failover cluster" {
        BeforeAll {
            $nodeResults = @(Get-DbaWsfcNode -ComputerName $TestConfig.InstanceMulti2)
        }

        It "Returns at least two node objects" {
            $nodeResults.Count | Should -BeGreaterOrEqual 2
        }

        It "Returns MSCluster_Node CIM instances" {
            $nodeResults[0].PSObject.TypeNames[0] | Should -Match "MSCluster_Node"
        }

        It "Carries ClusterName and ClusterFqdn as NoteProperty members added by Add-Member" {
            # characterization: these are injected via Add-Member -Force, not native CIM properties
            $clusterNameProp = $nodeResults[0].PSObject.Properties["ClusterName"]
            $clusterFqdnProp = $nodeResults[0].PSObject.Properties["ClusterFqdn"]
            $clusterNameProp.MemberType | Should -Be "NoteProperty"
            $clusterFqdnProp.MemberType | Should -Be "NoteProperty"
        }

        It "Reports cluster identity on each node" {
            $nodeResults[0].ClusterName | Should -Not -BeNullOrEmpty
            $nodeResults[0].ClusterFqdn | Should -Match "^$([regex]::Escape($nodeResults[0].ClusterName))\."
        }

        It "Reports a non-empty node Name for every returned node" {
            foreach ($node in $nodeResults) {
                $node.Name | Should -Not -BeNullOrEmpty
            }
        }

        It "Reports version bounds as positive integers" {
            $nodeResults[0].NodeHighestVersion | Should -BeGreaterThan 0
            $nodeResults[0].NodeLowestVersion | Should -BeGreaterThan 0
        }

        It "State is a native CIM property (not a NoteProperty) with a non-negative value" {
            # characterization: State comes directly from MSCluster_Node; value 0 = Up.
            # Unlike Get-DbaWsfcCluster which adds State as a null NoteProperty via a missing
            # helper, here State is the real CIM property. Do not "fix" without a surface-diff decision.
            $stateProp = $nodeResults[0].PSObject.Properties["State"]
            $stateProp | Should -Not -BeNullOrEmpty
            $stateProp.MemberType | Should -Not -Be "NoteProperty"
            [int]$nodeResults[0].State | Should -BeGreaterOrEqual 0
        }

        It "Accepts pipeline input and returns the same nodes" {
            $pipelineResults = @($TestConfig.InstanceMulti2 | Get-DbaWsfcNode)
            $pipelineResults.Count | Should -Be $nodeResults.Count
            $pipelineResults[0].ClusterName | Should -Be $nodeResults[0].ClusterName
        }
    }

    Context "When the target computer cannot be reached" {
        It "Warns and returns nothing even with EnableException" {
            # characterization: EnableException is not forwarded to the inner CIM lookup,
            # so connection failures always surface as a warning and the computer is skipped.
            $unreachableResult = Get-DbaWsfcNode -ComputerName "dbatoolsci_nohost" -EnableException -WarningVariable warnings -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
            $unreachableResult | Should -BeNullOrEmpty
            "$warnings" | Should -Match "Unable to find a connection to the target system"
        }
    }
}
