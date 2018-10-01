#ValidationTags#Messaging,FlowControl,Pipeline,CodeStyle#
function Get-DbaWsfcDisk {
<#
    .SYNOPSIS
        Gets information about the clustered disks on one or more failover clusters in a given domain.

    .DESCRIPTION
        Gets information about the clustered disks on one or more failover clusters in a given domain.
        
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
        https://dbatools.io/Get-DbaWsfcDisk

    .EXAMPLE
        Get-DbaWsfcDisk -ComputerName cluster01
    
        Gets disk information from the failover cluster cluster01
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
            try {
                # unsure how to do this with cim
                if ($Credential) {
                    $resources = Get-WmiObject -ComputerName $computer -Credential $Credential -Namespace root\MSCluster -Class MSCluster_Resource -Authentication PacketPrivacy -ErrorAction Stop
                }
                else {
                    $resources = Get-WmiObject -ComputerName $computer -Namespace root\MSCluster -Class MSCluster_Resource -Authentication PacketPrivacy -ErrorAction Stop
                }
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $computer -Continue
            }
            
            <#
                $disks = Get-CimInstance -Namespace Root\MSCluster -ClassName MSCluster_Resource -ComputerName $Cluster | Where-Object Type -eq 'Physical Disk'
                $disks | Get-CimAssociatedInstance -ResultClassName MSCluster_DiskPartition
            #>
            
            foreach ($res in $resources) {
                $resourcegroup = $res.GetRelated() | Where-Object Type -eq 'Physical Disk'
                foreach ($resource in $resourcegroup) {
                    $disks = $resource.GetRelated("MSCluster_Disk")
                    
                    foreach ($disk in $disks) {
                        $diskpart = $disk.GetRelated("MSCluster_DiskPartition")
                        [pscustomobject]@{
                            ComputerName  = $computer
                            ResourceGroup = $res.OwnerGroup
                            Disk          = $resource.Name
                            State         = (Get-ResourceState $resource.State)
                            FileSystem    = $diskpart.FileSystem
                            Path          = $diskpart.Path
                            Label         = $diskpart.VolumeLabel
                            Size          = [dbasize]($diskpart.TotalSize * 1MB)
                            Free          = [dbasize]($diskpart.FreeSpace * 1MB)
                            MountPoints   = $diskpart.MountPoints
                            SerialNumber  = $diskpart.SerialNumber
                        }
                    }
                }
            }
        }
    }
}