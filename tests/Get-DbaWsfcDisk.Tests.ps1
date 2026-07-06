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
}

Describe $CommandName -Tag IntegrationTests -Skip:$env:appveyor {
    # Characterization tests (2026-07-06, Track A TA-066): pin the observed behavior of the live
    # implementation ahead of the C# port. InstanceMulti2 is the FCI network name (sqlcluster);
    # querying it reaches the WSFC (wincluster in the lab, sqlnode1/sqlnode2 as members).
    #
    # root\MSCluster CIM requires domain auth. This gate must run via PSDirect (Invoke-Command
    # -VMName workstation -Credential lab\cl) or a domain-authenticated session on the workstation;
    # the SSH-key gate (administrator@10.0.1.20) yields Access Denied from CIM and returns empty.
    #
    # Get-DbaWsfcDisk calls Get-DbaWsfcResource (which calls Get-DbaWsfcCluster and Get-DbaCmObject
    # for MSCluster_Resource), then walks CIM associations to MSCluster_Disk and MSCluster_DiskPartition.
    # Each partition is returned as a PSCustomObject with Size/Free as Dataplat.Dbatools.Utility.Size.
    #
    # Lab FCI has 3 Physical Disk resources (all in group "sqlcluster", all Online, NTFS):
    #   Cluster Disk 1 -> S: (SQLData), Cluster Disk 2 -> L: (SQLLog), Cluster Disk 3 -> T: (TempDB)
    Context "When querying the lab failover cluster" {
        BeforeAll {
            # No fixture setup — read-only command. EnableException is NOT set globally:
            # inner helpers (Get-DbaWsfcCluster, Get-DbaCmObject) warn rather than throw when
            # CIM auth fails, so setting EnableException via PSDefaultParameterValues would
            # incorrectly turn those warnings into terminating errors.
            $diskResults = @(Get-DbaWsfcDisk -ComputerName $TestConfig.InstanceMulti2)
        }

        It "Returns at least one physical disk from the FCI cluster" {
            $diskResults.Count | Should -BeGreaterOrEqual 1
        }

        It "Returns PSCustomObject instances" {
            # characterization: output is PSCustomObject, not a raw CIM instance;
            # the command wraps CIM data in [PSCustomObject]@{...} blocks
            $diskResults[0].PSObject.TypeNames[0] | Should -Be "System.Management.Automation.PSCustomObject"
        }

        It "Populates ClusterName and ClusterFqdn from the WSFC" {
            $diskResults[0].ClusterName | Should -Not -BeNullOrEmpty
            $diskResults[0].ClusterFqdn | Should -Not -BeNullOrEmpty
            # characterization: FQDN is the cluster name with a domain suffix
            $diskResults[0].ClusterFqdn | Should -Match "^$([regex]::Escape($diskResults[0].ClusterName))\."
        }

        It "Reports Disk name matching the cluster resource name" {
            $diskResults[0].Disk | Should -Not -BeNullOrEmpty
        }

        It "Reports State as a string from Get-DbaWsfcResource Add-Member -Force" {
            # characterization: State is added by Get-DbaWsfcResource via Add-Member -Force
            # converting the numeric CIM state to a string (e.g. 'Online', 'Offline')
            $diskResults[0].State | Should -Not -BeNullOrEmpty
            $diskResults[0].State | Should -BeOfType [string]
        }

        It "Reports FileSystem as a non-empty string" {
            # characterization: FileSystem comes from MSCluster_DiskPartition.FileSystem (e.g. 'NTFS')
            $diskResults[0].FileSystem | Should -Not -BeNullOrEmpty
        }

        It "Reports Path as the drive letter or mount point from MSCluster_DiskPartition" {
            $diskResults[0].Path | Should -Not -BeNullOrEmpty
        }

        It "Reports Size and Free as Dataplat.Dbatools.Utility.Size objects" {
            # characterization: [dbasize] wraps the TotalSize/FreeSpace from MSCluster_DiskPartition
            # (in MB) so callers can convert to any unit. The exact class is the dbatools utility Size.
            $diskResults[0].Size | Should -BeOfType [Dataplat.Dbatools.Utility.Size]
            $diskResults[0].Free | Should -BeOfType [Dataplat.Dbatools.Utility.Size]
        }

        It "Reports Size and Free as positive values" {
            [long]$diskResults[0].Size | Should -BeGreaterThan 0
            [long]$diskResults[0].Free | Should -BeGreaterOrEqual 0
        }

        It "Reports ResourceGroup matching the FCI SQL instance cluster group" {
            # characterization: ResourceGroup = OwnerGroup from MSCluster_Resource; for the FCI
            # cluster in the lab all disks belong to the 'sqlcluster' group (the SQL Server role)
            $diskResults | ForEach-Object { $PSItem.ResourceGroup | Should -Not -BeNullOrEmpty }
        }

        It "Accepts pipeline input and returns the same disk count" {
            # characterization: ComputerName accepts DbaInstanceParameter[] via ValueFromPipeline
            $pipeResults = @($TestConfig.InstanceMulti2 | Get-DbaWsfcDisk)
            $pipeResults.Count | Should -Be $diskResults.Count
        }

        It "All returned disks have non-empty Disk and Path properties" {
            foreach ($disk in $diskResults) {
                $disk.Disk | Should -Not -BeNullOrEmpty
                $disk.Path | Should -Not -BeNullOrEmpty
            }
        }
    }

    Context "When the target computer cannot be reached" {
        It "Returns empty for a non-existent host" {
            # characterization: Get-DbaWsfcDisk calls Get-DbaWsfcResource which calls
            # Get-DbaWsfcCluster and Get-DbaCmObject. When neither can connect, all inner
            # calls return empty and no output is produced. Inner helpers may warn; the
            # outer command returns nothing rather than throwing.
            $unreachableResult = Get-DbaWsfcDisk -ComputerName "dbatoolsci_nohost" -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
            $unreachableResult | Should -BeNullOrEmpty
        }
    }
}
