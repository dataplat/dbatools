function Get-DbaWsfcNode {
    <#
    .SYNOPSIS
        Retrieves detailed node information from Windows Server Failover Clusters hosting SQL Server instances.

    .DESCRIPTION
        Retrieves configuration and status details for individual nodes (servers) within Windows Server Failover Clusters that host SQL Server FCIs or Availability Groups. This function connects to cluster nodes to gather essential node properties including ownership details, version information, and operational status.

        DBAs use this when troubleshooting cluster node issues, validating node configurations before SQL Server failover operations, or auditing cluster member server details. The function returns key node metadata needed for capacity planning, patch management coordination, and high availability troubleshooting.

        All Windows Server Failover Clustering (Wsfc) commands require local admin on each member node.

    .PARAMETER ComputerName
        Specifies the Windows Server Failover Cluster or individual cluster node to query for node information. Accepts either the cluster name or any member node name.
        Use this when you need to connect to a specific cluster hosting SQL Server FCIs or Availability Groups to retrieve node details.

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
        Microsoft.Management.Infrastructure.CimInstance#root/MSCluster/MSCluster_Node

        Returns one node object per cluster member node queried. Each object represents a cluster node with ownership and version information.

        Default display properties (via Select-DefaultView):
        - ClusterName: The name of the Windows Server Failover Cluster
        - ClusterFqdn: The fully qualified domain name of the cluster
        - Name: The name of the cluster node (server name)
        - PrimaryOwnerName: The primary owner of the node resource
        - PrimaryOwnerContact: Contact information for the primary owner
        - Dedicated: Boolean indicating if the node is dedicated to clustering
        - NodeHighestVersion: The highest cluster API version supported by this node
        - NodeLowestVersion: The lowest cluster API version supported by this node

        Additional properties available via Select-Object *:
        All properties from the MSCluster_Node WMI class, including node state, resource ownership, and cluster communication details.

    .LINK
        https://dbatools.io/Get-DbaWsfcNode

    .EXAMPLE
        PS C:\> Get-DbaWsfcNode -ComputerName cluster01

        Gets node information from the failover cluster cluster01

    .EXAMPLE
        PS C:\> Get-DbaWsfcNode -ComputerName cluster01 | Select-Object *

        Shows all node values, including the ones not shown in the default view
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
            $node = Get-DbaCmObject -Computername $computer -Credential $Credential -Namespace root\MSCluster -ClassName MSCluster_Node
            $node | Add-Member -Force -NotePropertyName ClusterName -NotePropertyValue $cluster.Name
            $node | Add-Member -Force -NotePropertyName ClusterFqdn -NotePropertyValue $cluster.Fqdn
            $node | Select-DefaultView -Property ClusterName, ClusterFqdn, Name, PrimaryOwnerName, PrimaryOwnerContact, Dedicated, NodeHighestVersion, NodeLowestVersion
        }
    }
}