function Get-DbaWsfcSharedVolume {
    <#
    .SYNOPSIS
        Gets information about Cluster Shared Volumes in a failover cluster.

    .DESCRIPTION
        Gets information about Cluster Shared Volumes in a failover cluster.

        All Windows Server Failover Clustering (Wsfc) commands require local admin on each member node.

    .PARAMETER ComputerName
        The target cluster name. Can be a node or the cluster name itself.

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
        https://dbatools.io/Get-DbaWsfcSharedVolume

    .EXAMPLE
        PS C:\> Get-DbaWsfcSharedVolume -ComputerName cluster01

        Gets shared volume (CSV) information from the failover cluster cluster01
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
            $volume = Get-DbaCmObject -Computername $computer -Credential $Credential -Namespace root\MSCluster -ClassName ClusterSharedVolume
            # I don't have a shared volume, so I can't see how to clean this up: Passthru
            $volume | Add-Member -Force -NotePropertyName ClusterName -NotePropertyValue $cluster.Name
            $volume | Add-Member -Force -NotePropertyName ClusterFqdn -NotePropertyValue $cluster.Fqdn
            $volume | Add-Member -Force -NotePropertyName State -NotePropertyValue (Get-ResourceState $resource.State) -PassThru
        }
    }
}