function Get-DbaWsfcRole {
    <#
    .SYNOPSIS
        Retrieves Windows Server Failover Cluster role status and ownership information for SQL Server monitoring

    .DESCRIPTION
        Retrieves detailed information about Windows Server Failover Cluster roles (resource groups), including their current state, and which node currently owns them. This function helps DBAs monitor and troubleshoot SQL Server Failover Cluster Instances and Availability Groups by providing visibility into the underlying cluster roles that control SQL Server services and resources.

        Use this command when you need to verify role health during maintenance windows, troubleshoot failover issues, or confirm which node is currently hosting specific SQL Server resources. The function translates numeric state codes into readable status values (Online, Offline, Failed, Pending) so you can quickly identify problematic roles.

        All Windows Server Failover Clustering (Wsfc) commands require local admin on each member node.

    .PARAMETER ComputerName
        Specifies the cluster node name or cluster name to connect to for retrieving role information. Accepts multiple values for querying multiple clusters.
        Use this when you need to check role status on remote clusters or when working with multiple cluster environments.

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
        Microsoft.Management.Infrastructure.CimInstance#root/MSCluster/MSCluster_ResourceGroup

        Returns one resource group (role) object per cluster role found in the Windows Server Failover Cluster. Resource groups bundle together related cluster resources and manage their failover behavior as a single unit.

        Default display properties (via Select-DefaultView):
        - ClusterName: Name of the cluster containing this role
        - ClusterFqdn: Fully qualified domain name of the cluster
        - Name: Name of the resource group (key property), typically the cluster role name (e.g., SQL Server instance name)
        - OwnerNode: Name of the node currently hosting this resource group
        - State: Current state of the resource group translated to readable format (Online, Offline, Failed, Partial Online, Pending, or Unknown)

        Additional properties available (from WMI MSCluster_ResourceGroup object):
        - Caption: Short textual description of the resource group
        - Description: Detailed comments about the resource group
        - Id: Network identifier for the group
        - Status: Current status string (OK, Error, Degraded, Unknown, etc.)
        - InstallDate: DateTime when the group was created
        - Characteristics: Bit flags defining group characteristics
        - Flags: Flags set for the group
        - DefaultOwner: Node number where group was last activated or moved (node preferences)
        - AutoFailbackType: Whether automatic failback to preferred owner is enabled (0=Prevent, 1=Allow)
        - FailbackWindowStart: Earliest hour (local cluster time) group can move back to preferred node (-1 to 23)
        - FailbackWindowEnd: Latest hour group can move back to preferred node (-1 to 23)
        - FailoverPeriod: Hours during which failover threshold applies (1-1193 hours)
        - FailoverThreshold: Maximum number of failover attempts allowed within FailoverPeriod
        - PersistentState: Whether group stays offline or comes online when Cluster service starts
        - Priority: Priority value for the resource group (0-4999)
        - AntiAffinityClassNames: Groups that should not be hosted on the same cluster node
        - GroupType: Type of resource group (cluster, SQL Server instance, file server, virtual machine, etc.)
        - IsCore: Boolean indicating if group is essential cluster group that cannot be deleted
        - CCFEpoch: Current CCF (Cluster Configuration Fence) of the resource group (Windows Server 2016+)
        - ResiliencyPeriod: Resiliency period in seconds (Windows Server 2016+)

        All properties from the WMI MSCluster_ResourceGroup object are accessible using Select-Object *. Use Select-Object * to view all available properties including dynamically populated values based on current cluster state.

    .LINK
        https://dbatools.io/Get-DbaWsfcRole

    .EXAMPLE
        PS C:\> Get-DbaWsfcRole -ComputerName cluster01

        Gets role information from the failover cluster cluster01

    .EXAMPLE
        PS C:\> Get-DbaWsfcRole -ComputerName cluster01 | Select-Object *

        Shows all role values, including the ones not shown in the default view
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
            $role = Get-DbaCmObject -Computername $computer -Credential $Credential -Namespace root\MSCluster -ClassName MSCluster_ResourceGroup
            $role | Add-Member -Force -NotePropertyName State -NotePropertyValue (Get-ResourceState $resource.State)
            $role | Add-Member -Force -NotePropertyName ClusterName -NotePropertyValue $cluster.Name
            $role | Add-Member -Force -NotePropertyName ClusterFqdn -NotePropertyValue $cluster.Fqdn
            $role | Select-DefaultView -Property ClusterName, ClusterFqdn, Name, OwnerNode, State
        }
    }
}