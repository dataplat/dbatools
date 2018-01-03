function Invoke-DbaDatabaseShrink {
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
    http://sqlmag.com/sql-server/shrinking-data-files

However, there are some cases where a database will need to be shrunk. In the event that you must shrink your database:

1. Ensure you have plenty of space for your T-Log to grow
2. Understand that shrinks require a lot of CPU and disk resources
3. Consider running DBCC INDEXDEFRAG or ALTER INDEX ... REORGANIZE after the shrink is complete.

.PARAMETER SqlInstance
The SQL Server that you're connecting to.

.PARAMETER SqlCredential
SqlCredential object used to connect to the SQL Server as a different user.

.PARAMETER Database
The database(s) to process - this list is auto-populated from the server. If unspecified, all databases will be processed.

.PARAMETER ExcludeDatabase
The database(s) to exclude - this list is auto-populated from the server

.PARAMETER AllUserDatabases
Run command against all user databases

.PARAMETER PercentFreeSpace
Specifies how much to reduce the database in percent, defaults to 0.

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
Timeout in minutes. Defaults to infinity (shrinks can take a while.)

.PARAMETER LogsOnly
Deprecated. Use FileType instead

.PARAMETER FileType
Specifies the files types that will be shrunk

        All
            All Data and Log files are shrunk, using database shrink (Default)
        Data
            Just the Data files are shrunk using file shrink
        Log
            Just the Log files are shrunk using file shrink

.PARAMETER ExcludeIndexStats
Exclude statistics about fragmentation

.PARAMETER ExcludeUpdateUsage
Exclude DBCC UPDATE USAGE for database

.PARAMETER WhatIf
Shows what would happen if the command were to run

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
Tags: Shrink, Databases

Website: https://dbatools.io
Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

.LINK
https://dbatools.io/Invoke-DbaDatabaseShrink

.EXAMPLE
Invoke-DbaDatabaseShrink -SqlInstance sql2016 -Database Northwind,pubs,Adventureworks2014

Shrinks Northwind, pubs and Adventureworks2014 to have as little free space as possible.

.EXAMPLE
Invoke-DbaDatabaseShrink -SqlInstance sql2014 -Database Adventureworks2014 -PercentFreeSpace 50

Shrinks Adventureworks2014 to have 50% free space. So let's say Adventureworks2014 was 1GB and it's using 100MB space. The database free space would be reduced to 50MB.

.EXAMPLE
Invoke-DbaDatabaseShrink -SqlInstance sql2012 -AllUserDatabases

Shrinks all databases on SQL2012 (not ideal for production)

#>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
    Param (
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [Alias("Credential")]
        [PSCredential]
        $SqlCredential,
        [Alias("Databases")]
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [switch]$AllUserDatabases,
        [ValidateRange(0, 99)]
        [int]$PercentFreeSpace = 0,
        [ValidateSet('Default', 'EmptyFile', 'NoTruncate', 'TruncateOnly')]
        [string]$ShrinkMethod = "Default",
        [ValidateSet('All', 'Data', 'Log')]
        [string]$FileType = "All",
        [int]$StatementTimeout = 0,
        [switch]$LogsOnly,
        [switch]$ExcludeIndexStats,
        [switch]$ExcludeUpdateUsage,
        [switch][Alias('Silent')]$EnableException
    )

    begin {
        if ($LogsOnly) {
            Test-DbaDeprecation -DeprecatedOn "1.0.0" -Parameter "LogsOnly"
            $FileType = 'Log'
        }

        $StatementTimeoutSeconds = $StatementTimeout * 60

        $sql = "SELECT
                indexstats.avg_fragmentation_in_percent
                FROM sys.dm_db_index_physical_stats (DB_ID(), NULL, NULL, NULL, NULL) AS indexstats
                INNER JOIN sys.tables dbtables on dbtables.[object_id] = indexstats.[object_id]
                INNER JOIN sys.schemas dbschemas on dbtables.[schema_id] = dbschemas.[schema_id]
                INNER JOIN sys.indexes AS dbindexes ON dbindexes.[object_id] = indexstats.[object_id]
                AND indexstats.index_id = dbindexes.index_id
                WHERE indexstats.database_id = DB_ID() AND indexstats.avg_fragmentation_in_percent > 0
                ORDER BY indexstats.avg_fragmentation_in_percent desc"

        $sqltop1 = "SELECT top 1
                indexstats.avg_fragmentation_in_percent
                FROM sys.dm_db_index_physical_stats (DB_ID(), NULL, NULL, NULL, NULL) AS indexstats
                INNER JOIN sys.tables dbtables on dbtables.[object_id] = indexstats.[object_id]
                INNER JOIN sys.schemas dbschemas on dbtables.[schema_id] = dbschemas.[schema_id]
                INNER JOIN sys.indexes AS dbindexes ON dbindexes.[object_id] = indexstats.[object_id]
                AND indexstats.index_id = dbindexes.index_id
                WHERE indexstats.database_id = DB_ID()
                ORDER BY indexstats.avg_fragmentation_in_percent desc"
    }

    process {
        if (!$Database -and !$ExcludeDatabase -and !$AllUserDatabases) {
            Stop-Function -Message "You must specify databases to execute against using either -Databases, -Exclude or -AllUserDatabases" -Continue
        }

        foreach ($instance in $SqlInstance) {
            Write-Message -Level Verbose -Message "Connecting to $instance"
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential

            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            # changing statement timeout to $StatementTimeout
            if ($StatementTimeout -eq 0) {
                Write-Message -Level Verbose -Message "Changing statement timeout to infinity"
            }
            else {
                Write-Message -Level Verbose -Message "Changing statement timeout to $StatementTimeout minutes"
            }
            $server.ConnectionContext.StatementTimeout = $StatementTimeoutSeconds

            $dbs = $server.Databases | Where-Object { $_.IsSystemObject -eq $false -and $_.IsAccessible }

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

                $startingsize = $db.Size
                $spaceAvailableMB = $db.SpaceAvailable / 1024
                $spaceused = $startingsize - $spaceAvailableMB
                $desiredSpaceAvailable = ($PercentFreeSpace * $spaceused) / 100

                Write-Message -Level Verbose -Message "Starting Size (MB): $startingsize"
                Write-Message -Level Verbose -Message "Starting Freespace (MB): $([int]$spaceavailableMB)"
                Write-Message -Level Verbose -Message "Desired Freespace (MB): $([int]$desiredSpaceAvailable)"

                if (($db.SpaceAvailable / 1024) -le $desiredSpaceAvailable) {
                    Write-Message -Level Warning -Message "Space Available ($spaceavailableMB) is less than or equal to the desired outcome ($desiredSpaceAvailable)"
                }
                else {
                    if ($Pscmdlet.ShouldProcess("$db on $instance", "Shrinking from $([int]$spaceavailableMB) MB space available to $([int]$desiredSpaceAvailable) MB space available")) {
                        if ($db.Tables.Indexes.Name -and $server.VersionMajor -gt 8 -and $ExcludeIndexStats -eq $false) {
                            Write-Message -Level Verbose -Message "Getting average fragmentation"
                            $startingfrag = ($server.Query($sql, $db.name) | Select-Object -ExpandProperty avg_fragmentation_in_percent | Measure-Object -Average).Average
                            $startingtopfrag = ($server.Query($sqltop1, $db.name)).avg_fragmentation_in_percent
                        }
                        else {
                            $startingtopfrag = $startingfrag = $null
                        }

                        $start = Get-Date

                        switch ($FileType) {
                            'Log' {
                                try {
                                    Write-Message -Level Verbose -Message "Beginning shrink of log files"
                                    $db.LogFiles.Shrink($PercentFreeSpace, $ShrinkMethod)
                                    $db.Refresh()
                                    Write-Message -Level Verbose -Message "Recalculating space usage"
                                    $success = $true
                                    $notes = $null
                                }
                                catch {
                                    $success = $false
                                    $notes = $_.Exception.InnerException
                                }
                            }
                            'Data' {
                                try {
                                    Write-Message -Level Verbose -Message "Beginning shrink of data files"
                                    foreach ($fileGroup in $db.FileGroups) {
                                        foreach ($file in $fileGroup.Files) {
                                            Write-Message -Level Verbose -Message "Beggining shrink of $($file.Name)"
                                            $file.Shrink($PercentFreeSpace, $ShrinkMethod)
                                        }
                                    }
                                    $db.Refresh()
                                    Write-Message -Level Verbose -Message "Recalculating space usage"
                                    if (-not $ExcludeUpdateUsage) { $db.RecalculateSpaceUsage() }
                                    $success = $true
                                    $notes = $null
                                }
                                catch {
                                    $success = $false
                                    $notes = $_.Exception.InnerException
                                }
                            }
                            default {
                                try {
                                    Write-Message -Level Verbose -Message "Beginning shrink of entire database"
                                    $db.Shrink($PercentFreeSpace, $ShrinkMethod)
                                    $db.Refresh()
                                    Write-Message -Level Verbose -Message "Recalculating space usage"
                                    if (-not $ExcludeUpdateUsage) { $db.RecalculateSpaceUsage() }
                                    $success = $true
                                    $notes = $null
                                }
                                catch {
                                    $success = $false
                                    $notes = $_.Exception.InnerException
                                }
                            }
                        }

                        $end = Get-Date
                        $dbsize = $db.Size
                        $newSpaceAvailableMB = $db.SpaceAvailable / 1024

                        Write-Message -Level Verbose -Message "Final database size: $([int]$dbsize) MB"
                        Write-Message -Level Verbose -Message "Final space available: $([int]$newSpaceAvailableMB) MB"

                        if ($db.Tables.Indexes.Name -and $server.VersionMajor -gt 8 -and $ExcludeIndexStats -eq $false) {
                            Write-Message -Level Verbose -Message "Refreshing indexes and getting average fragmentation"
                            $endingdefrag = ($server.Query($sql, $db.name) | Select-Object -ExpandProperty avg_fragmentation_in_percent | Measure-Object -Average).Average
                            $endingtopfrag = ($server.Query($sqltop1, $db.name)).avg_fragmentation_in_percent
                        }
                        else {
                            $endingtopfrag = $endingdefrag = $null
                        }

                        $timespan = New-TimeSpan -Start $start -End $end
                        $ts = [timespan]::fromseconds($timespan.TotalSeconds)
                        $elapsed = "{0:HH:mm:ss}" -f ([datetime]$ts.Ticks)
                    }
                }

                #$db.TruncateLog()

                if ($Pscmdlet.ShouldProcess("$db on $instance", "Showing results")) {
                    if ($null -eq $notes) {
                        $notes = "Database shrinks can cause massive index fragmentation and negatively impact performance. You should now run DBCC INDEXDEFRAG or ALTER INDEX ... REORGANIZE"
                    }

                    $object = [pscustomobject]@{
                        ComputerName                  = $server.NetName
                        InstanceName                  = $server.ServiceName
                        SqlInstance                   = $server.DomainInstanceName
                        Database                      = $db.name
                        Start                         = $start
                        End                           = $end
                        Elapsed                       = $elapsed
                        Success                       = $success
                        StartingTotalSizeMB           = [math]::Round($startingsize, 2)
                        StartingUsedMB                = [math]::Round($spaceused, 2)
                        FinalTotalSizeMB              = [math]::Round($db.size, 2)
                        StartingAvailableMB           = [math]::Round($spaceavailableMB, 2)
                        DesiredAvailableMB            = [math]::Round($desiredSpaceAvailable, 2)
                        FinalAvailableMB              = [math]::Round(($db.SpaceAvailable / 1024), 2)
                        StartingAvgIndexFragmentation = [math]::Round($startingfrag, 1)
                        EndingAvgIndexFragmentation   = [math]::Round($endingdefrag, 1)
                        StartingTopIndexFragmentation = [math]::Round($startingtopfrag, 1)
                        EndingTopIndexFragmentation   = [math]::Round($endingtopfrag, 1)
                        Notes                         = $notes
                    }

                    if ($ExcludeIndexStats) {
                        Select-DefaultView -InputObject $object -ExcludeProperty StartingAvgIndexFragmentation, EndingAvgIndexFragmentation, StartingTopIndexFragmentation, EndingTopIndexFragmentation
                    }
                    else {
                        $object
                    }
                }
            }
        }
    }
}

