function Remove-DbaBackup {
    <#
    .SYNOPSIS
        Removes SQL Server backup files from disk based on retention policies and file extension criteria.

    .DESCRIPTION
        Recursively searches backup directories and removes SQL Server backup files older than your specified retention period. This function automates the tedious process of manually cleaning up old backup files to free disk space and maintain storage compliance.

        You can target specific backup types by extension (.bak, .trn, .dif) and define retention periods using flexible time units (hours, days, weeks, months). The Archive bit check ensures files are only deleted after they've been backed up to another location, preventing accidental loss of unarchived backups.

        Replaces the backup cleanup functionality found in SQL Server maintenance plans with more granular control and PowerShell automation. Optionally removes empty backup folders after file cleanup to keep your backup directory structure tidy.

    .PARAMETER Path
        Specifies the name of the base level folder to search for backup files. Deletion of backup files will be recursive from this location.

    .PARAMETER BackupFileExtension
        Specifies the filename extension of the backup files you wish to remove (typically 'bak', 'trn' or 'log'). Do not include the period.

    .PARAMETER RetentionPeriod
        Specifies the retention period for backup files. Correct format is ##U.

        ## is the retention value and must be an integer value
        U signifies the units where the valid units are:
        h = hours
        d = days
        w = weeks
        m = months

        Formatting Examples:
        '48h' = 48 hours
        '7d' = 7 days
        '4w' = 4 weeks
        '1m' = 1 month

    .PARAMETER CheckArchiveBit
        If this switch is enabled, the filesystem Archive bit is checked before deletion. If this bit is set (which translates to "it has not been backed up to another location yet", the file won't be deleted.

    .PARAMETER RemoveEmptyBackupFolder
        If this switch is enabled, empty folders will be removed after the cleanup process is complete.

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