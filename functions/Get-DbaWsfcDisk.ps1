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
                $disks = Get-CimInstance -Namespace Root\MSCluster -ClassName MSCluster_Resource -ComputerName $Cluster | ?{$_.Type -eq 'Physical Disk'}
                $disks | Get-CimAssociatedInstance -ResultClassName MSCluster_DiskPartition
            #>
            
            foreach ($res in $resources) {
                $resourcegroup = $res.GetRelated() | Where-Object Type -eq 'Physical Disk'
                foreach ($resource in $resourcegroup) {
                    $disks = $resource.GetRelated("MSCluster_Disk")
                    foreach ($disk in $disks) {
                        $diskpart = $disk.GetRelated("MSCluster_DiskPartition")
                        $diskpart
                        return
                        $clusterdisk = $resource.Name
                        $diskstate = $resource.State
                        $diskdrive = $diskpart.Path
                        $disklabel = $diskpart.VolumeLabel
                        $disksize = $diskpart.TotalSize
                        $diskfree = $diskpart.FreeSpace
                        
                        switch ($diskstate) {
                            -1 { $diskstate = "Unknown" }
                            0   { $diskstate = "Inherited" }
                            1   { $diskstate = "Initializing" }
                            2   { $diskstate = "Online" }
                            3   { $diskstate = "Offline" }
                            4   { $diskstate = "Failed" }
                            128 { $diskstate = "Pending" }
                            129 { $diskstate = "Online Pending" }
                            130 { $diskstate = "Offline Pending" }
                        }
                        
                        <#
                        Caption                :
                        Characteristics        :
                        Description            :
                        FileSystem             : NTFS
                        FileSystemFlags        : 65470703
                        Flags                  : 29
                        FreeSpace              : 94538
                        InstallDate            :
                        MaximumComponentLength : 255
                        MountPoints            : { M: }
                        Name                   :
                        PartitionNumber        : 2
                        Path                   : M:
                        SerialNumber           : 1045740649
                        Status                 :
                        TotalSize              : 102269
                        VolumeGuid             : cb354fe3-d679-4e84-8cc4-f24cc2d3630f
                        VolumeLabel            : Data
                        PSComputerName         : SQLB
                        #>
                        [pscustomobject]@{
                            ComputerName = $computer
                            ResourceGroup = $res.OwnerGroup
                            Disk          = $clusterdisk
                            State         = $diskstate
                            Drive         = $diskdrive
                            Label         = $disklabel
                            Size          = $disksize
                            Free          = $diskfree
                        }
                    }
                }
            }
        }
    }
}