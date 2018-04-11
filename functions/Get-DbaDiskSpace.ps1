#ValidationTags#CodeStyle,Messaging,FlowControl,Pipeline#
function Get-DbaDiskSpace {
    <#
        .SYNOPSIS
            Displays disk information for all local disk on a server.

        .DESCRIPTION
            Returns a custom object with server name, name of disk, label of disk, total size, free size, percent free, block size and filesystem.

            By default, this function only shows drives of types 2 and 3 (removable disk and local disk).

            Requires Windows administrator access on SQL Servers

        .PARAMETER ComputerName
            The target computer. Defaults to localhost.

        .PARAMETER Credential
            Credential object used to connect to the computer as a different user.

        .PARAMETER Unit
            This parameter has been deprecated and will be removed in 1.0.0
            All properties previously generated through this command are present at the same time, but hidden by default.

        .PARAMETER CheckForSql
            If this switch is enabled, disks will be checked for SQL Server data and log files. Windows Authentication is always used for this.

        .PARAMETER SqlCredential
            Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

        .PARAMETER ExcludeDrive
            Filter out drives - format is C:\

        .PARAMETER Detailed
            Output all properties, will be deprecated in 1.0.0 release. Use Force Instead

        .PARAMETER CheckFragmentation
            If this switch is enabled, fragmentation of all filesystems will be checked.

            This will increase the runtime of the function by seconds or even minutes per volume.

        .PARAMETER Force
            Enabling this switch will cause the command to include ALL drives.
            By default, only local disks and removable disks are shown, and hidden volumes are excluded.

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .PARAMETER WhatIf
            If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

        .PARAMETER Confirm
            If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

        .NOTES
            Tags: Storage, Disk
            Author: Chrissy LeMaire (clemaire@gmail.com) & Jakob Bindslet (jakob@bindslet.dk)

            dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
            Copyright (C) 2016 Chrissy LeMaire
            License: MIT https://opensource.org/licenses/MIT

        .LINK
            https://dbatools.io/Get-DbaDiskSpace

        .EXAMPLE
            Get-DbaDiskSpace -ComputerName srv0042

            Get disk space for the server srv0042.

        .EXAMPLE
            Get-DbaDiskSpace -ComputerName srv0042 -Unit MB

            Get disk space for the server srv0042 and displays in megabytes (MB).

        .EXAMPLE
            Get-DbaDiskSpace -ComputerName srv0042, srv0007 -Unit TB

            Get disk space from two servers and displays in terabytes (TB).

        .EXAMPLE
            Get-DbaDiskSpace -ComputerName srv0042 -Force

            Get all disk and volume space information.

        .EXAMPLE
            Get-DbaDiskSpace -ComputerName srv0042 -ExcludeDrive 'C:\'

            Get all disk and volume space information.
    #>
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline = $true)]
        [Alias('ServerInstance', 'SqlInstance', 'SqlServer')]
        [DbaInstanceParameter[]]$ComputerName = $env:COMPUTERNAME,
        [PSCredential]$Credential,
        [ValidateSet('Bytes', 'KB', 'MB', 'GB', 'TB', 'PB')]
        [string]$Unit = 'GB',
        [switch]$CheckForSql,
        [PSCredential]$SqlCredential,
        [string[]]$ExcludeDrive,
        [Alias('Detailed', 'AllDrives')]
        [switch]$CheckFragmentation,
        [switch]$Force,
        [switch][Alias('Silent')]
        $EnableException
    )

    begin {
        Test-DbaDeprecation -DeprecatedOn 1.0.0 -Parameter Detailed
        Test-DbaDeprecation -DeprecatedOn 1.0.0 -Parameter AllDrives
        Test-DbaDeprecation -DeprecatedOn 1.0.0 -Parameter Unit

        $condition = " WHERE DriveType = 2 OR DriveType = 3"
        if (Test-Bound 'Force') {
            $condition = ""
        }

        # Keep track of what computer was already processed to avoid duplicates
        $processed = New-Object System.Collections.ArrayList

        <# In order to support properly identifying if a disk/volume is involved with ANY instance on a given computer #>
        $sqlDisks = New-Object System.Collections.ArrayList
    }

    process {
        foreach ($computer in $ComputerName) {
            if ($computer.ComputerName -notin $processed) {
                $null = $processed.Add($computer.ComputerName)
                Write-Message -Level VeryVerbose -Message "Connecting to $computer." -Target $computer.ComputerName
            }
            else {
                continue
            }

            try {
                $disks = Get-DbaCmObject -ComputerName $computer.ComputerName -Query "SELECT * FROM Win32_Volume$condition" -Credential $Credential -Namespace root\CIMv2 -ErrorAction Stop -WarningAction SilentlyContinue -EnableException
            }
            catch {
                Stop-Function -Message "Failed to connect to $computer." -EnableException $EnableException -ErrorRecord $_ -Target $computer.ComputerName -Continue
            }

            foreach ($disk in $disks) {
                if ($disk.Name -in $ExcludeDrive) {
                    continue
                }
                if ($disk.Name.StartsWith('\\') -and (-not $Force)) {
                    Write-Message -Level Verbose -Message "Skipping disk: $($disk.Name)" -Target $computer.ComputerName
                    continue
                }

                Write-Message -Level Verbose -Message "Processing disk: $($disk.Name)" -Target $computer.ComputerName

                $info = New-Object Sqlcollaborative.Dbatools.Computer.DiskSpace
                $info.ComputerName = $computer.ComputerName
                $info.Name = $disk.Name
                $info.Label = $disk.Label
                $info.Capacity = $disk.Capacity
                $info.Free = $disk.Freespace
                $info.BlockSize = $disk.BlockSize
                $info.FileSystem = $disk.FileSystem
                $info.Type = $disk.DriveType

                if ($CheckForSql) {
                    $driveLetter = $disk.DriveLetter.TrimEnd(":")
                    try {
                        $sqlServices = Get-DbaSqlService -ComputerName $computer -Type Engine
                    }
                    catch {
                        Write-Message -Level Warning -Message "Failed to connect to $computer to gather SQL Server instances, will not be reporting SQL Information." -ErrorRecord $_ -OverrideExceptionMessage -Target $computer.ComputerName
                    }

                    Write-Message -Level Verbose -Message "Instances found on $($computer): $($sqlServices.InstanceName.Count)"
                    if ($sqlServices.InstanceName.Count -gt 0) {
                        foreach ($sqlService in $sqlServices) {
                            if ($sqlService.InstanceName -eq "MSSQLSERVER") {
                                $instanceName = $sqlService.ComputerName
                            }
                            else {
                                $instanceName = "$($sqlService.ComputerName)\$($sqlService.InstanceName)"
                            }
                            Write-Message -Level VeryVerbose -Message "Processing instance $($instanceName)"
                            try {
                                $server = Connect-SqlInstance -SqlInstance $instanceName -SqlCredential $SqlCredential
                                if ($server.Version -lt 9) {
                                    $sql = "SELECT DISTINCT LEFT(filename,1) AS SqlDisk FROM sysaltfiles"
                                }
                                else {
                                    $sql = "SELECT DISTINCT LEFT(physical_name,1) AS SqlDisk FROM sys.master_files"
                                }
                                $results = $server.Query($sql)
                                if ($results.SqlDisk.Count -gt 0) {
                                    foreach ($sqlDisk in $results.SqlDisk) {
                                        $null = $sqlDisks.Add($sqlDisk)
                                    }
                                }
                            }
                            catch {
                                Write-Message -Level Warning -Message "Failed to connect to $instanceName on $computer. SQL information may not be accurate or services have been stopped." -ErrorRecord $_ -OverrideExceptionMessage -Target $computer.ComputerName
                            }
                        }
                    }
                    $info.IsSqlDisk = ($driveLetter -in $sqlDisks)
                    $info
                }
                $info
            }
        }
    }
}