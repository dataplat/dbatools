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