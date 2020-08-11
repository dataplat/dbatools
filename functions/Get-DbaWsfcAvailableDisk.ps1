function Get-DbaWsfcAvailableDisk {
    <#
    .SYNOPSIS
        Gets information about the disks that can support Failover Clustering and are visible to all nodes, but are not yet part of the set of clustered disks.

    .DESCRIPTION
        Gets information about the disks that can support Failover Clustering and are visible to all nodes, but are not yet part of the set of clustered disks.

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
        https://dbatools.io/Get-DbaWsfcAvailableDisk

    .EXAMPLE
        PS C:\> Get-DbaWsfcAvailableDisk -ComputerName cluster01

        Gets available disks from the failover cluster cluster01
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
            $disk = Get-DbaCmObject -Computername $computer -Credential $Credential -Namespace root\MSCluster -ClassName MSCluster_AvailableDisk

            # I don't have an available disk, so I can't see how to clean this up: Passthru
            $disk | Add-Member -Force -NotePropertyName State -NotePropertyValue (Get-ResourceState $resource.State)
            $disk | Add-Member -Force -NotePropertyName ClusterName -NotePropertyValue $cluster.Name
            $disk | Add-Member -Force -NotePropertyName ClusterFqdn -NotePropertyValue $cluster.Fqdn -PassThru
        }
    }
}