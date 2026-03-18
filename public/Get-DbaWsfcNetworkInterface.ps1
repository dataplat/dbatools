function Get-DbaWsfcNetworkInterface {
    <#
    .SYNOPSIS
        Retrieves network interface configuration from Windows Server Failover Cluster nodes.

    .DESCRIPTION
        Retrieves detailed network adapter information from all nodes in a Windows Server Failover Cluster, including IP addresses, DHCP settings, and network assignments. This information is essential for troubleshooting SQL Server Failover Cluster Instance connectivity issues and verifying cluster network configuration.

        Use this command to identify network misconfigurations that could impact SQL Server availability, document cluster network topology for compliance, or diagnose connectivity problems between cluster nodes.

        All Windows Server Failover Clustering (Wsfc) commands require local admin on each member node.

    .PARAMETER ComputerName
        Specifies the Windows Server Failover Cluster name or any cluster node name to query for network interface information.
        Use this when troubleshooting SQL Server FCI connectivity issues or documenting cluster network topology.
        Accepts cluster names, node names, or IP addresses of cluster resources.

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
        System.Management.ManagementObject

        Returns one network interface object per adapter found on cluster nodes queried. Each object represents a network interface configuration with IP address and DHCP settings.

        Default display properties (via Select-DefaultView):
        - ClusterName: The name of the Windows Server Failover Cluster
        - ClusterFqdn: The fully qualified domain name of the cluster
        - Name: The name of the network interface
        - Network: The name or identifier of the network this interface belongs to
        - Node: The name of the cluster node this interface is assigned to
        - Adapter: The network adapter identifier or friendly name
        - Address: The IP address assigned to this interface
        - DhcpEnabled: Boolean indicating if DHCP is enabled for this interface
        - IPv4Addresses: String array of IPv4 addresses configured on this interface
        - IPv6Addresses: String array of IPv6 addresses configured on this interface

        Additional properties available via Select-Object *:
        All properties from the MSCluster_NetworkInterface WMI class, including network role, state, and adapter-level details.

    .LINK
        https://dbatools.io/Get-DbaWsfcNetworkInterface

    .EXAMPLE
        PS C:\> Get-DbaWsfcNetworkInterface -ComputerName cluster01

        Gets network interface information from the failover cluster cluster01

    .EXAMPLE
        PS C:\> Get-DbaWsfcNetworkInterface -ComputerName cluster01 | Select-Object *

        Shows all network interface  values, including the ones not shown in the default view
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
            $network = Get-DbaCmObject -Computername $computer -Credential $Credential -Namespace root\MSCluster -ClassName MSCluster_NetworkInterface
            $network | Add-Member -Force -NotePropertyName ClusterName -NotePropertyValue $cluster.Name
            $network | Add-Member -Force -NotePropertyName ClusterFqdn -NotePropertyValue $cluster.Fqdn
            $network | Select-DefaultView -Property ClusterName, ClusterFqdn, Name, Network, Node, Adapter, Address, DhcpEnabled, IPv4Addresses, IPv6Addresses, IPv6Addresses
        }
    }
}