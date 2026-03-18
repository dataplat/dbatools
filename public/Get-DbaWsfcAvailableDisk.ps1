function Get-DbaWsfcAvailableDisk {
    <#
    .SYNOPSIS
        Retrieves shared storage disks available for clustering but not yet assigned to a Windows Server Failover Cluster.

    .DESCRIPTION
        Identifies shared storage disks that are visible to all cluster nodes and eligible for clustering, but have not yet been added to the cluster's storage pool. This is essential when planning to expand SQL Server Failover Cluster Instances (FCIs) or troubleshooting storage connectivity issues. The function queries each cluster node to ensure disks are properly accessible across the entire cluster before attempting to add them as cluster resources.

        All Windows Server Failover Clustering (Wsfc) commands require local admin on each member node.

    .PARAMETER ComputerName
        Specifies the Windows Server Failover Cluster name or any cluster node name to query for available disks.
        Use this when you need to check shared storage from a specific cluster, especially when managing multiple clusters or troubleshooting storage visibility across cluster nodes.
        Accepts multiple values to query several clusters simultaneously.

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
        Microsoft.Management.Infrastructure.CimInstance#root/MSCluster/MSCluster_AvailableDisk

        Returns one object per available disk that can be added to the cluster. The disk must be visible to all cluster nodes to be considered available.

        All properties from the MSCluster_AvailableDisk WMI class are returned, including:

        Properties added via Add-Member:
        - State: Current operational state of the disk
        - ClusterName: Name of the cluster
        - ClusterFqdn: Fully qualified domain name of the cluster

        Standard WMI properties from MSCluster_AvailableDisk:
        - Name: Label or designation of the disk
        - Id: Unique disk identifier (GUID for virtual disks, GptGuid or Signature for physical disks)
        - Size: Physical disk capacity in bytes
        - Number: Disk number as seen on the host node
        - Status: Operational status (OK, Degraded, Error, etc.)
        - ConnectedNodes: Array of cluster node names that can access the disk
        - Signature: MBR disk signature value
        - GptGuid: GUID for GPT-partitioned disks
        - ScsiPort: SCSI port number
        - ScsiBus: SCSI bus identifier
        - ScsiTargetID: SCSI target identification number
        - ScsiLUN: SCSI logical unit number
        - Node: Name of the node providing the disk information
        - ResourceName: Resource name when adding disk to cluster

        All properties from the base WMI object are accessible; the function returns the complete object without filtering.

    .LINK
        https://dbatools.io/Get-DbaWsfcAvailableDisk

    .EXAMPLE
        PS C:\> Get-DbaWsfcAvailableDisk -ComputerName cluster01

        Gets available disks from the failover cluster cluster01
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
            $cluster = Get-DbaWsfcCluster -ComputerName $computer -Credential $Credential
            $disk = Get-DbaCmObject -Computername $computer -Credential $Credential -Namespace root\MSCluster -ClassName MSCluster_AvailableDisk

            # I don't have an available disk, so I can't see how to clean this up: Passthru
            $disk | Add-Member -Force -NotePropertyName State -NotePropertyValue (Get-ResourceState $resource.State)
            $disk | Add-Member -Force -NotePropertyName ClusterName -NotePropertyValue $cluster.Name
            $disk | Add-Member -Force -NotePropertyName ClusterFqdn -NotePropertyValue $cluster.Fqdn -PassThru
        }
    }
}