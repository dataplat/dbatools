function Get-DbaWsfcSharedVolume {
    <#
    .SYNOPSIS
        Retrieves Cluster Shared Volume configuration and status from Windows Server Failover Clusters hosting SQL Server instances.

    .DESCRIPTION
        Retrieves detailed configuration and operational information about Cluster Shared Volumes (CSVs) from Windows Server Failover Clusters. CSVs provide the shared storage foundation for SQL Server Failover Cluster Instances (FCIs) and other clustered applications, making this function essential for monitoring storage health and troubleshooting cluster storage issues.

        DBAs use this when validating CSV health before SQL Server installations, investigating storage-related performance problems in clustered environments, or documenting shared storage configurations for disaster recovery planning. The function returns CSV properties along with cluster context including state information and fully qualified cluster names.

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