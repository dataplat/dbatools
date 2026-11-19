function Get-DbaWsfcResourceType {
    <#
    .SYNOPSIS
        Retrieves available resource types from Windows Server Failover Cluster for SQL Server FCI configuration.

    .DESCRIPTION
        Retrieves detailed information about all resource types available in a Windows Server Failover Cluster. Resource types define what kinds of cluster resources can be created, including SQL Server instances, network names, IP addresses, and shared storage. This information is essential when configuring or troubleshooting SQL Server Failover Cluster Instances (FCI), as it shows which resource types are installed and their dependencies.

        Returns resource type properties including display names, DLL locations, and required dependency relationships. This helps DBAs understand the available building blocks for creating clustered SQL Server resources and diagnose configuration issues.

        All Windows Server Failover Clustering (Wsfc) commands require local admin on each member node.

    .PARAMETER ComputerName
        Specifies the target Windows Server Failover Cluster by providing either a cluster node name or the cluster name itself.
        Use this when connecting to a specific cluster to retrieve its available resource types for SQL Server FCI planning or troubleshooting.
        Defaults to the local computer name if not specified.

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
        Microsoft.Management.Infrastructure.CimInstance#root/MSCluster/MSCluster_ResourceType

        Returns one resource type object per resource type available in the Windows Server Failover Cluster. Resource types represent the available building blocks for creating cluster resources such as SQL Server instances, network names, and shared storage.

        Default display properties (via Select-DefaultView):
        - ClusterName: Name of the cluster containing this resource type
        - ClusterFqdn: Fully qualified domain name of the cluster
        - Name: Name of the resource type (key property)
        - DisplayName: Displayed name for the resource type shown in user interfaces
        - DllName: File name of the dynamic-link library that implements the resource type
        - RequiredDependencyTypes: Array of resource type names that resources of this type must depend on (Windows Server 2012+)

        Additional properties available (from WMI MSCluster_ResourceType object):
        - Caption: Short textual description of the resource type
        - Description: Detailed description of the resource type
        - Characteristics: Bit flags defining resource type characteristics
        - Flags: Resource type flags
        - ResourceClass: Classification of resource type (Storage, Network, User, Unknown)
        - QuorumCapable: Boolean indicating if resource can be selected as quorum resource
        - IsAlivePollInterval: Recommended poll interval in milliseconds for liveness checks
        - LooksAlivePollInterval: Recommended poll interval in milliseconds for operational status checks
        - DeadlockTimeout: Milliseconds before declaring a deadlock in resource calls
        - PendingTimeout: Milliseconds before forcibly terminating unresponsive resources
        - AdminExtensions: Class identifiers for Cluster Administrator extension DLLs
        - Status: Current operational status of the resource type

        All properties from the WMI MSCluster_ResourceType object are accessible using Select-Object *.

    .LINK
        https://dbatools.io/Get-DbaWsfcResourceType

    .EXAMPLE
        PS C:\> Get-DbaWsfcResourceType -ComputerName cluster01

        Gets resource type information from the failover cluster cluster01
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
            $resource = Get-DbaCmObject -Computername $computer -Credential $Credential -Namespace root\MSCluster -ClassName MSCluster_ResourceType
            $resource | Add-Member -Force -NotePropertyName ClusterName -NotePropertyValue $cluster.Name
            $resource | Add-Member -Force -NotePropertyName ClusterFqdn -NotePropertyValue $cluster.Fqdn
            $resource | Select-DefaultView -Property ClusterName, ClusterFqdn, Name, DisplayName, DllName, RequiredDependencyTypes
        }
    }
}