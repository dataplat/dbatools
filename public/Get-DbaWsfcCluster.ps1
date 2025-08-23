function Get-DbaWsfcCluster {
    <#
    .SYNOPSIS
        Retrieves Windows Server Failover Cluster configuration and status information for SQL Server high availability environments.

    .DESCRIPTION
        Retrieves detailed configuration and operational status information from Windows Server Failover Clusters that host SQL Server instances. This function connects to cluster nodes or the cluster name itself to gather essential cluster properties including quorum configuration, shared volume settings, and current operational state.

        DBAs use this when troubleshooting cluster issues, validating cluster health before SQL Server installations, or documenting high availability configurations. The function returns key cluster metadata needed for capacity planning and disaster recovery preparation.

        All Windows Server Failover Clustering (Wsfc) commands require local admin on each member node.

    .PARAMETER ComputerName
        Specifies the target Windows Server Failover Cluster to query, either by cluster name or individual node name.
        Use the cluster name when connecting to an active cluster, or specify a node name when the cluster service may be down.
        Defaults to the local computer if not specified.

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
        https://dbatools.io/Get-DbaWsfcCluster

    .EXAMPLE
        PS C:\> Get-DbaWsfcCluster -ComputerName cluster01

        Gets failover cluster information about cluster01

    .EXAMPLE
        PS C:\> Get-DbaWsfcCluster -ComputerName cluster01 | Select-Object *

        Shows all cluster values, including the ones not shown in the default view
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
            $cluster = Get-DbaCmObject -Computername $computer -Credential $Credential -Namespace root\MSCluster -ClassName MSCluster_Cluster
            $cluster | Add-Member -Force -NotePropertyName State -NotePropertyValue (Get-ResourceState $resource.State)
            $cluster | Select-DefaultView -Property Name, Fqdn, State, DrainOnShutdown, DynamicQuorumEnabled, EnableSharedVolumes, SharedVolumesRoot, QuorumPath, QuorumType, QuorumTypeValue, RequestReplyTimeout
        }
    }
}