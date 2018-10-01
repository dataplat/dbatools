#ValidationTags#Messaging,FlowControl,Pipeline,CodeStyle#
function Get-DbaWsfcCluster {
<#
    .SYNOPSIS
        Gets information about one or more failover clusters in a given domain.
    
    .DESCRIPTION
        Gets information about one or more failover clusters in a given domain.

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
        Tags: Cluster, WSFC, FCI, HA
        Author: Chrissy LeMaire (@cl), netnerds.net
        Website: https://dbatools.io
        Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaWsfcCluster
    
    .EXAMPLE
        Get-DbaWsfcCluster -ComputerName cluster01
    
        Gets failover cluster information about cluster01
    
    .EXAMPLE
        Get-DbaWsfcCluster -ComputerName cluster01 | Select *
    
        Shows all cluster values, including those not included in the default view
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
            Get-DbaCmObject -Computername $computer -Credential $Credential -Namespace root\MSCluster -ClassName MSCluster_Cluster |
            Select-DefaultView -Property Name, Fqdn, Caption, Description, InstallDate, Status, DrainOnShutdown, DynamicQuorumEnabled, EnableSharedVolumes, SharedVolumesRoot, QuorumPath, QuorumType, QuorumTypeValue, RequestReplyTimeout
        }
    }
}