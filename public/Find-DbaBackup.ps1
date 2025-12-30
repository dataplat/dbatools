function Find-DbaBackup {
    <#
    .SYNOPSIS
        Searches filesystem directories for SQL Server backup files based on age and extension criteria.

    .DESCRIPTION
        Recursively scans specified directories to locate SQL Server backup files (.bak, .trn, .dif, etc.) older than your defined retention period. Returns file objects that can be piped to removal commands or processed for cleanup workflows.

        This function replaces manual directory searches when managing backup retention policies. You can filter results to only include files that have been archived (using the Archive bit check) to ensure backups are safely stored elsewhere before cleanup.

        Commonly used in automated maintenance scripts to identify backup files ready for deletion based on your organization's retention requirements.

    .PARAMETER Path
        Specifies the root directory path to recursively search for backup files. Searches all subdirectories within this path.
        Use this to target specific backup locations like dedicated backup drives or network shares where your SQL Server backups are stored.

    .PARAMETER BackupFileExtension
        Specifies the file extension to search for without the period (e.g., 'bak', 'trn', 'dif', 'log').
        Use 'bak' for full backups, 'trn' or 'log' for transaction log backups, or 'dif' for differential backups depending on which backup type you need to manage.

    .PARAMETER RetentionPeriod
        Specifies how old backup files must be before they're included in results, using format like '7d' or '48h'.
        Files older than this period will be returned, making this essential for backup cleanup operations based on your retention policy.
        Valid units: h (hours), d (days), w (weeks), m (months). Examples: '48h', '7d', '4w', '1m'.

    .PARAMETER CheckArchiveBit
        Only includes backup files that have been archived to another location (Archive bit is not set).
        Use this safety feature to ensure backups have been copied to tape, cloud storage, or other backup systems before cleanup to prevent accidental data loss.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Backup, Lookup
        Author: Chris Sommer (@cjsommer), www.cjsommer.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Find-DbaBackup

    .OUTPUTS
        System.IO.FileInfo

        Returns one file object for each backup file found in the specified directory and subdirectories that meets the age and archive bit criteria.

        Properties:
        - FullName: The complete path to the backup file
        - Name: The file name including extension
        - Extension: The file extension (e.g., .bak, .trn, .dif, .log)
        - DirectoryName: The directory containing the file
        - Length: The file size in bytes
        - LastWriteTime: The timestamp when the file was last modified, used to determine if it meets the retention period
        - Attributes: File attributes including the Archive bit status (checked when -CheckArchiveBit is specified)
        - CreationTime: The timestamp when the file was created
        - LastAccessTime: The timestamp when the file was last accessed

        These file objects are suitable for piping to Remove-Item or other file management cmdlets for automated cleanup workflows.

    .EXAMPLE
        PS C:\> Find-DbaBackup -Path 'C:\MSSQL\SQL Backup\' -BackupFileExtension trn -RetentionPeriod 48h

        Searches for all trn files in C:\MSSQL\SQL Backup\ and all subdirectories that are more than 48 hours old will be included.

    .EXAMPLE
        PS C:\> Find-DbaBackup -Path 'C:\MSSQL\Backup\' -BackupFileExtension bak -RetentionPeriod 7d -CheckArchiveBit

        Searches for all bak files in C:\MSSQL\Backup\ and all subdirectories that are more than 7 days old will be included, but only if the files have been backed up to another location as verified by checking the Archive bit.

    .EXAMPLE
         PS C:\> Find-DbaBackup -Path '\\SQL2014\Backup\' -BackupFileExtension bak -RetentionPeriod 24h | Remove-Item -Verbose

         Searches for all bak files in \\SQL2014\Backup\ and all subdirectories that are more than 24 hours old and deletes only those files with verbose message.
    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, HelpMessage = "Full path to the root level backup folder (ex. 'C:\SQL\Backups'")]
        [Alias("BackupFolder")]
        [string]$Path,
        [parameter(Mandatory, HelpMessage = "Backup File extension to remove (ex. bak, trn, dif)")]
        [string]$BackupFileExtension ,
        [parameter(Mandatory, HelpMessage = "Backup retention period. (ex. 24h, 7d, 4w, 6m)")]
        [string]$RetentionPeriod ,
        [switch]$CheckArchiveBit = $false ,
        [switch]$EnableException
    )

    begin {
        ### Local Functions
        function Convert-UserFriendlyRetentionToDatetime {
            [cmdletbinding()]
            param (
                [string]$UserFriendlyRetention
            )

            <#
            Convert a user friendly retention value into a datetime.
            The last character of the string will indicate units (validated)
            Valid units are: (h = hours, d = days, w = weeks, m = months)

            The preceeding characters are the value and must be an integer (validated)

            Examples:
                '48h' = 48 hours
                '7d' = 7 days
                '4w' = 4 weeks
                '1m' = 1 month
            #>

            [int]$Length = ($UserFriendlyRetention).Length
            $Value = ($UserFriendlyRetention).Substring(0, $Length - 1)
            $Units = ($UserFriendlyRetention).Substring($Length - 1, 1)

            # Validate that $Units is an accepted unit of measure
            if ( $Units -notin @('h', 'd', 'w', 'm') ) {
                throw "RetentionPeriod '$UserFriendlyRetention' units invalid! See Get-Help for correct formatting and examples."
            }

            # Validate that $Value is an INT
            if ( ![int]::TryParse($Value, [ref]"") ) {
                throw "RetentionPeriod '$UserFriendlyRetention' format invalid! See Get-Help for correct formatting and examples."
            }

            switch ($Units) {
                #Variable marked as unused by PSScriptAnalyzer
                'h' { <# $UnitString = 'Hours';#> [datetime]$ReturnDatetime = (Get-Date).AddHours( - $Value) }
                'd' { <# $UnitString = 'Days';#> [datetime]$ReturnDatetime = (Get-Date).AddDays( - $Value) }
                'w' { <# $UnitString = 'Weeks';#> [datetime]$ReturnDatetime = (Get-Date).AddDays( - $Value * 7) }
                'm' { <# $UnitString = 'Months';#> [datetime]$ReturnDatetime = (Get-Date).AddMonths( - $Value) }
            }
            $ReturnDatetime
        }

        # Validations
        # Ensure BackupFileExtension does not begin with a .
        if ($BackupFileExtension -match "^[.]") {
            Write-Message -Level Warning -Message "Parameter -BackupFileExtension begins with a period '$BackupFileExtension'. A period is automatically prepended to -BackupFileExtension and need not be passed in."
        }
        # Ensure Path is a proper path
        if (!(Test-Path $Path -PathType 'Container')) {
            Stop-Function -Message "$Path not found"
        }

    }
    process {
        if (Test-FunctionInterrupt) { return }
        # Process stuff
        Write-Message -Message "Finding backups on $Path" -Level Verbose
        # Convert Retention Value to an actual DateTime
        try {
            $RetentionDate = Convert-UserFriendlyRetentionToDatetime -UserFriendlyRetention $RetentionPeriod
            Write-Message -Message "Backup Retention Date set to $RetentionDate" -Level Verbose
        } catch {
            Stop-Function -Message "Failed to interpret retention time." -ErrorRecord $_
        }

        # Filter out unarchived files if -CheckArchiveBit parameter is used
        if ($CheckArchiveBit) {
            Write-Message -Message "Removing only archived files." -Level Verbose
            filter DbaArchiveBitFilter {
                if ($_.Attributes -notmatch "Archive") {
                    $_
                }
            }
        } else {
            filter DbaArchiveBitFilter {
                $_
            }
        }
        # Enumeration may take a while. Without resorting to "esoteric" file listing facilities
        # and given we need to fetch at least the LastWriteTime, let's just use "streaming" processing
        # here to avoid issues like described in #970
        Get-ChildItem $Path -Filter "*.$BackupFileExtension" -File -Recurse -ErrorAction SilentlyContinue -ErrorVariable EnumErrors |
            Where-Object LastWriteTime -lt $RetentionDate | DbaArchiveBitFilter
        if ($EnumErrors) {
            Write-Message "Errors encountered enumerating files." -Level Warning -ErrorRecord $EnumErrors
        }
    }
}