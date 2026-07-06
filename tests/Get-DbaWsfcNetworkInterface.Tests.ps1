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
}

Describe $CommandName -Tag IntegrationTests -Skip:$env:appveyor {
    # Characterization tests (2026-07-06, Track A TA-068): pin the observed behavior of the live
    # implementation ahead of the C# port. InstanceMulti2 is the FCI network name (sqlcluster);
    # querying it reaches the WSFC (wincluster in the lab, sqlnode1/sqlnode2 as members).
    #
    # root\MSCluster CIM requires domain auth. This gate must run via PSDirect (Invoke-Command
    # -VMName workstation -Credential lab\cl) or a domain-authenticated session on the workstation;
    # the SSH-key gate (administrator@10.0.1.20) yields Access Denied from CIM and returns empty.
    #
    # Lab observation (2026-07-06): the lab WSFC (wincluster) exposes two network interfaces,
    # one per node: "sqlnode1 - Ethernet" (10.0.1.35) and "sqlnode2 - Ethernet" (10.0.1.36),
    # both on "Cluster Network 1", both with DhcpEnabled=False, IPv4Addresses populated and
    # IPv6Addresses empty. ClusterName and ClusterFqdn are injected as NoteProperty members
    # via Add-Member -Force (not native CIM properties).
    #
    # Characterization note: the public source calls Select-DefaultView with IPv6Addresses
    # listed TWICE (copy-paste quirk). This does not affect the data returned but is current
    # behavior — do not "fix" without a surface-diff decision.
    Context "When querying the lab failover cluster" {
        BeforeAll {
            # No fixture setup — read-only command. EnableException is NOT set globally:
            # inner helpers (Get-DbaWsfcCluster, Get-DbaCmObject) warn rather than throw when
            # CIM auth fails, so setting EnableException via PSDefaultParameterValues would
            # incorrectly turn those warnings into terminating errors.
            $ifaceResults = @(Get-DbaWsfcNetworkInterface -ComputerName $TestConfig.InstanceMulti2)
        }

        It "Returns at least two network interface objects (one per cluster node)" {
            $ifaceResults.Count | Should -BeGreaterOrEqual 2
        }

        It "Returns MSCluster_NetworkInterface CIM instances" {
            # characterization: output is a raw CIM instance, not a PSCustomObject wrapper
            $ifaceResults[0].PSObject.TypeNames[0] | Should -Match "MSCluster_NetworkInterface"
        }

        It "Carries ClusterName and ClusterFqdn as NoteProperty members added by Add-Member" {
            # characterization: these are injected via Add-Member -Force, not native CIM properties
            $clusterNameProp = $ifaceResults[0].PSObject.Properties["ClusterName"]
            $clusterFqdnProp = $ifaceResults[0].PSObject.Properties["ClusterFqdn"]
            $clusterNameProp.MemberType | Should -Be "NoteProperty"
            $clusterFqdnProp.MemberType | Should -Be "NoteProperty"
        }

        It "Reports cluster identity on each interface" {
            $ifaceResults[0].ClusterName | Should -Not -BeNullOrEmpty
            $ifaceResults[0].ClusterFqdn | Should -Match "^$([regex]::Escape($ifaceResults[0].ClusterName))\."
        }

        It "Reports a non-empty Name for every returned interface" {
            foreach ($iface in $ifaceResults) {
                $iface.Name | Should -Not -BeNullOrEmpty
            }
        }

        It "Reports a non-empty Node for every returned interface" {
            # characterization: Node is the native MSCluster_NetworkInterface CIM property
            # naming the cluster node this adapter belongs to (e.g. 'sqlnode1', 'sqlnode2')
            foreach ($iface in $ifaceResults) {
                $iface.Node | Should -Not -BeNullOrEmpty
            }
        }

        It "Returns one interface per cluster node" {
            # characterization: lab WSFC has two nodes; each exposes one network interface
            $uniqueNodes = $ifaceResults | Select-Object -ExpandProperty Node -Unique
            $uniqueNodes.Count | Should -Be $ifaceResults.Count
        }

        It "Reports a non-empty Network for every returned interface" {
            # characterization: Network names the MSCluster network this adapter belongs to
            # (e.g. 'Cluster Network 1' in the lab)
            foreach ($iface in $ifaceResults) {
                $iface.Network | Should -Not -BeNullOrEmpty
            }
        }

        It "Reports a non-empty Address for every returned interface" {
            # characterization: Address is the IPv4 address of this network adapter on the node
            foreach ($iface in $ifaceResults) {
                $iface.Address | Should -Not -BeNullOrEmpty
            }
        }

        It "Reports DhcpEnabled as a native CIM property (not a NoteProperty)" {
            # characterization: DhcpEnabled comes directly from MSCluster_NetworkInterface;
            # in the lab it is False (static IP addresses on all nodes)
            $dhcpProp = $ifaceResults[0].PSObject.Properties["DhcpEnabled"]
            $dhcpProp | Should -Not -BeNullOrEmpty
            $dhcpProp.MemberType | Should -Not -Be "NoteProperty"
        }

        It "Reports IPv4Addresses as a non-empty string on each interface" {
            # characterization: IPv4Addresses is a String (or String[]) from the CIM property;
            # in the lab each interface has exactly one IPv4 address matching its Address field
            foreach ($iface in $ifaceResults) {
                $iface.IPv4Addresses | Should -Not -BeNullOrEmpty
            }
        }

        It "Reports Adapter as a non-empty string on each interface" {
            # characterization: Adapter is the adapter friendly name (e.g. 'Microsoft Hyper-V Network Adapter')
            foreach ($iface in $ifaceResults) {
                $iface.Adapter | Should -Not -BeNullOrEmpty
            }
        }

        It "Accepts pipeline input and returns the same interface count" {
            # characterization: ComputerName accepts DbaInstanceParameter[] via ValueFromPipeline
            $pipelineResults = @($TestConfig.InstanceMulti2 | Get-DbaWsfcNetworkInterface)
            $pipelineResults.Count | Should -Be $ifaceResults.Count
            $pipelineResults[0].ClusterName | Should -Be $ifaceResults[0].ClusterName
        }
    }

    Context "When the target computer cannot be reached" {
        It "Warns and returns nothing for a non-existent host" {
            # characterization: Get-DbaWsfcNetworkInterface calls Get-DbaWsfcCluster then
            # Get-DbaCmObject. When neither can connect, all inner calls return empty and no
            # output is produced. The outer command warns via both inner helpers and returns nothing.
            $unreachableResult = Get-DbaWsfcNetworkInterface -ComputerName "dbatoolsci_nohost" -WarningVariable warnings -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
            $unreachableResult | Should -BeNullOrEmpty
            "$warnings" | Should -Match "Unable to find a connection to the target system"
        }
    }
}
