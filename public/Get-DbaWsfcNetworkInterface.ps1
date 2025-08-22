function Get-DbaWsfcNetworkInterface {
    <#
    .SYNOPSIS
        Retrieves network interface configuration from Windows Server Failover Cluster nodes.

    .DESCRIPTION
        Retrieves detailed network adapter information from all nodes in a Windows Server Failover Cluster, including IP addresses, DHCP settings, and network assignments. This information is essential for troubleshooting SQL Server Failover Cluster Instance connectivity issues and verifying cluster network configuration.

        Use this command to identify network misconfigurations that could impact SQL Server availability, document cluster network topology for compliance, or diagnose connectivity problems between cluster nodes.

        All Windows Server Failover Clustering (Wsfc) commands require local admin on each member node.

    .PARAMETER ComputerName
        The target cluster name. Can be a Network or the cluster name itself.

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