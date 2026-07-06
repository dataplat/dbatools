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

    .OUTPUTS
        Microsoft.Management.Infrastructure.CimInstance#root/MSCluster/MSCluster_Cluster

        Returns one cluster object per target cluster specified via ComputerName parameter. Each object contains cluster-wide configuration and status information.

        Default display properties (via Select-DefaultView):
        - Name: The name of the cluster
        - Fqdn: Fully qualified domain name of the cluster
        - State: Current operational state of the cluster (added via NoteProperty)
        - DrainOnShutdown: Boolean indicating if nodes drain resources during service shutdown (uint32)
        - DynamicQuorumEnabled: Boolean indicating if dynamic quorum adjustment is enabled (uint32)
        - EnableSharedVolumes: Boolean indicating if Cluster Shared Volumes feature is enabled (uint32)
        - SharedVolumesRoot: The root directory path for Cluster Shared Volumes
        - QuorumPath: File system path where quorum files are maintained
        - QuorumType: Current quorum type as a string (Majority Node Majority, Node and Disk Majority, No Majority - Disk Only, Node Majority, or Witness)
        - QuorumTypeValue: Numeric identifier representing the quorum type (uint32)
        - RequestReplyTimeout: Timeout period in milliseconds for request-reply operations (uint32)

        Additional properties from MSCluster_Cluster WMI class (accessible via Select-Object *):
        - Caption: Short text description of the cluster
        - Description: Detailed cluster description
        - InstallDate: DateTime when the cluster was installed
        - Status: Cluster operational status string
        - AddEvictDelay: Seconds between node eviction and new node admission
        - AdminAccessPoint: Type of cluster administrative access point
        - BackupInProgress: Indicates if cluster backup is running
        - ClusterEnforcedAntiAffinity: Hard enforcement status of group anti-affinity
        - ClusterFunctionalLevel: Current cluster functional level
        - ClusterLogLevel: Cluster logging verbosity level
        - ClusterLogSize: Maximum log file size per node
        - ClusSvcHangTimeout: Heartbeat timeout before node considered hung
        - CrossSiteDelay: Heartbeat delay between sites in milliseconds
        - CrossSiteThreshold: Missed heartbeats before cross-site failure detected
        - CrossSubnetDelay: Heartbeat delay between subnets in milliseconds
        - CrossSubnetThreshold: Missed heartbeats before cross-subnet failure detected
        - CsvBalancer: Automatic CSV balancing enabled status
        - GracePeriodEnabled: Node grace period feature status
        - GracePeriodTimeout: Grace period timeout in milliseconds
        - IgnorePersistentStateOnStartup: Whether cluster brings online previously running groups
        - MaxNumberOfNodes: Maximum nodes allowed in cluster
        - NetftIPSecEnabled: IPSec security for internal cluster traffic
        - PrimaryOwnerName: Primary cluster owner name
        - PrimaryOwnerContact: Primary owner contact information
        - S2DEnabled: Storage Spaces Direct feature enablement
        - SameSubnetDelay: Heartbeat delay on same subnet in milliseconds
        - SameSubnetThreshold: Missed heartbeats on same subnet before failure detected
        - SharedVolumeCompatibleFilters: Filters compatible with direct I/O
        - SharedVolumeIncompatibleFilters: Filters that prevent direct I/O usage
        - S2DCacheBehavior, S2DCacheDeviceModel, S2DIOLatencyThreshold: Storage Spaces Direct configuration options
        - WitnessDynamicWeight: Configured witness weight for quorum calculations
        - All other properties defined in the MSCluster_Cluster WMI class

        All properties from the base WMI object are accessible using Select-Object *. Use Select-Object * to see properties not shown in the default view, as noted in the second example.

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