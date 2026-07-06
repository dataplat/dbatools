#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaWsfcResource",
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
    # Characterization tests (2026-07-06, Track A TA-070): pin the observed behavior of the live
    # implementation ahead of the C# port. InstanceMulti2 is the FCI network name (sqlcluster);
    # querying it reaches the WSFC (wincluster in the lab, sqlnode1/sqlnode2 as members).
    #
    # root\MSCluster CIM requires domain auth. This gate must run via PSDirect (Invoke-Command
    # -VMName workstation -Credential lab\cl) or a domain-authenticated session on the workstation;
    # the SSH-key gate (administrator@10.0.1.20) yields Access Denied from CIM and returns empty.
    #
    # Lab observation (2026-07-06): the lab WSFC (wincluster) exposes 11 resources covering
    # types: Physical Disk, IP Address, Network Name, File Share Witness, SQL Server,
    # SQL Server Agent, Generic Service. All resources were Online. ClusterName="wincluster",
    # ClusterFqdn="wincluster.lab.local". State, ClusterName, ClusterFqdn are all injected as
    # NoteProperty members via Add-Member -Force (not native CIM properties).
    Context "When querying the lab failover cluster" {
        BeforeAll {
            # No fixture setup -- read-only command. EnableException is NOT set globally:
            # inner helpers (Get-DbaWsfcCluster, Get-DbaCmObject) warn rather than throw when
            # CIM auth fails, so setting EnableException via PSDefaultParameterValues would
            # incorrectly turn those warnings into terminating errors.
            $resourceResults = @(Get-DbaWsfcResource -ComputerName $TestConfig.InstanceMulti2)
        }

        It "Returns resource objects (at least 5 for a minimal SQL FCI)" {
            # characterization: an FCI always has at minimum SQL Server, SQL Server Agent,
            # IP Address, Network Name, and one disk resource
            $resourceResults.Count | Should -BeGreaterOrEqual 5
        }

        It "Returns MSCluster_Resource CIM instances" {
            # characterization: output is a raw CIM instance with injected NoteProperty members,
            # not a PSCustomObject wrapper
            $resourceResults[0].PSObject.TypeNames[0] | Should -Match "MSCluster_Resource"
        }

        It "Carries ClusterName as a NoteProperty member added by Add-Member" {
            # characterization: ClusterName is injected via Add-Member -Force, not a native CIM property
            $clusterNameProp = $resourceResults[0].PSObject.Properties["ClusterName"]
            $clusterNameProp | Should -Not -BeNullOrEmpty
            $clusterNameProp.MemberType | Should -Be "NoteProperty"
        }

        It "Carries ClusterFqdn as a NoteProperty member added by Add-Member" {
            # characterization: ClusterFqdn is injected via Add-Member -Force, not a native CIM property
            $clusterFqdnProp = $resourceResults[0].PSObject.Properties["ClusterFqdn"]
            $clusterFqdnProp | Should -Not -BeNullOrEmpty
            $clusterFqdnProp.MemberType | Should -Be "NoteProperty"
        }

        It "Carries State as a NoteProperty that overwrites the CIM integer with a string" {
            # characterization: the original MSCluster_Resource.State is an integer; Get-DbaWsfcResource
            # replaces it with a human-readable string (e.g. 'Online') via Add-Member -Force
            $stateProp = $resourceResults[0].PSObject.Properties["State"]
            $stateProp | Should -Not -BeNullOrEmpty
            $stateProp.MemberType | Should -Be "NoteProperty"
            $stateProp.TypeNameOfValue | Should -Be "System.String"
        }

        It "Reports cluster identity on each resource" {
            $resourceResults[0].ClusterName | Should -Not -BeNullOrEmpty
            $resourceResults[0].ClusterFqdn | Should -Match "^$([regex]::Escape($resourceResults[0].ClusterName))\."
        }

        It "Reports a non-empty Name for every returned resource" {
            foreach ($res in $resourceResults) {
                $res.Name | Should -Not -BeNullOrEmpty
            }
        }

        It "Reports a non-empty Type for every returned resource" {
            foreach ($res in $resourceResults) {
                $res.Type | Should -Not -BeNullOrEmpty
            }
        }

        It "Reports a non-empty OwnerGroup for every returned resource" {
            foreach ($res in $resourceResults) {
                $res.OwnerGroup | Should -Not -BeNullOrEmpty
            }
        }

        It "Reports a non-empty OwnerNode for every returned resource" {
            # characterization: OwnerNode names the cluster node currently hosting the resource
            foreach ($res in $resourceResults) {
                $res.OwnerNode | Should -Not -BeNullOrEmpty
            }
        }

        It "Includes a SQL Server resource type for this FCI" {
            # characterization: every SQL Server FCI exposes a resource of Type 'SQL Server'
            $sqlResource = $resourceResults | Where-Object Type -eq "SQL Server"
            $sqlResource | Should -Not -BeNullOrEmpty
        }

        It "Reports State as a recognized string value on every resource" {
            # characterization: Get-ResourceState maps the CIM integer to one of these known strings
            $validStates = @("Online", "Offline", "Failed", "Initializing", "Pending", "Unknown")
            foreach ($res in $resourceResults) {
                $res.State | Should -BeIn $validStates
            }
        }

        It "Reports RestartAction as a uint32 on every resource" {
            # characterization: RestartAction is a native CIM uint32 (0=DoNotRestart, 1=RestartWithoutFailover,
            # 2=RestartWithFailover); the lab observed both 1 and 2 across its 11 resources
            foreach ($res in $resourceResults) {
                $res.RestartAction | Should -BeOfType [uint32]
            }
        }

        It "Reports PersistentState as a native CIM property (not NoteProperty)" {
            # characterization: PersistentState comes directly from MSCluster_Resource
            $prop = $resourceResults[0].PSObject.Properties["PersistentState"]
            $prop | Should -Not -BeNullOrEmpty
            $prop.MemberType | Should -Not -Be "NoteProperty"
        }

        It "Accepts pipeline input and returns the same resource count" {
            # characterization: ComputerName accepts DbaInstanceParameter[] via ValueFromPipeline
            $pipelineResults = @($TestConfig.InstanceMulti2 | Get-DbaWsfcResource)
            $pipelineResults.Count | Should -Be $resourceResults.Count
            $pipelineResults[0].ClusterName | Should -Be $resourceResults[0].ClusterName
        }
    }

    Context "When the target computer cannot be reached" {
        It "Warns and returns nothing for a non-existent host" {
            # characterization: Get-DbaWsfcResource calls Get-DbaWsfcCluster then Get-DbaCmObject.
            # When neither can connect, both inner helpers emit warnings and return empty;
            # the outer command produces no output.
            $unreachableResult = Get-DbaWsfcResource -ComputerName "dbatoolsci_nohost" -WarningVariable warnings -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
            $unreachableResult | Should -BeNullOrEmpty
            "$warnings" | Should -Match "Unable to find a connection to the target system"
        }
    }
}