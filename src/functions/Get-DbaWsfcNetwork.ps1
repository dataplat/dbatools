function Get-DbaWsfcNetwork {
    <#
    .SYNOPSIS
        Gets information about one or more networks in a failover cluster.

    .DESCRIPTION
        Gets information about one or more networks in a failover cluster.

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