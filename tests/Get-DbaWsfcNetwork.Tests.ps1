#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaWsfcNetwork",
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

Describe $CommandName -Tag IntegrationTests -Skip:$env:appveyor {
    # Characterization tests (2026-07-06, Track A TA-067): pin the observed behavior of the live
    # implementation ahead of the C# port. InstanceMulti2 is the FCI network name (sqlcluster);
    # querying it reaches the WSFC (wincluster in the lab, sqlnode1/sqlnode2 as members).
    #
    # root\MSCluster CIM requires domain auth. This gate must run via PSDirect (Invoke-Command
    # -VMName workstation -Credential lab\cl) or a domain-authenticated session on the workstation;
    # the SSH-key gate (administrator@10.0.1.20) yields Access Denied from CIM and returns empty.
    #
    # Lab observation (2026-07-06): the lab cluster (wincluster) exposes exactly one cluster
    # network named "Cluster Network 1" at 10.0.1.0/255.255.255.0 with Role=3 (internal+client)
    # and State=3 (up). IPv4Addresses is a String[] containing the network address. QuorumType
    # and RequestReplyTimeout are empty in this lab. ClusterName and ClusterFqdn are injected
    # as NoteProperty members via Add-Member -Force (not native CIM properties).
    Context "When querying the lab failover cluster" {
        BeforeAll {
            # No fixture setup — read-only command. EnableException is NOT set globally:
            # inner helpers (Get-DbaWsfcCluster, Get-DbaCmObject) warn rather than throw when
            # CIM auth fails, so setting EnableException via PSDefaultParameterValues would
            # incorrectly turn those warnings into terminating errors.
            $networkResults = @(Get-DbaWsfcNetwork -ComputerName $TestConfig.InstanceMulti2)
        }

        It "Returns at least one network object from the FCI cluster" {
            $networkResults.Count | Should -BeGreaterOrEqual 1
        }

        It "Returns MSCluster_Network CIM instances" {
            # characterization: output is a raw CIM instance, not a PSCustomObject wrapper
            $networkResults[0].PSObject.TypeNames[0] | Should -Match "MSCluster_Network"
        }

        It "Carries ClusterName and ClusterFqdn as NoteProperty members added by Add-Member" {
            # characterization: these are injected via Add-Member -Force, not native CIM properties
            $clusterNameProp = $networkResults[0].PSObject.Properties["ClusterName"]
            $clusterFqdnProp = $networkResults[0].PSObject.Properties["ClusterFqdn"]
            $clusterNameProp.MemberType | Should -Be "NoteProperty"
            $clusterFqdnProp.MemberType | Should -Be "NoteProperty"
        }

        It "Reports cluster identity on each network" {
            $networkResults[0].ClusterName | Should -Not -BeNullOrEmpty
            $networkResults[0].ClusterFqdn | Should -Match "^$([regex]::Escape($networkResults[0].ClusterName))\."
        }

        It "Reports a non-empty network Name for every returned network" {
            foreach ($net in $networkResults) {
                $net.Name | Should -Not -BeNullOrEmpty
            }
        }

        It "Reports non-empty Address and AddressMask for the cluster network" {
            $networkResults[0].Address | Should -Not -BeNullOrEmpty
            $networkResults[0].AddressMask | Should -Not -BeNullOrEmpty
        }

        It "Reports Role as a native CIM property (not a NoteProperty) with a non-negative UInt32 value" {
            # characterization: Role is a native MSCluster_Network CIM property (UInt32), not
            # injected via Add-Member. Value 3 = internal+client network in the lab.
            $roleProp = $networkResults[0].PSObject.Properties["Role"]
            $roleProp | Should -Not -BeNullOrEmpty
            $roleProp.MemberType | Should -Not -Be "NoteProperty"
            [uint32]$networkResults[0].Role | Should -BeGreaterOrEqual 0
        }

        It "Reports State as a native CIM property (not a NoteProperty) with a non-negative value" {
            # characterization: State is the native MSCluster_Network CIM property (UInt32).
            # Value 3 = up in the lab. Do not 'fix' without a surface-diff decision.
            $stateProp = $networkResults[0].PSObject.Properties["State"]
            $stateProp | Should -Not -BeNullOrEmpty
            $stateProp.MemberType | Should -Not -Be "NoteProperty"
            [uint32]$networkResults[0].State | Should -BeGreaterOrEqual 0
        }

        It "Reports IPv4Addresses as a String array" {
            # characterization: IPv4Addresses is String[] from the CIM property;
            # in the lab it contains the network address (e.g. '10.0.1.0')
            $networkResults[0].IPv4Addresses | Should -BeOfType [string]
        }

        It "Accepts pipeline input and returns the same network count" {
            # characterization: ComputerName accepts DbaInstanceParameter[] via ValueFromPipeline
            $pipelineResults = @($TestConfig.InstanceMulti2 | Get-DbaWsfcNetwork)
            $pipelineResults.Count | Should -Be $networkResults.Count
            $pipelineResults[0].ClusterName | Should -Be $networkResults[0].ClusterName
        }
    }

    Context "When the target computer cannot be reached" {
        It "Warns and returns nothing for a non-existent host" {
            # characterization: Get-DbaWsfcNetwork calls Get-DbaWsfcCluster then Get-DbaCmObject.
            # When neither can connect, all inner calls return empty and no output is produced.
            # The outer command warns via Get-DbaWsfcCluster and returns nothing.
            $unreachableResult = Get-DbaWsfcNetwork -ComputerName "dbatoolsci_nohost" -WarningVariable warnings -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
            $unreachableResult | Should -BeNullOrEmpty
            "$warnings" | Should -Match "Unable to find a connection to the target system"
        }
    }
}
