function Get-DbaWsfcResource {
    <#
    .SYNOPSIS
        Gets information about one or more resources in a failover cluster.

    .DESCRIPTION
        Gets information about one or more resources in a failover cluster.

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
        https://dbatools.io/Get-DbaWsfcResource

    .EXAMPLE
        PS C:\> Get-DbaWsfcResource -ComputerName cluster01

        Gets resource information from the failover cluster cluster01

    .EXAMPLE
        PS C:\> Get-DbaWsfcResource -ComputerName cluster01 | Select-Object *

        Shows all resource values, including the ones not shown in the default view
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
            $resources = Get-DbaCmObject -Computername $computer -Credential $Credential -Namespace root\MSCluster -ClassName MSCluster_Resource
            foreach ($resource in $resources) {
                $resource | Add-Member -Force -NotePropertyName State -NotePropertyValue (Get-ResourceState $resource.State)
                $resource | Add-Member -Force -NotePropertyName ClusterName -NotePropertyValue $cluster.Name
                $resource | Add-Member -Force -NotePropertyName ClusterFqdn -NotePropertyValue $cluster.Fqdn
                $resource | Select-DefaultView -Property ClusterName, ClusterFqdn, Name, State, Type, OwnerGroup, OwnerNode, PendingTimeout, PersistentState, QuorumCapable, RequiredDependencyClasses, RequiredDependencyTypes, RestartAction, RestartDelay, RestartPeriod, RestartThreshold, RetryPeriodOnFailure, SeparateMonitor
            }
        }
    }
}