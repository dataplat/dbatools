#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaWsfcRole",
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
    # Characterization tests (2026-07-06, Track A TA-073): pin the observed behavior of the live
    # implementation ahead of the C# port. InstanceMulti2 is the FCI network name (sqlcluster);
    # querying it reaches the WSFC (wincluster in the lab, sqlnode1/sqlnode2 as members).
    #
    # root\MSCluster CIM requires domain auth. This gate must run via PSDirect (Invoke-Command
    # -VMName workstation -Credential lab\cl) or a domain-authenticated session on the workstation;
    # the SSH-key gate (administrator@10.0.1.20) yields Access Denied from CIM and returns empty.
    #
    # Lab observation (2026-07-06): the lab WSFC (wincluster) exposes 3 resource groups (roles):
    # "Available Storage", "Cluster Group", "sqlcluster".
    # ClusterName="wincluster", ClusterFqdn="wincluster.lab.local".
    # ClusterName and ClusterFqdn are injected as NoteProperty members via Add-Member -Force.
    # OwnerNode is a native CIM property (MemberType = Property).
    # State is also injected as NoteProperty via Add-Member -Force, but the source code has a
    # bug: it calls Get-ResourceState $resource.State instead of $role.State, so $resource is
    # undefined and State is always $null on every returned role.
    # characterization: current behavior -- State is always null; do not "fix" without a
    # surface-diff decision in the C# port.
    Context "When querying the lab failover cluster" {
        BeforeAll {
            # No fixture setup -- read-only command. EnableException is NOT set globally:
            # inner helpers (Get-DbaWsfcCluster, Get-DbaCmObject) warn rather than throw when
            # CIM auth fails, so setting EnableException via PSDefaultParameterValues would
            # incorrectly turn those warnings into terminating errors.
            $roleResults = @(Get-DbaWsfcRole -ComputerName $TestConfig.InstanceMulti2)
        }

        It "Returns at least one role for a WSFC cluster" {
            # characterization: a minimal WSFC always has at least a Cluster Group role
            $roleResults.Count | Should -BeGreaterOrEqual 1
        }

        It "Returns MSCluster_ResourceGroup CIM instances" {
            # characterization: Get-DbaWsfcRole queries MSCluster_ResourceGroup (same CIM class
            # as Get-DbaWsfcResourceGroup); output is a raw CIM instance with injected NoteProperty members
            $roleResults[0].PSObject.TypeNames[0] | Should -Match "MSCluster_ResourceGroup"
        }

        It "Carries ClusterName as a NoteProperty member added by Add-Member" {
            # characterization: ClusterName is injected via Add-Member -Force, not a native CIM property
            $prop = $roleResults[0].PSObject.Properties["ClusterName"]
            $prop | Should -Not -BeNullOrEmpty
            $prop.MemberType | Should -Be "NoteProperty"
        }

        It "Carries ClusterFqdn as a NoteProperty member added by Add-Member" {
            # characterization: ClusterFqdn is injected via Add-Member -Force, not a native CIM property
            $prop = $roleResults[0].PSObject.Properties["ClusterFqdn"]
            $prop | Should -Not -BeNullOrEmpty
            $prop.MemberType | Should -Be "NoteProperty"
        }

        It "Carries State as a NoteProperty that is always null due to a variable bug" {
            # characterization: the source code calls Get-ResourceState $resource.State but $resource
            # is not defined in scope (the loop variable is $role); $resource.State is $null and
            # Get-ResourceState $null returns nothing, so State is always $null on every role.
            # characterization: current behavior, do not "fix" without a surface-diff decision.
            $stateProp = $roleResults[0].PSObject.Properties["State"]
            $stateProp | Should -Not -BeNullOrEmpty
            $stateProp.MemberType | Should -Be "NoteProperty"
            $stateProp.Value | Should -BeNullOrEmpty
        }

        It "Reports cluster identity on each role" {
            $roleResults[0].ClusterName | Should -Not -BeNullOrEmpty
            $roleResults[0].ClusterFqdn | Should -Match "^$([regex]::Escape($roleResults[0].ClusterName))\."
        }

        It "Reports a non-empty Name for every returned role" {
            foreach ($role in $roleResults) {
                $role.Name | Should -Not -BeNullOrEmpty
            }
        }

        It "Reports OwnerNode as a native CIM property (not NoteProperty) on every role" {
            # characterization: OwnerNode comes directly from MSCluster_ResourceGroup, not injected
            foreach ($role in $roleResults) {
                $prop = $role.PSObject.Properties["OwnerNode"]
                $prop | Should -Not -BeNullOrEmpty
                $prop.MemberType | Should -Not -Be "NoteProperty"
            }
        }

        It "Reports the same ClusterName and ClusterFqdn on every role" {
            # characterization: all roles in one cluster share the same cluster identity
            $clusterNames = $roleResults | Select-Object -ExpandProperty ClusterName -Unique
            $clusterNames.Count | Should -Be 1
            $clusterFqdns = $roleResults | Select-Object -ExpandProperty ClusterFqdn -Unique
            $clusterFqdns.Count | Should -Be 1
        }
    }

    Context "When using pipeline input" {
        BeforeAll {
            $allRoles = @(Get-DbaWsfcRole -ComputerName $TestConfig.InstanceMulti2)
        }

        It "Accepts pipeline input and returns the same role count" {
            # characterization: ComputerName accepts DbaInstanceParameter[] via ValueFromPipeline
            $pipelineResults = @($TestConfig.InstanceMulti2 | Get-DbaWsfcRole)
            $pipelineResults.Count | Should -Be $allRoles.Count
        }

        It "Pipeline result carries the same ClusterName as direct call" {
            $pipelineResults = @($TestConfig.InstanceMulti2 | Get-DbaWsfcRole)
            $pipelineResults[0].ClusterName | Should -Be $allRoles[0].ClusterName
        }
    }

    Context "When the target computer cannot be reached" {
        It "Warns and returns nothing for a non-existent host" {
            # characterization: Get-DbaWsfcRole calls Get-DbaWsfcCluster then Get-DbaCmObject.
            # When neither can connect, both inner helpers emit warnings and return empty;
            # the outer command produces no output.
            $splatBad = @{
                ComputerName    = "dbatoolsci_nohost"
                WarningVariable = "warnings"
                WarningAction   = "SilentlyContinue"
                ErrorAction     = "SilentlyContinue"
            }
            $unreachableResult = Get-DbaWsfcRole @splatBad
            $unreachableResult | Should -BeNullOrEmpty
            "$warnings" | Should -Match "Unable to find a connection to the target system"
        }
    }
}
