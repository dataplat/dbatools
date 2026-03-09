function Get-DbaWsfcResource {
    <#
    .SYNOPSIS
        Retrieves detailed information about cluster resources in a Windows Server Failover Cluster

    .DESCRIPTION
        Retrieves comprehensive information about cluster resources including SQL Server instances, disks, network names, and other services managed by the failover cluster. Shows current state, ownership, dependencies, restart policies, and timeout settings for each resource, which is essential for troubleshooting cluster issues and monitoring SQL Server FCI health.

        Use this when diagnosing cluster resource failures, planning maintenance windows, or investigating why SQL Server services aren't failing over properly. The state information helps identify stuck resources, while ownership details show which node currently hosts each resource.

        All Windows Server Failover Clustering (Wsfc) commands require local admin on each member node.

    .PARAMETER ComputerName
        Specifies the target cluster to query for resource information. Can be any cluster node name or the cluster name itself.
        Use this when managing multiple clusters or when connecting from outside the cluster to gather resource status and configuration details.

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
        https://dbatools.io/Get-DbaWsfcResource

    .OUTPUTS
        MSCluster_Resource (with added NoteProperties)

        Returns one resource object per cluster resource found in the specified Windows Server Failover Cluster. Each resource represents a clustered component such as a physical disk, IP address, SQL Server instance, or network name.

        Default display properties (via Select-DefaultView):
        - ClusterName: The name of the Windows Server Failover Cluster
        - ClusterFqdn: The fully qualified domain name of the cluster
        - Name: The resource name
        - State: Current operational status of the resource (Online, Offline, Failed, Initializing, Pending, Unknown, etc.)
        - Type: The resource type (e.g., "Physical Disk", "IP Address", "Network Name")
        - OwnerGroup: The resource group this resource belongs to
        - OwnerNode: The cluster node currently hosting this resource
        - PendingTimeout: Timeout in milliseconds for bringing resource online/offline (typically 180000 ms / 3 minutes)
        - PersistentState: Boolean indicating whether resource should be online when Cluster Service starts
        - QuorumCapable: Boolean indicating if the resource can be selected as quorum resource
        - RequiredDependencyClasses: Array of resource classes this resource depends on
        - RequiredDependencyTypes: Array of resource types that are required dependencies
        - RestartAction: Action on failure - Do Not Restart (0), Restart Without Failover (1), Restart With Failover (2)
        - RestartDelay: Time delay in milliseconds before restart attempt
        - RestartPeriod: Interval in milliseconds for restart attempt tracking
        - RestartThreshold: Maximum number of restart attempts within RestartPeriod
        - RetryPeriodOnFailure: Interval in milliseconds before retrying a failed resource
        - SeparateMonitor: Boolean indicating if resource requires isolated Resource Monitor process

        Additional properties available (WMI MSCluster_Resource object):
        - Id: Unique identifier for the resource
        - CoreResource: Boolean indicating if resource is essential to cluster
        - IsAlivePollInterval: Polling interval in milliseconds for operational checks
        - LooksAlivePollInterval: Polling interval in milliseconds for appearance checks
        - DeadlockTimeout: Timeout in milliseconds for deadlock detection
        - Status: Status message string (e.g., "OK", "Error", "Degraded")
        - ResourceSpecificStatus: Resource-specific status information
        - IsClusterSharedVolume: Boolean indicating if resource is a cluster shared volume
        - MonitorProcessId: Process ID of resource monitor managing this resource
        - Characteristics: Resource characteristics flags
        - Flags: Resource configuration flags
        - InstallDate: DateTime when resource was installed
        - Caption: Short description of the resource
        - CryptoCheckpoints: Array of encrypted checkpoints for resource backup/restore
        - RegistryCheckpoints: Array of registry checkpoints for resource backup/restore
        - LocalQuorumCapable: Boolean indicating if usable as quorum in local quorum clusters
        - ResourceClass: Classification (Storage, Network, User)

        All properties from the WMI MSCluster_Resource class are accessible using Select-Object *.

    .EXAMPLE
        PS C:\> Get-DbaWsfcResource -ComputerName cluster01

        Gets resource information from the failover cluster cluster01

    .EXAMPLE
        PS C:\> Get-DbaWsfcResource -ComputerName cluster01 | Select-Object *

        Shows all resource values, including the ones not shown in the default view
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
            $resources = Get-DbaCmObject -Computername $computer -Credential $Credential -Namespace root\MSCluster -ClassName MSCluster_Resource
            foreach ($resource in $resources) {
                $resource | Add-Member -Force -NotePropertyName State -NotePropertyValue (Get-ResourceState $resource.State)
                $resource | Add-Member -Force -NotePropertyName ClusterName -NotePropertyValue $cluster.Name
                $resource | Add-Member -Force -NotePropertyName ClusterFqdn -NotePropertyValue $cluster.Fqdn
                $resource | Select-DefaultView -Property ClusterName, ClusterFqdn, Name, State, Type, OwnerGroup, OwnerNode, PendingTimeout, PersistentState, QuorumCapable, RequiredDependencyClasses, RequiredDependencyTypes, RestartAction, RestartDelay, RestartPeriod, RestartThreshold, RetryPeriodOnFailure, SeparateMonitor
            }
        }
    }
}