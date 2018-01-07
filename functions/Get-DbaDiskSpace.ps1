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

        .PARAMETER Unit
            This parameter has been deprecated and will be removed in 1.0.0
            All properties previously generated through this command are present at the same time, but hidden by default.

        .PARAMETER CheckForSql
            If this switch is enabled, disks will be checked for SQL Server data and log files. Windows Authentication is always used for this.

        .PARAMETER SqlCredential
            SqlCredential object to connect as. If not specified, current Windows login will be used.
            Only relevant in combination with the -CheckForSql parameter.

        .PARAMETER Credential
            The credentials to use to connect via CIM/WMI/PowerShell remoting

        .PARAMETER ExcludeDrive
            Filter out drives - format is C:\

        .PARAMETER Detailed
            Output all properties, will be deprecated in 1.0.0 release. Use Force Instead

        .PARAMETER Force
            Enabling this switch will cause the command to include ALL drives.
            By default, only local disks and removable disks are shown, and hidden volumes are excluded.

        .PARAMETER CheckFragmentation
            If this switch is enabled, fragmentation of all filesystems will be checked.

            This will increase the runtime of the function by seconds or even minutes per volume.

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .PARAMETER WhatIf
            If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

        .PARAMETER Confirm
            If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

        .EXAMPLE
            Get-DbaDiskSpace -ComputerName srv0042 | Format-Table -AutoSize

            Get disk space for the server srv0042.

            Server  Name Label  SizeInGB FreeInGB PercentFree BlockSize
            ------  ---- -----  -------- -------- ----------- ---------
            srv0042 C:\  System   126,45   114,12       90,25      4096
            srv0042 E:\  Data1     97,62    96,33       98,67      4096
            srv0042 F:\  DATA2      29,2     29,2         100     16384

        .EXAMPLE
            Get-DbaDiskSpace -ComputerName srv0042 -Unit MB | Format-Table -AutoSize

            Get disk space for the server srv0042 and displays in megabytes (MB).

            Server  Name Label  SizeInMB  FreeInMB PercentFree BlockSize
            ------  ---- -----  --------  -------- ----------- ---------
            srv0042 C:\  System   129481 116856,11       90,25      4096
            srv0042 E:\  Data1     99968  98637,56       98,67      4096
            srv0042 F:\  DATA2     29901  29900,92         100     16384

        .EXAMPLE
            Get-DbaDiskSpace -ComputerName srv0042, srv0007 -Unit TB | Format-Table -AutoSize

            Get disk space from two servers and displays in terabytes (TB).

            Server  Name Label  SizeInTB FreeInTB PercentFree BlockSize
            ------  ---- -----  -------- -------- ----------- ---------
            srv0042 C:\  System     0,12     0,11       90,25      4096
            srv0042 E:\  Data1       0,1     0,09       98,67      4096
            srv0042 F:\  DATA2      0,03     0,03         100     16384
            srv0007 C:\  System     0,07     0,01       11,92      4096

        .EXAMPLE
            Get-DbaDiskSpace -ComputerName srv0042 -Force | Format-Table -AutoSize

            Get all disk and volume space information.

            Server  Name                                              Label    SizeInGB FreeInGB PercentFree BlockSize IsSqlDisk FileSystem DriveType
            ------  ----                                              -----    -------- -------- ----------- --------- --------- ---------- ---------
            srv0042 C:\                                               System     126,45   114,12       90,25      4096     False NTFS       Local Disk
            srv0042 E:\                                               Data1       97,62    96,33       98,67      4096     False ReFS       Local Disk
            srv0042 F:\                                               DATA2        29,2     29,2         100     16384     False FAT32      Local Disk
            srv0042 \\?\Volume{7a31be94-b842-42f5-af71-e0464a1a9803}\ Recovery     0,44     0,13       30,01      4096     False NTFS       Local Disk
            srv0042 D:\                                                               0        0           0               False            Compact Disk

        .EXAMPLE
            Get-DbaDiskSpace -ComputerName srv0042 -ExcludeDrive 'C:\'  | Format-Table -AutoSize
            Get all disk and volume space information.

            Server  Name                                              Label    SizeInGB FreeInGB PercentFree BlockSize IsSqlDisk FileSystem DriveType
            ------  ----                                              -----    -------- -------- ----------- --------- --------- ---------- ---------
            srv0042 E:\                                               Data1       97,62    96,33       98,67      4096     False ReFS       Local Disk
            srv0042 F:\                                               DATA2        29,2     29,2         100     16384     False FAT32      Local Disk

        .NOTES
            Tags: Storage
            Author: Chrissy LeMaire (clemaire@gmail.com) & Jakob Bindslet (jakob@bindslet.dk)

            dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
            Copyright (C) 2016 Chrissy LeMaire
            License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

        .LINK
            https://dbatools.io/Get-DbaDiskSpace
    #>
    [CmdletBinding()]
    Param (
        [Parameter(ValueFromPipeline = $true)]
        [Alias('ServerInstance', 'SqlInstance', 'SqlServer')]
        [DbaInstance[]]$ComputerName = $env:COMPUTERNAME,
        [ValidateSet('Bytes', 'KB', 'MB', 'GB', 'TB', 'PB')]
        [String]$Unit = 'GB',
        [Switch]$CheckForSql,
        [PSCredential]$SqlCredential,
        [PSCredential]$Credential,
        [string[]]$ExcludeDrive,
        [Alias('Detailed', 'AllDrives')]
        [Switch]$Force,
        [Switch]$CheckFragmentation,
        [Switch][Alias('Silent')]
        $EnableException
    )

    begin {
        Test-DbaDeprecation -DeprecatedOn 1.0.0 -Parameter Detailed
        Test-DbaDeprecation -DeprecatedOn 1.0.0 -Parameter AllDrives
        Test-DbaDeprecation -DeprecatedOn 1.0.0 -Parameter Unit

        $condition = " WHERE DriveType = 2 OR DriveType = 3"
        if ($Force) { $condition = "" }

        # Keep track of what computer was already processed to avoid duplicates
        $processed = New-Object System.Collections.ArrayList
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

            try { $disks = Get-DbaCmObject -ComputerName $computer.ComputerName -Query "SELECT * FROM Win32_Volume$condition" -Credential $Credential -Namespace root\CIMv2 -ErrorAction Stop -WarningAction SilentlyContinue -EnableException }
            catch { Stop-Function -Message "Failed to connect to $computer." -EnableException $EnableException -ErrorRecord $_ -Target $computer.ComputerName -Continue }

            if ($CheckForSql) {
                try {
                    $server = Connect-SqlInstance -SqlInstance $computer -SqlCredential $SqlCredential
                    $sqlSuccess = $true
                }
                catch {
                    Write-Message -Level Warning -Message "Failed to connect to $computer, will not be reporting SQL Stats!" -ErrorRecord $_ -OverrideExceptionMessage -Target $computer.ComputerName
                    $sqlSuccess = $false
                }
            }

            foreach ($disk in $disks) {
                if ($disk.Name -in $ExcludeDrive) { continue }
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

                if ($CheckForSql -and $sqlSuccess) {
                    $countSqlDisks = -1
                    try { $countSqlDisks = $server.Query("Select count(*) as Count from sys.master_files where physical_name like '$($disk.Name)%'").Count }
                    catch { Write-Message -Level Warning -Message "Failed to query for master_files on $computer" -ErrorRecord $_ }
                    $info.IsSqlDisk = ($countSqlDisks -gt 0)
                }

                $info
            }
        }
    }
}