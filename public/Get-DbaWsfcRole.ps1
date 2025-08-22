function Get-DbaWsfcRole {
    <#
    .SYNOPSIS
        Retrieves Windows Server Failover Cluster role status and ownership information for SQL Server monitoring

    .DESCRIPTION
        Retrieves detailed information about Windows Server Failover Cluster roles (resource groups), including their current state, and which node currently owns them. This function helps DBAs monitor and troubleshoot SQL Server Failover Cluster Instances and Availability Groups by providing visibility into the underlying cluster roles that control SQL Server services and resources.

        Use this command when you need to verify role health during maintenance windows, troubleshoot failover issues, or confirm which node is currently hosting specific SQL Server resources. The function translates numeric state codes into readable status values (Online, Offline, Failed, Pending) so you can quickly identify problematic roles.

        All Windows Server Failover Clustering (Wsfc) commands require local admin on each member node.

    .PARAMETER ComputerName
        The target cluster name. Can be a Role or the cluster name itself.

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