function Find-DbaBackup {
    <#
    .SYNOPSIS
        Finds SQL Server backups on disk.

    .DESCRIPTION
        Provides all of the same functionality for finding SQL backups to remove from disk as a standard maintenance plan would.

        As an addition you have the ability to check the Archive bit on files before deletion. This will allow you to ensure backups have been archived to your archive location before removal.

    .PARAMETER Path
        Specifies the name of the base level folder to search for backup files.

    .PARAMETER BackupFileExtension
        Specifies the filename extension of the backup files you wish to find (typically 'bak', 'trn' or 'log'). Do not include the period.

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
        If this switch is enabled, the filesystem Archive bit is checked.
        If this bit is set (which translates to "it has not been backed up to another location yet"), the file won't be included.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Backup
        Author: Chris Sommer (@cjsommer), www.cjsommer.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Find-DbaBackup

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