#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaWsfcResourceGroup",
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
                "Name",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests -Skip:$env:appveyor {
    # Characterization tests (2026-07-06, Track A TA-071): pin the observed behavior of the live
    # implementation ahead of the C# port. InstanceMulti2 is the FCI network name (sqlcluster);
    # querying it reaches the WSFC (wincluster in the lab, sqlnode1/sqlnode2 as members).
    #
    # root\MSCluster CIM requires domain auth. This gate must run via PSDirect (Invoke-Command
    # -VMName workstation -Credential lab\cl) or a domain-authenticated session on the workstation;
    # the SSH-key gate (administrator@10.0.1.20) yields Access Denied from CIM and returns empty.
    #
    # Lab observation (2026-07-06): the lab WSFC (wincluster) exposes 3 resource groups:
    # "Available Storage" (Offline), "Cluster Group" (Online), "sqlcluster" (Online).
    # ClusterName="wincluster", ClusterFqdn="wincluster.lab.local".
    # State, ClusterName, ClusterFqdn are injected as NoteProperty members via Add-Member -Force.
    # PersistentState and OwnerNode are native CIM properties.
    Context "When querying the lab failover cluster" {
        BeforeAll {
            # No fixture setup -- read-only command. EnableException is NOT set globally:
            # inner helpers (Get-DbaWsfcCluster, Get-DbaCmObject) warn rather than throw when
            # CIM auth fails, so setting EnableException via PSDefaultParameterValues would
            # incorrectly turn those warnings into terminating errors.
            $groupResults = @(Get-DbaWsfcResourceGroup -ComputerName $TestConfig.InstanceMulti2)
        }

        It "Returns at least one resource group for a WSFC cluster" {
            # characterization: a minimal WSFC always has at least a Cluster Group
            $groupResults.Count | Should -BeGreaterOrEqual 1
        }

        It "Returns MSCluster_ResourceGroup CIM instances" {
            # characterization: output is a raw CIM instance with injected NoteProperty members
            $groupResults[0].PSObject.TypeNames[0] | Should -Match "MSCluster_ResourceGroup"
        }

        It "Carries ClusterName as a NoteProperty member added by Add-Member" {
            # characterization: ClusterName is injected via Add-Member -Force, not a native CIM property
            $prop = $groupResults[0].PSObject.Properties["ClusterName"]
            $prop | Should -Not -BeNullOrEmpty
            $prop.MemberType | Should -Be "NoteProperty"
        }

        It "Carries ClusterFqdn as a NoteProperty member added by Add-Member" {
            # characterization: ClusterFqdn is injected via Add-Member -Force, not a native CIM property
            $prop = $groupResults[0].PSObject.Properties["ClusterFqdn"]
            $prop | Should -Not -BeNullOrEmpty
            $prop.MemberType | Should -Be "NoteProperty"
        }

        It "Carries State as a NoteProperty that overwrites the CIM integer with a string" {
            # characterization: MSCluster_ResourceGroup.State is an integer in CIM; the command
            # replaces it with a human-readable string (e.g. 'Online', 'Offline') via Add-Member -Force
            $stateProp = $groupResults[0].PSObject.Properties["State"]
            $stateProp | Should -Not -BeNullOrEmpty
            $stateProp.MemberType | Should -Be "NoteProperty"
            $stateProp.TypeNameOfValue | Should -Be "System.String"
        }

        It "Reports cluster identity on each resource group" {
            $groupResults[0].ClusterName | Should -Not -BeNullOrEmpty
            $groupResults[0].ClusterFqdn | Should -Match "^$([regex]::Escape($groupResults[0].ClusterName))\."
        }

        It "Reports a non-empty Name for every returned resource group" {
            foreach ($grp in $groupResults) {
                $grp.Name | Should -Not -BeNullOrEmpty
            }
        }

        It "Reports State as a recognized string value on every resource group" {
            # characterization: Get-ResourceGroupState maps the CIM integer to one of these known strings
            $validStates = @("Online", "Offline", "Failed", "Unknown")
            foreach ($grp in $groupResults) {
                $grp.State | Should -BeIn $validStates
            }
        }

        It "Reports PersistentState as a native CIM property (not NoteProperty)" {
            # characterization: PersistentState comes directly from MSCluster_ResourceGroup, not injected
            $prop = $groupResults[0].PSObject.Properties["PersistentState"]
            $prop | Should -Not -BeNullOrEmpty
            $prop.MemberType | Should -Not -Be "NoteProperty"
        }

        It "Reports OwnerNode as a non-empty value on online resource groups" {
            # characterization: OwnerNode names the cluster node currently hosting the resource group
            $onlineGroups = $groupResults | Where-Object State -eq "Online"
            foreach ($grp in $onlineGroups) {
                $grp.OwnerNode | Should -Not -BeNullOrEmpty
            }
        }
    }

    Context "When using the -Name filter" {
        BeforeAll {
            $allGroups = @(Get-DbaWsfcResourceGroup -ComputerName $TestConfig.InstanceMulti2)
            # Pick the first group name to use as a filter target
            $firstGroupName = $allGroups[0].Name
        }

        It "Returns only the matching resource group when -Name is used" {
            # characterization: -Name uses Where-Object Name -in, so filtering is case-insensitive
            $filtered = @(Get-DbaWsfcResourceGroup -ComputerName $TestConfig.InstanceMulti2 -Name $firstGroupName)
            $filtered.Count | Should -Be 1
            $filtered[0].Name | Should -Be $firstGroupName
        }

        It "Returns multiple groups when -Name has multiple values" {
            # characterization: -Name accepts [string[]] and filters with -in, returning all matches
            $twoNames = @($allGroups[0].Name, $allGroups[1].Name)
            $multiFiltered = @(Get-DbaWsfcResourceGroup -ComputerName $TestConfig.InstanceMulti2 -Name $twoNames)
            $multiFiltered.Count | Should -Be 2
        }

        It "Returns nothing when -Name does not match any group" {
            # characterization: unmatched -Name yields no output (no warning, no error -- silent empty)
            $noMatch = @(Get-DbaWsfcResourceGroup -ComputerName $TestConfig.InstanceMulti2 -Name "dbatoolsci_nonexistent_group")
            $noMatch.Count | Should -Be 0
        }
    }

    Context "When using pipeline input" {
        BeforeAll {
            $allGroups = @(Get-DbaWsfcResourceGroup -ComputerName $TestConfig.InstanceMulti2)
        }

        It "Accepts pipeline input and returns the same group count" {
            # characterization: ComputerName accepts DbaInstanceParameter[] via ValueFromPipeline
            $pipelineResults = @($TestConfig.InstanceMulti2 | Get-DbaWsfcResourceGroup)
            $pipelineResults.Count | Should -Be $allGroups.Count
        }

        It "Pipeline result carries the same ClusterName as direct call" {
            $pipelineResults = @($TestConfig.InstanceMulti2 | Get-DbaWsfcResourceGroup)
            $pipelineResults[0].ClusterName | Should -Be $allGroups[0].ClusterName
        }
    }

    Context "When the target computer cannot be reached" {
        It "Warns and returns nothing for a non-existent host" {
            # characterization: Get-DbaWsfcResourceGroup calls Get-DbaWsfcCluster then Get-DbaCmObject.
            # When neither can connect, both inner helpers emit warnings and return empty;
            # the outer command produces no output.
            $splatBad = @{
                ComputerName    = "dbatoolsci_nohost"
                WarningVariable = "warnings"
                WarningAction   = "SilentlyContinue"
                ErrorAction     = "SilentlyContinue"
            }
            $unreachableResult = Get-DbaWsfcResourceGroup @splatBad
            $unreachableResult | Should -BeNullOrEmpty
            "$warnings" | Should -Match "Unable to find a connection to the target system"
        }
    }
}
