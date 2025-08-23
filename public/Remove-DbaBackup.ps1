function Remove-DbaBackup {
    <#
    .SYNOPSIS
        Removes SQL Server backup files from disk based on retention policies and file extension criteria.

    .DESCRIPTION
        Recursively searches backup directories and removes SQL Server backup files older than your specified retention period. This function automates the tedious process of manually cleaning up old backup files to free disk space and maintain storage compliance.

        You can target specific backup types by extension (.bak, .trn, .dif) and define retention periods using flexible time units (hours, days, weeks, months). The Archive bit check ensures files are only deleted after they've been backed up to another location, preventing accidental loss of unarchived backups.

        Replaces the backup cleanup functionality found in SQL Server maintenance plans with more granular control and PowerShell automation. Optionally removes empty backup folders after file cleanup to keep your backup directory structure tidy.

    .PARAMETER Path
        Specifies the root directory where backup files are stored for cleanup. The function recursively searches all subdirectories from this location.
        Use this to target your primary backup storage location, whether it's a local drive, network share, or mounted backup volume.

    .PARAMETER BackupFileExtension
        Specifies the file extension for the backup type to clean up. Common values are 'bak' for full backups, 'trn' for transaction log backups, or 'dif' for differential backups.
        Use this to target specific backup types during cleanup, allowing you to apply different retention policies for each backup type. Do not include the period.

    .PARAMETER RetentionPeriod
        Defines how long to keep backup files before deletion, formatted as number plus unit (48h, 7d, 4w, 1m).
        Use shorter periods for transaction log backups (24h-48h) and longer periods for full backups (1w-4w) based on your recovery requirements and storage capacity.

        Valid units: h=hours, d=days, w=weeks, m=months
        Examples: '48h' keeps files for 48 hours, '7d' for 7 days, '4w' for 4 weeks, '1m' for 1 month

    .PARAMETER CheckArchiveBit
        Prevents deletion of files that haven't been archived to tape or another backup location by checking the Windows Archive bit.
        Use this when you have a two-tier backup strategy where files are first copied to disk, then archived to tape or cloud storage before cleanup.

    .PARAMETER RemoveEmptyBackupFolder
        Removes directories that become empty after backup file cleanup to prevent folder structure clutter.
        Use this to maintain a clean backup directory structure, especially when backup files are organized by database or date folders.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.i

    .NOTES
        Tags: Backup, DisasterRecovery
        Author: Chris Sommer (@cjsommer), www.cjsommer.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Remove-DbaBackup

    .EXAMPLE
        PS C:\> Remove-DbaBackup -Path 'C:\MSSQL\SQL Backup\' -BackupFileExtension trn -RetentionPeriod 48h

        '*.trn' files in 'C:\MSSQL\SQL Backup\' and all subdirectories that are more than 48 hours old will be removed.

    .EXAMPLE
        PS C:\> Remove-DbaBackup -Path 'C:\MSSQL\SQL Backup\' -BackupFileExtension trn -RetentionPeriod 48h -WhatIf

        Same as example #1, but doesn't actually remove any files. The function will instead show you what would be done.
        This is useful when first experimenting with using the function.

    .EXAMPLE
        PS C:\> Remove-DbaBackup -Path 'C:\MSSQL\Backup\' -BackupFileExtension bak -RetentionPeriod 7d -CheckArchiveBit

        '*.bak' files in 'C:\MSSQL\Backup\' and all subdirectories that are more than 7 days old will be removed, but only if the files have been backed up to another location as verified by checking the Archive bit.

    .EXAMPLE
        PS C:\> Remove-DbaBackup -Path 'C:\MSSQL\Backup\' -BackupFileExtension bak -RetentionPeriod 1w -RemoveEmptyBackupFolder

        '*.bak' files in 'C:\MSSQL\Backup\' and all subdirectories that are more than 1 week old will be removed. Any folders left empty will be removed as well.

#>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [parameter(Mandatory, HelpMessage = "Full path to the root level backup folder (ex. 'C:\SQL\Backups'")]
        [Alias("BackupFolder")]
        [string]$Path,
        [parameter(Mandatory, HelpMessage = "Backup File extension to remove (ex. bak, trn, dif)")]
        [string]$BackupFileExtension ,
        [parameter(Mandatory, HelpMessage = "Backup retention period. (ex. 24h, 7d, 4w, 6m)")]
        [string]$RetentionPeriod ,
        [switch]$CheckArchiveBit = $false ,
        [switch]$RemoveEmptyBackupFolder = $false,
        [switch]$EnableException
    )
    begin {
        # Ensure BackupFileExtension does not begin with a .
        if ($BackupFileExtension -match "^[.]") {
            Write-Message -Level Warning -Message "Parameter -BackupFileExtension begins with a period '$BackupFileExtension'. A period is automatically prepended to -BackupFileExtension and need not be passed in."
        }
    }
    process {
        # Process stuff
        Write-Message -Message "Removing backups from $Path" -Level Verbose
        Find-DbaBackup -Path $Path -BackupFileExtension $BackupFileExtension -RetentionPeriod $RetentionPeriod -CheckArchiveBit:$CheckArchiveBit -EnableException |
            ForEach-Object {
                $file = $_
                if ($PSCmdlet.ShouldProcess($file.Directory.FullName, "Removing backup file $($file.Name)")) {
                    try {
                        $file | Remove-Item -Force -EA Stop
                    } catch {
                        Write-Message -Message "Failed to remove $file." -Level Warning -ErrorRecord $_
                    }
                }
            }
        Write-Message -Message "File Cleaning ended." -Level Verbose
        # Cleanup empty backup folders.
        if ($RemoveEmptyBackupFolder) {
            Write-Message -Message "Removing empty folders." -Level Verbose
            (Get-ChildItem -Directory -Path $Path -Recurse -ErrorAction SilentlyContinue -ErrorVariable EnumErrors).FullName |
                Sort-Object -Descending |
                ForEach-Object {
                    $OrigPath = $_
                    try {
                        $Contents = @(Get-ChildItem -Force $OrigPath -ErrorAction Stop)
                    } catch {
                        Write-Message -Message "Can't enumerate $OrigPath." -Level Warning -ErrorRecord $_
                    }
                    if ($Contents.Count -eq 0) {
                        return $_
                    }
                } |
                ForEach-Object {
                    $FolderPath = $_
                    if ($PSCmdlet.ShouldProcess($Path, "Removing empty folder .$($FolderPath.Replace($Path, ''))")) {
                        try {
                            $FolderPath | Remove-Item -ErrorAction Stop
                        } catch {
                            Write-Message -Message "Failed to remove $FolderPath." -Level Warning -ErrorRecord $_
                        }
                    }
                }
            if ($EnumErrors) {
                Write-Message "Errors encountered enumerating folders." -Level Warning -ErrorRecord $EnumErrors
            }
            Write-Message -Message "Removed empty folders." -Level Verbose
        }
    }
}