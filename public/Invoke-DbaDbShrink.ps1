function Invoke-DbaDbShrink {
    <#
    .SYNOPSIS
        Reduces the physical size of database files by removing unused space from data and log files.

        - Shrinks can cause severe index fragmentation (to the tune of 99%)
        - Shrinks can cause massive growth in the database's transaction log
        - Shrinks can require a lot of time and system resources to perform data movement

    .DESCRIPTION
        Reduces database file sizes by removing unused space from data files, log files, or both. This function targets specific files within databases and can reclaim substantial disk space when databases have grown significantly beyond their current data requirements.

        Use this function sparingly and only when disk space recovery is critical, such as after large data deletions, index rebuilds, or when preparing databases for migration. The function supports chunked shrinking operations to minimize performance impact and provides detailed fragmentation statistics to help assess the operation's effects.

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
        Specifies which databases to shrink on the target instance. Accepts wildcard patterns and multiple database names.
        Use this when you need to shrink specific databases rather than all databases on the instance.

    .PARAMETER ExcludeDatabase
        Excludes specific databases from the shrink operation when processing multiple databases. Accepts wildcard patterns.
        Useful when shrinking all user databases but want to skip critical production databases or those with specific maintenance windows.

    .PARAMETER AllUserDatabases
        Targets all user databases on the instance, excluding system databases (master, model, msdb, tempdb).
        Use this for maintenance operations across an entire instance while preserving system database integrity.

    .PARAMETER PercentFreeSpace
        Sets the percentage of free space to maintain in the database files after shrinking, ranging from 0-99. Defaults to 0.
        Leave some free space (10-20%) to accommodate normal database growth and reduce the need for frequent auto-growth events.

    .PARAMETER ShrinkMethod
        Controls how SQL Server performs the shrink operation. Default moves data pages and truncates files.
        EmptyFile migrates all data to other files in the filegroup. NoTruncate moves pages but doesn't truncate. TruncateOnly reclaims space without moving data.
        Use TruncateOnly when possible as it's the least resource-intensive and doesn't cause data movement or fragmentation.

    .PARAMETER StatementTimeout
        Sets the command timeout in minutes for the shrink operation. Defaults to 0 (infinite timeout).
        Large database shrinks can take hours to complete, so the default allows operations to run without timing out.

    .PARAMETER LogsOnly
        Deprecated. Use FileType instead.

    .PARAMETER FileType
        Determines which database files to target for shrinking: All (data and log files), Data (only data files), or Log (only log files). Defaults to All.
        Use Data when you only need to reclaim space from data files after large deletions. Use Log to specifically target transaction log files after maintenance operations.

    .PARAMETER StepSize
        Breaks large shrink operations into smaller chunks of the specified size. Use PowerShell size notation like 100MB or 1GB.
        Chunked shrinks reduce resource contention and allow for better progress monitoring during large shrink operations. Recommended for databases being shrunk by several gigabytes.

    .PARAMETER ExcludeIndexStats
        Skips collecting index fragmentation statistics before and after the shrink operation.
        Use this to speed up the shrink process when you don't need fragmentation analysis or are planning to rebuild indexes immediately afterward.

    .PARAMETER ExcludeUpdateUsage
        Skips running DBCC UPDATEUSAGE before the shrink operation to ensure accurate space usage statistics.
        Use this to reduce operation time when space usage statistics are already current or when immediate shrinking is more important than precision.

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

    .PARAMETER InputObject
        Accepts database objects from the pipeline, typically from Get-DbaDatabase output.
        Use this for advanced filtering scenarios or when combining multiple database operations in a pipeline.

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

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance sql2012 -Database Northwind,pubs | Invoke-DbaDbShrink

        Shrinks all databases coming from a pre-filtered list via Get-DbaDatabase

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param (
        [Parameter(ValueFromPipeline)]
        [Parameter(ParameterSetName = 'SqlInstance', Position = 0)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [switch]$AllUserDatabases,
        [ValidateRange(0, 99)]
        [int]$PercentFreeSpace = 0,
        [ValidateSet('Default', 'EmptyFile', 'NoTruncate', 'TruncateOnly')]
        [string]$ShrinkMethod = 'Default',
        [ValidateSet('All', 'Data', 'Log')]
        [string]$FileType = 'All',
        [int64]$StepSize,
        [int]$StatementTimeout = 0,
        [switch]$ExcludeIndexStats,
        [switch]$ExcludeUpdateUsage,
        [switch]$EnableException,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject
    )

    begin {

        if ((Test-Bound -ParameterName StepSize) -and $StepSize -lt 1024) {
            Stop-Function -Message "StepSize is measured in bits. Did you mean $StepSize bits? If so, please use 1024 or above. If not, then use the PowerShell bit notation like $($StepSize)MB or $($StepSize)GB"
            return
        }

        if ($StepSize) {
            $stepSizeKB = ([dbasize]($StepSize)).Kilobyte
        }
        $StatementTimeoutSeconds = $StatementTimeout * 60

        $sql = 'SELECT
                  AVG(avg_fragmentation_in_percent) AS [avg_fragmentation_in_percent]
                , MAX(avg_fragmentation_in_percent) AS [max_fragmentation_in_percent]
                FROM sys.dm_db_index_physical_stats (DB_ID(), NULL, NULL, NULL, NULL) AS indexstats
                WHERE indexstats.avg_fragmentation_in_percent > 0 AND indexstats.page_count > 100
                GROUP BY indexstats.database_id'
    }

    process {
        if (Test-FunctionInterrupt) { return }

        if (-not $Database -and -not $ExcludeDatabase -and -not $AllUserDatabases -and -not $InputObject) {
            Stop-Function -Message 'You must specify databases to execute against using either -Database, -Exclude or -AllUserDatabases, or piping them in'
            return
        }

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message 'Failure' -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

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
                $InputObject += $db
            }
        }

        foreach ($db in $InputObject) {

            $instance = $db.Parent

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
                # $file.Size and $file.UsedSpace are in KB and translated here to bytes as the dbasize type requires
                [dbasize]$startingSizeKB = $file.Size * 1024
                [dbasize]$spaceUsedKB = $file.UsedSpace * 1024
                [dbasize]$spaceAvailableKB = ($startingSizeKB - $spaceUsedKB)
                [dbasize]$desiredSpaceAvailableKB = [math]::ceiling((($PercentFreeSpace / 100)) * $spaceUsedKB)
                [dbasize]$desiredFileSizeKB = $spaceUsedKB + $desiredSpaceAvailableKB

                Write-Message -Level Verbose -Message "File: $($file.Name)"
                Write-Message -Level Verbose -Message "Initial Size: $($startingSizeKB)"
                Write-Message -Level Verbose -Message "Space Used: $($spaceUsedKB)"
                Write-Message -Level Verbose -Message "Initial Freespace: $($spaceAvailableKB)"
                Write-Message -Level Verbose -Message "Target Freespace: $($desiredSpaceAvailableKB)"
                Write-Message -Level Verbose -Message "Target FileSize: $($desiredFileSizeKB)"

                if ($spaceAvailableKB -le $desiredSpaceAvailableKB) {
                    Write-Message -Level Warning -Message "File size of ($startingSizeKB) is less than or equal to the desired outcome ($desiredFileSizeKB) for $($file.Name)"
                } else {
                    if ($Pscmdlet.ShouldProcess("$db on $instance, file $($file.Name)", "Shrinking from $($startingSizeKB) to $($desiredFileSizeKB)")) {
                        if ($server.VersionMajor -gt 8 -and $ExcludeIndexStats -eq $false) {
                            Write-Message -Level Verbose -Message 'Getting starting average fragmentation'
                            $dataRow = $server.Query($sql, $db.name)
                            $startingFrag = $dataRow.avg_fragmentation_in_percent
                            $startingTopFrag = $dataRow.max_fragmentation_in_percent
                        } else {
                            $startingTopFrag = $startingFrag = $null
                        }

                        $start = Get-Date
                        # saving previous timeout to be restored at the end
                        $previousStatementTimeout = $instance.ConnectionContext.StatementTimeout
                        try {
                            Write-Message -Level Verbose -Message 'Beginning shrink of files'
                            $instance.ConnectionContext.StatementTimeout = $StatementTimeoutSeconds
                            Write-Message -Level Debug -Message "Connection timeout set to $StatementTimeout"
                            [dbasize]$shrinkGapKB = ($startingSizeKB - $desiredFileSizeKB)
                            Write-Message -Level Verbose -Message "ShrinkGap: $($shrinkGapKB)"
                            Write-Message -Level Verbose -Message "Step Size: $($stepSizeKB) KB"

                            if ($stepSizeKB -and ($shrinkGapKB.Kilobyte -ge $stepSizeKB)) {
                                $numberIterations = [math]::ceiling($((($shrinkGapKB.Kilobyte) / $stepSizeKB)))
                                for ($i = 1; $i -le $numberIterations; $i++) {
                                    Write-Message -Level Verbose -Message "Step: $i of $numberIterations"
                                    [dbasize]$shrinkSizeKB = ($startingSizeKB.Kilobyte - ($stepSizeKB * $i)) * 1024
                                    if ($shrinkSizeKB -lt $desiredFileSizeKB) {
                                        $shrinkSizeKB = $desiredFileSizeKB
                                    }
                                    Write-Message -Level Verbose -Message ('Shrinking {0} to {1}' -f $file.Name, $shrinkSizeKB)
                                    $file.Shrink($shrinkSizeKB.Megabyte, $ShrinkMethod)
                                    $file.Refresh()

                                    if ($startingSizeKB -eq ($file.Size * 1024)) {
                                        Write-Message -Level Verbose -Message ('Unable to shrink further')
                                        break
                                    }
                                }
                            } else {
                                $file.Shrink(($desiredFileSizeKB.Megabyte), $ShrinkMethod)
                                $file.Refresh()
                            }
                            $success = $true
                        } catch {
                            $success = $false
                            Stop-Function -Message 'Failure' -EnableException $EnableException -ErrorRecord $_ -Continue
                            continue
                        } finally {
                            $instance.ConnectionContext.StatementTimeout = $previousStatementTimeout
                        }
                        $end = Get-Date
                        [dbasize]$finalFileSizeKB = $file.Size * 1024
                        [dbasize]$finalSpaceAvailableKB = ($finalFileSizeKB - ($file.UsedSpace * 1024))
                        Write-Message -Level Verbose -Message "Final file size: $($finalFileSizeKB)"
                        Write-Message -Level Verbose -Message "Final file space available: $($finalSpaceAvailableKB)"

                        if ($server.VersionMajor -gt 8 -and $ExcludeIndexStats -eq $false -and $success -and $FileType -ne 'Log') {
                            Write-Message -Level Verbose -Message 'Getting ending average fragmentation'
                            $dataRow = $server.Query($sql, $db.name)
                            $endingDefrag = $dataRow.avg_fragmentation_in_percent
                            $endingTopDefrag = $dataRow.max_fragmentation_in_percent
                        } else {
                            $endingTopDefrag = $endingDefrag = $null
                        }

                        $timSpan = New-TimeSpan -Start $start -End $end
                        $ts = [TimeSpan]::FromSeconds($timSpan.TotalSeconds)
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
                            InitialSize                 = ($startingSizeKB)
                            InitialUsed                 = ($spaceUsedKB)
                            InitialAvailable            = ($spaceAvailableKB)
                            TargetAvailable             = ($desiredSpaceAvailableKB)
                            FinalAvailable              = ($finalSpaceAvailableKB)
                            FinalSize                   = ($finalFileSizeKB)
                            InitialAverageFragmentation = [math]::Round($startingFrag, 1)
                            FinalAverageFragmentation   = [math]::Round($endingDefrag, 1)
                            InitialTopFragmentation     = [math]::Round($startingTopFrag, 1)
                            FinalTopFragmentation       = [math]::Round($endingTopDefrag, 1)
                            Notes                       = 'Database shrinks can cause massive index fragmentation and negatively impact performance. You should now run DBCC INDEXDEFRAG or ALTER INDEX ... REORGANIZE'
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