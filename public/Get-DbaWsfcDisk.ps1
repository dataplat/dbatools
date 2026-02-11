function Get-DbaWsfcDisk {
    <#
    .SYNOPSIS
        Retrieves detailed information about clustered physical disks from Windows Server Failover Clusters.

    .DESCRIPTION
        Retrieves comprehensive disk information from Windows Server Failover Clusters including disk space usage, file systems, mount points, and cluster resource states. This function is essential for DBAs managing SQL Server Failover Cluster Instances who need to monitor storage health and capacity across cluster nodes. Returns detailed disk properties like total size, free space, volume labels, and serial numbers for each clustered disk resource, helping identify storage bottlenecks and plan capacity upgrades.

        All Windows Server Failover Clustering (Wsfc) commands require local admin on each member node.

    .PARAMETER ComputerName
        Specifies the Windows Server Failover Cluster to query for disk information. Accepts either a cluster node name or the cluster name itself.
        Use this when managing SQL Server Failover Cluster Instances to monitor storage across different cluster environments.

    .PARAMETER Credential
        Allows you to login to the cluster using alternative credentials.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: WSFC, FCI, WindowsCluster, HA
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .OUTPUTS
        PSCustomObject

        Returns one object per clustered disk partition found on the failover cluster.

        Default display properties (via Select-DefaultView -ExcludeProperty ClusterDisk, ClusterDiskPart, ClusterResource):
        - ClusterName: The name of the Windows Server Failover Cluster
        - ClusterFqdn: The fully qualified domain name of the cluster
        - ResourceGroup: The owner group of the disk resource
        - Disk: The disk resource name
        - State: The current state of the disk resource
        - FileSystem: The file system type (NTFS, ReFS, etc.)
        - Path: The mount path of the disk partition
        - Label: The volume label assigned to the disk
        - Size: Total size of the disk partition; dbasize object convertible to Bytes, KB, MB, GB, TB
        - Free: Free space available on the disk partition; dbasize object with unit conversion
        - MountPoints: Array of mount points for the disk partition
        - SerialNumber: The serial number of the physical disk

        Additional properties available (using Select-Object *):
        - ClusterDisk: The CIM MSCluster_Disk object representing the physical disk
        - ClusterDiskPart: The CIM MSCluster_DiskPartition object with full partition metadata
        - ClusterResource: The CIM MSCluster_Resource object representing the cluster resource

    .LINK
        https://dbatools.io/Get-DbaWsfcDisk

    .EXAMPLE
        PS C:\> Get-DbaWsfcDisk -ComputerName cluster01

        Gets disk information from the failover cluster cluster01
    #>
    [CmdletBinding()]
    param (
        [parameter(ValueFromPipeline)]
        [DbaInstanceParameter[]]$ComputerName = $env:COMPUTERNAME,
        [PSCredential]$Credential,
        [switch]$EnableException
    )
    process {
        foreach ($computer in $computername) {
            $resources = Get-DbaWsfcResource -ComputerName $computer -Credential $Credential | Where-Object Type -eq 'Physical Disk'
            foreach ($resource in $resources) {
                $disks = $resource | Get-CimAssociatedInstance -ResultClassName MSCluster_Disk
                foreach ($disk in $disks) {
                    $diskpart = $disk | Get-CimAssociatedInstance -ResultClassName MSCluster_DiskPartition
                    [PSCustomObject]@{
                        ClusterName     = $resource.ClusterName
                        ClusterFqdn     = $resource.ClusterFqdn
                        ResourceGroup   = $resource.OwnerGroup
                        Disk            = $resource.Name
                        State           = $resource.State
                        FileSystem      = $diskpart.FileSystem
                        Path            = $diskpart.Path
                        Label           = $diskpart.VolumeLabel
                        Size            = [dbasize]($diskpart.TotalSize * 1MB)
                        Free            = [dbasize]($diskpart.FreeSpace * 1MB)
                        MountPoints     = $diskpart.MountPoints
                        SerialNumber    = $diskpart.SerialNumber
                        ClusterDisk     = $disk
                        ClusterDiskPart = $diskpart
                        ClusterResource = $resource
                    } | Select-DefaultView -ExcludeProperty ClusterDisk, ClusterDiskPart, ClusterResource
                }
            }
        }
    }
}