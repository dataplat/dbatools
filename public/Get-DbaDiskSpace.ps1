function Get-DbaDiskSpace {
    <#
    .SYNOPSIS
        Retrieves disk space and filesystem details from SQL Server host systems for capacity monitoring and performance analysis.

    .DESCRIPTION
        Queries Windows disk volumes on SQL Server systems using WMI to gather critical storage information for database administration. Returns comprehensive disk details including capacity, free space, filesystem type, and optional fragmentation analysis.

        Essential for SQL Server capacity planning, this function helps DBAs monitor disk space before growth limits impact database operations. Use it to verify adequate space for backup operations, identify performance bottlenecks from fragmented volumes hosting data or log files, and maintain compliance documentation for storage utilization.

        By default, only local disks and removable disks are shown (DriveType 2 and 3), which covers most SQL Server storage scenarios. Hidden system volumes are excluded unless the Force parameter is used.

        Requires Windows administrator access on target SQL Server systems.

    .PARAMETER ComputerName
        Specifies the SQL Server host systems to query for disk space information. Accepts multiple computer names for bulk monitoring.
        Use this to check storage capacity across your SQL Server environment before database growth or backup operations impact available space.

    .PARAMETER Credential
        Credential object used to connect to the computer as a different user.

    .PARAMETER Unit
        This parameter has been deprecated and will be removed in 1.0.0.
        All size properties (Bytes, KB, MB, GB, TB, PB) are now available simultaneously in the output object but hidden by default for cleaner display.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER ExcludeDrive
        Specifies drive letters to exclude from the disk space report, using the format 'C:\' or 'D:\'.
        Use this to skip system drives or non-SQL storage when focusing on database file locations, or to exclude network drives that may cause timeouts.

    .PARAMETER CheckFragmentation
        Enables filesystem fragmentation analysis for all volumes, which can impact SQL Server I/O performance when database or log files are stored on fragmented drives.
        This significantly increases runtime (seconds to minutes per volume) but provides critical data for troubleshooting slow database operations or planning defragmentation maintenance.

    .PARAMETER Force
        Includes all drive types and hidden volumes in the results, not just local and removable disks (DriveType 2 and 3).
        Use this when you need complete storage visibility including network drives, CD/DVD drives, or system volumes that might host SQL Server components like backup locations or tempdb files.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .NOTES
        Tags: Storage, Disk, Space, OS
        Author: Chrissy LeMaire (@cl), netnerds.net | Jakob Bindslet

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaDiskSpace

    .EXAMPLE
        PS C:\> Get-DbaDiskSpace -ComputerName srv0042

        Get disk space for the server srv0042.

    .EXAMPLE
        PS C:\> Get-DbaDiskSpace -ComputerName srv0042 -Unit MB

        Get disk space for the server srv0042 and displays in megabytes (MB).

    .EXAMPLE
        PS C:\> Get-DbaDiskSpace -ComputerName srv0042, srv0007 -Unit TB

        Get disk space from two servers and displays in terabytes (TB).

    .EXAMPLE
        PS C:\> Get-DbaDiskSpace -ComputerName srv0042 -Force

        Get all disk and volume space information.

    .EXAMPLE
        PS C:\> Get-DbaDiskSpace -ComputerName srv0042 -ExcludeDrive 'C:\'

        Get all disk and volume space information.
    #>
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline)]
        [DbaInstanceParameter[]]$ComputerName = $env:COMPUTERNAME,
        [PSCredential]$Credential,
        [ValidateSet('Bytes', 'KB', 'MB', 'GB', 'TB', 'PB')]
        [string]$Unit = 'GB',
        [PSCredential]$SqlCredential,
        [string[]]$ExcludeDrive,
        [switch]$CheckFragmentation,
        [switch]$Force,
        [switch]$EnableException
    )

    begin {

        $condition = " WHERE DriveType = 2 OR DriveType = 3"
        if (Test-Bound 'Force') {
            $condition = ""
        }

        # Keep track of what computer was already processed to avoid duplicates
        $processed = New-Object System.Collections.ArrayList

    }

    process {
        foreach ($computer in $ComputerName) {
            if ($computer.ComputerName -notin $processed) {
                $null = $processed.Add($computer.ComputerName)
            } else {
                continue
            }

            try {
                $disks = Get-DbaCmObject -ComputerName $computer.ComputerName -Query "SELECT * FROM Win32_Volume$condition" -Credential $Credential -Namespace root\CIMv2 -ErrorAction Stop -WarningAction SilentlyContinue -EnableException
            } catch {
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

                $info = New-Object Dataplat.Dbatools.Computer.DiskSpace
                $info.ComputerName = $computer.ComputerName
                $info.Name = $disk.Name
                $info.Label = $disk.Label
                $info.Capacity = $disk.Capacity
                $info.Free = $disk.Freespace
                $info.BlockSize = $disk.BlockSize
                $info.FileSystem = $disk.FileSystem
                $info.Type = $disk.DriveType

                $info
            }
        }
    }
}