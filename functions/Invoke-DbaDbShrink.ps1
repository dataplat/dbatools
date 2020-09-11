function Invoke-DbaDbShrink {
    <#
    .SYNOPSIS
        Shrinks all files in a database. This is a command that should rarely be used.

        - Shrinks can cause severe index fragmentation (to the tune of 99%)
        - Shrinks can cause massive growth in the database's transaction log
        - Shrinks can require a lot of time and system resources to perform data movement

    .DESCRIPTION
        Shrinks all files in a database. Databases should be shrunk only when completely necessary.

        Many awesome SQL people have written about why you should not shrink your data files. Paul Randal and Kalen Delaney wrote great posts about this topic:

        http://www.sqlskills.com/blogs/paul/why-you-should-not-shrink-your-data-files
        https://www.itprotoday.com/sql-server/shrinking-data-files

        However, there are some cases where a database will need to be shrunk. In the event that you must shrink your database:

        1. Ensure you have plenty of space for your T-Log to grow
        2. Understand that shrinks require a lot of CPU and disk resources
        3. Consider running DBCC INDEXDEFRAG or ALTER INDEX ... REORGANIZE after the shrink is complete.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. Defaults to the default instance on localhost.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance..

    .PARAMETER Database
        The database(s) to process - this list is auto-populated from the server. If unspecified, all databases will be processed.

    .PARAMETER ExcludeDatabase
        The database(s) to exclude - this list is auto-populated from the server.

    .PARAMETER AllUserDatabases
        Run command against all user databases.

    .PARAMETER PercentFreeSpace
        Specifies how much free space to leave, defaults to 0.

    .PARAMETER ShrinkMethod
        Specifies the method that is used to shrink the database
        Default
        Data in pages located at the end of a file is moved to pages earlier in the file. Files are truncated to reflect allocated space.
        EmptyFile
        Migrates all of the data from the referenced file to other files in the same filegroup. (DataFile and LogFile objects only).
        NoTruncate
        Data in pages located at the end of a file is moved to pages earlier in the file.
        TruncateOnly
        Data distribution is not affected. Files are truncated to reflect allocated space, recovering free space at the end of any file.

    .PARAMETER StatementTimeout
        Timeout in minutes. Defaults to infinity (shrinks can take a while).

    .PARAMETER LogsOnly
        Deprecated. Use FileType instead.

    .PARAMETER FileType
        Specifies the files types that will be shrunk
        All - All Data and Log files are shrunk, using database shrink (Default)
        Data - Just the Data files are shrunk using file shrink
        Log - Just the Log files are shrunk using file shrink

    .PARAMETER StepSize
        Measured in bits - but no worries! PowerShell has a very cool way of formatting bits. Just specify something like: 1MB or 10GB. See the examples for more information.

        If specified, this will chunk a larger shrink operation into multiple smaller shrinks.
        If shrinking a file by a large amount there are benefits of doing multiple smaller chunks.

    .PARAMETER ExcludeIndexStats
        Exclude statistics about fragmentation.

    .PARAMETER ExcludeUpdateUsage
        Exclude DBCC UPDATE USAGE for database.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run.

    .PARAMETER Confirm
        Prompts for confirmation of every step. For example:

        Are you sure you want to perform this action?
        Performing the operation "Shrink database" on target "pubs on SQL2016\VNEXT".
        [Y] Yes  [A] Yes to All  [N] No  [L] No to All  [S] Suspend  [?] Help (default is "Y"):

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Shrink, Database
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Invoke-DbaDbShrink

    .EXAMPLE
        PS C:\> Invoke-DbaDbShrink -SqlInstance sql2016 -Database Northwind,pubs,Adventureworks2014

        Shrinks Northwind, pubs and Adventureworks2014 to have as little free space as possible.

    .EXAMPLE
        PS C:\> Invoke-DbaDbShrink -SqlInstance sql2014 -Database AdventureWorks2014 -PercentFreeSpace 50

        Shrinks AdventureWorks2014 to have 50% free space. So let's say AdventureWorks2014 was 1GB and it's using 100MB space. The database free space would be reduced to 50MB.

    .EXAMPLE
        PS C:\> Invoke-DbaDbShrink -SqlInstance sql2014 -Database AdventureWorks2014 -PercentFreeSpace 50 -FileType Data -StepSize 25MB

        Shrinks AdventureWorks2014 to have 50% free space, runs shrinks in 25MB chunks for improved performance.

    .EXAMPLE
        PS C:\> Invoke-DbaDbShrink -SqlInstance sql2012 -AllUserDatabases

        Shrinks all user databases on SQL2012 (not ideal for production)

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [switch]$AllUserDatabases,
        [ValidateRange(0, 99)]
        [int]$PercentFreeSpace = 0,
        [ValidateSet('Default', 'EmptyFile', 'NoTruncate', 'TruncateOnly')]
        [string]$ShrinkMethod = "Default",
        [ValidateSet('All', 'Data', 'Log')]
        [string]$FileType = "All",
        [int64]$StepSize,
        [int]$StatementTimeout = 0,
        [switch]$ExcludeIndexStats,
        [switch]$ExcludeUpdateUsage,
        [switch]$EnableException
    )

    begin {
        if (-not $Database -and -not $ExcludeDatabase -and -not $AllUserDatabases) {
            Stop-Function -Message "You must specify databases to execute against using either -Database, -Exclude or -AllUserDatabases"
            return
        }

        if ((Test-Bound -ParameterName StepSize) -and $StepSize -lt 1024) {
            Stop-Function -Message "StepSize is measured in bits. Did you mean $StepSize bits? If so, please use 1024 or above. If not, then use the PowerShell bit notation like $($StepSize)MB or $($StepSize)GB"
            return
        }

        if ($StepSize) {
            $stepSizeKB = ([dbasize]($StepSize)).Kilobyte
        }
        $StatementTimeoutSeconds = $StatementTimeout * 60

        $sql = "SELECT
                  avg(avg_fragmentation_in_percent) as [avg_fragmentation_in_percent]
                , max(avg_fragmentation_in_percent) as [max_fragmentation_in_percent]
                FROM sys.dm_db_index_physical_stats (DB_ID(), NULL, NULL, NULL, NULL) AS indexstats
                WHERE indexstats.avg_fragmentation_in_percent > 0 AND indexstats.page_count > 100
                GROUP BY indexstats.database_id"
    }

    process {
        if (Test-FunctionInterrupt) { return }

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $server.ConnectionContext.StatementTimeout = $StatementTimeoutSeconds
            Write-Message -Level Verbose -Message "Connection timeout set to $StatementTimeout"

            $dbs = $server.Databases | Where-Object { $_.IsAccessible }

            if ($AllUserDatabases) {
                $dbs = $dbs | Where-Object { $_.IsSystemObject -eq $false }
            }

            if ($Database) {
                $dbs = $dbs | Where-Object Name -In $Database
            }

            if ($ExcludeDatabase) {
                $dbs = $dbs | Where-Object Name -NotIn $ExcludeDatabase
            }

            foreach ($db in $dbs) {

                Write-Message -Level Verbose -Message "Processing $db on $instance"

                if ($db.IsDatabaseSnapshot) {
                    Write-Message -Level Warning -Message "The database $db on server $instance is a snapshot and cannot be shrunk. Skipping database."
                    continue
                }

                $files = @()
                if ($FileType -in ('Log', 'All')) {
                    $files += $db.LogFiles
                }
                if ($FileType -in ('Data', 'All')) {
                    $files += $db.FileGroups.Files
                }

                foreach ($file in $files) {
                    $startingSize = $file.Size
                    $spaceUsed = $file.UsedSpace
                    $spaceAvailable = ($file.Size - $file.UsedSpace)
                    $desiredSpaceAvailable = [math]::ceiling((($PercentFreeSpace / 100)) * $spaceUsed)
                    $desiredFileSize = $spaceUsed + $desiredSpaceAvailable

                    Write-Message -Level Verbose -Message "File: $($file.Name)"
                    Write-Message -Level Verbose -Message "Initial Size (KB): $([int]$startingSize)"
                    Write-Message -Level Verbose -Message "Space Used (KB): $([int]$spaceUsed)"
                    Write-Message -Level Verbose -Message "Initial Freespace (KB): $([int]$spaceAvailable)"
                    Write-Message -Level Verbose -Message "Target Freespace (KB): $([int]$desiredSpaceAvailable)"
                    Write-Message -Level Verbose -Message "Target FileSize (KB): $([int]$desiredFileSize)"

                    if ($spaceAvailable -le $desiredSpaceAvailable) {
                        Write-Message -Level Warning -Message "File size of ($startingSize) is less than or equal to the desired outcome ($desiredFileSize) for $($file.Name)"
                    } else {
                        if ($Pscmdlet.ShouldProcess("$db on $instance", "Shrinking from $([int]$startingSize)KB to $([int]$desiredFileSize)KB")) {
                            if ($server.VersionMajor -gt 8 -and $ExcludeIndexStats -eq $false) {
                                Write-Message -Level Verbose -Message "Getting starting average fragmentation"
                                $dataRow = $server.Query($sql, $db.name)
                                $startingFrag = $dataRow.avg_fragmentation_in_percent
                                $startingTopFrag = $dataRow.max_fragmentation_in_percent
                            } else {
                                $startingTopFrag = $startingFrag = $null
                            }

                            $start = Get-Date
                            try {
                                Write-Message -Level Verbose -Message "Beginning shrink of files"

                                $shrinkGap = ($startingSize - $desiredFileSize)
                                Write-Message -Level Verbose -Message "ShrinkGap: $([int]$shrinkGap) KB"
                                Write-Message -Level Verbose -Message "Step Size: $($stepSizeKB) KB"

                                if ($stepSizeKB -and ($shrinkGap -ge $stepSizeKB)) {
                                    for ($i = 1; $i -le [int](($shrinkGap) / $stepSizeKB); $i++) {
                                        Write-Message -Level Verbose -Message "Step: $i / $([int](($shrinkGap) / $stepSizeKB))"
                                        $shrinkSize = $startingSize - ($stepSizeKB * $i)
                                        if ($shrinkSize -lt $desiredFileSize) {
                                            $shrinkSize = $desiredFileSize
                                        }
                                        Write-Message -Level Verbose -Message ("Shrinking {0} to {1}" -f $file.Name, $shrinkSize)
                                        $file.Shrink(($shrinkSize / 1024), $ShrinkMethod)
                                        $file.Refresh()

                                        if ($startingSize -eq $file.Size) {
                                            Write-Message -Level Verbose -Message ("Unable to shrink further")
                                            break
                                        }
                                    }
                                } else {
                                    $file.Shrink(($desiredFileSize / 1024), $ShrinkMethod)
                                    $file.Refresh()
                                }
                                $success = $true
                            } catch {
                                $success = $false
                                Stop-Function -message "Failure" -EnableException $EnableException -ErrorRecord $_ -Continue
                                continue
                            }
                            $end = Get-Date
                            $finalFileSize = $file.Size
                            $finalSpaceAvailable = ($file.Size - $file.UsedSpace)
                            Write-Message -Level Verbose -Message "Final file size: $([int]$finalFileSize) KB"
                            Write-Message -Level Verbose -Message "Final file space available: $($finalSpaceAvailable) KB"

                            if ($server.VersionMajor -gt 8 -and $ExcludeIndexStats -eq $false -and $success -and $FileType -ne 'Log') {
                                Write-Message -Level Verbose -Message "Getting ending average fragmentation"
                                $dataRow = $server.Query($sql, $db.name)
                                $endingDefrag = $dataRow.avg_fragmentation_in_percent
                                $endingTopDefrag = $dataRow.max_fragmentation_in_percent
                            } else {
                                $endingTopDefrag = $endingDefrag = $null
                            }

                            $timSpan = New-TimeSpan -Start $start -End $end
                            $ts = [TimeSpan]::fromseconds($timSpan.TotalSeconds)
                            $elapsed = "{0:HH:mm:ss}" -f ([datetime]$ts.Ticks)

                            $object = [PSCustomObject]@{
                                ComputerName                = $server.ComputerName
                                InstanceName                = $server.ServiceName
                                SqlInstance                 = $server.DomainInstanceName
                                Database                    = $db.name
                                File                        = $file.name
                                Start                       = $start
                                End                         = $end
                                Elapsed                     = $elapsed
                                Success                     = $success
                                InitialSize                 = [dbasize]($startingSize * 1024)
                                InitialUsed                 = [dbasize]($spaceUsed * 1024)
                                InitialAvailable            = [dbasize]($spaceAvailable * 1024)
                                TargetAvailable             = [dbasize]($desiredSpaceAvailable * 1024)
                                FinalAvailable              = [dbasize]($finalSpaceAvailable * 1024)
                                FinalSize                   = [dbasize]($finalFileSize * 1024)
                                InitialAverageFragmentation = [math]::Round($startingFrag, 1)
                                FinalAverageFragmentation   = [math]::Round($endingDefrag, 1)
                                InitialTopFragmentation     = [math]::Round($startingTopFrag, 1)
                                FinalTopFragmentation       = [math]::Round($endingTopDefrag, 1)
                                Notes                       = "Database shrinks can cause massive index fragmentation and negatively impact performance. You should now run DBCC INDEXDEFRAG or ALTER INDEX ... REORGANIZE"
                            }
                            if ($ExcludeIndexStats) {
                                Select-DefaultView -InputObject $object -ExcludeProperty InitialAverageFragmentation, FinalAverageFragmentation, InitialTopFragmentation, FinalTopFragmentation
                            } else {
                                $object
                            }
                        }
                    }
                }
            }
        }
    }
}