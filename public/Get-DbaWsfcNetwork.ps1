function Get-DbaWsfcNetwork {
    <#
    .SYNOPSIS
        Retrieves network configuration details from Windows Server Failover Clustering for SQL Server high availability troubleshooting.

    .DESCRIPTION
        Retrieves detailed network information from Windows Server Failover Cluster nodes, including IP addresses, subnet masks, and network roles. This information is essential for diagnosing connectivity issues with SQL Server Failover Cluster Instances (FCIs) and Availability Groups, especially when troubleshooting network-related failures or validating cluster network configuration. The function returns comprehensive network details like IPv4/IPv6 addresses, prefix lengths, and quorum settings that help DBAs understand how cluster networks are configured and identify potential communication problems between nodes.

        All Windows Server Failover Clustering (Wsfc) commands require local admin on each member node.

    .PARAMETER ComputerName
        Specifies the Windows Server Failover Cluster name or any cluster node name to retrieve network configuration from.
        Use this to target a specific cluster when troubleshooting network connectivity issues with SQL Server FCIs or Availability Groups.
        Accepts multiple cluster names for bulk network configuration analysis.

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
        https://dbatools.io/Get-DbaWsfcNetwork

    .EXAMPLE
        PS C:\> Get-DbaWsfcNetwork -ComputerName cluster01

        Gets network information from the failover cluster cluster01
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

            $network = Get-DbaCmObject -Computername $computer -Credential $Credential -Namespace root\MSCluster -ClassName MSCluster_Network
            $network | Add-Member -Force -NotePropertyName ClusterName -NotePropertyValue $cluster.Name
            $network | Add-Member -Force -NotePropertyName ClusterFqdn -NotePropertyValue $cluster.Fqdn

            $network | Select-DefaultView -Property ClusterName, ClusterFqdn, Name, Address, AddressMask, IPv4Addresses, IPv4PrefixLengths, IPv6Addresses, IPv6PrefixLengths, QuorumType, QuorumTypeValue, RequestReplyTimeout, Role
        }
    }
}