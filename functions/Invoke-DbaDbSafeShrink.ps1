function Invoke-DbaDbSafeShrink {
    <#
    .SYNOPSIS
        Shrinks all data files in a database safely. Can be used to safely recover disk space after deleting large amounts of data. Only data files can be shrunk. Still not
        advisable to use on a production system during production hours.

        - This command can double the used space size of a file group while it is shrinking it. You should have as much free space needed as the used space size of your largest file group.
        - Fragmentation is not affected at all. It will be the exact same as before the operation.
        - Shrinks can require a lot of time and system resources to perform data movement

        Steps:
            - Loops all of the files groups for the database
                - Creates a new filegroup and file to temporarily house the indexes that file group
                - Moves all indexes to the new filegroup
                - Shrinks all of the now empty files in the original filegroup
                - Moves all of the indexes back to the original filegroup from the temporary filegroup
                - Removes the temporary file group and file
            - Starts loop over again with next file group

    .DESCRIPTION
        This function is written as to follow the following recommendation from Paul Randal: https://www.sqlskills.com/blogs/paul/why-you-should-not-shrink-your-data-files/

        QUOTE:
            The method I like to recommend is as follows:
            - Create a new filegroup
            - Move all affected tables and indexes into the new filegroup using the CREATE INDEX � WITH (DROP_EXISTING = ON) ON syntax, to move the tables and remove fragmentation from them at the same time
            - Drop the old filegroup that you were going to shrink anyway (or shrink it way down if its the primary filegroup)

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

    .PARAMETER StatementTimeout
        Timeout in minutes. Defaults to infinity (shrinks can take a while). Valid range is from 0 (infinity) to 1 day (1440).

    .PARAMETER WhatIf
        Shows what would happen if the command were to run.

    .PARAMETER Confirm
        Prompts for confirmation of every step. For example:

        Are you sure you want to perform this action?
        Performing the operation "Shrink database" on target "pubs on SQL2016\VNEXT".
        [Y] Yes  [A] Yes to All  [N] No  [L] No to All  [S] Suspend  [?] Help (default is "Y"):

    .PARAMETER MinimumFreeSpace
        Measured in bits - but no worries! PowerShell has a very cool way of formatting bits. Just specify something like: 1MB or 10GB. See the examples for more information.

        If specified, the shrink will only occur if the total free space exceeds this value.
        If not specified then all databases will be shrunk regardless of how much free space is available.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Shrink, Database
        Author: Tim Cartwright

        Website: https://dbatools.io
        Copyright: (c) 2022 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Invoke-DbaDbSafeShrink

    .EXAMPLE
        PS C:\> Invoke-DbaDbSafeShrink -SqlInstance sql2016 -Database Northwind,pubs,Adventureworks2014

        Shrinks Northwind, pubs and Adventureworks2014 to have as little free space as possible.

    .EXAMPLE
        PS C:\> Invoke-DbaDbSafeShrink -SqlInstance sql2014 -Database AdventureWorks2014 -MinimumFreeSpace 25MB

        Shrinks AdventureWorks2014 only if the free space exceeds 25MB.

    .EXAMPLE
        PS C:\> Invoke-DbaDbSafeShrink -SqlInstance sql2012 -AllUserDatabases

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
        [ValidateRange(0, 1440)] # 1 day = 1440 minutes
        [int]$StatementTimeout = 0,
        [Int64]$MinimumFreeSpace = 0,
        [switch]$EnableException
    )

    begin {
        # this will be the name of the file group and files we create temporarily to store the data so we can shrink the file groups files
        $shrinkName = "SHRINK_DATA_TEMP"
        if (-not $Database -and -not $ExcludeDatabase -and -not $AllUserDatabases) {
            Stop-Function -Message "You must specify databases to execute against using either -Database, -ExcludeDatabase or -AllUserDatabases"
            return
        }

        $StatementTimeoutSeconds = $StatementTimeout * 60

        #private functions
        function MoveIndexes ($server, $db, $fromFG, $toFG) {
            Write-Message -Level Verbose -Message "DATABASE [$($db.Name)]"
            foreach ($table in $db.Tables) {
                $tableName = "[$($table.Schema)].[$($table.Name)]"
                Write-Message -Level Verbose -Message "-TABLE: $tableName"
                foreach ($index in $table.Indexes) {
                    if ($index.FileGroup -ieq $fromFG) {
                        Write-Message -Level Verbose -Message "--INDEX: [$($index.Name)] [$fromFG] --> [$toFG]"

                        # set the new filegroup, and the dropexisting property so the script will generate properly
                        $index.FileGroup = $toFG
                        $index.DropExistingIndex = $true
                        $indexScript = $index.Script()

                        $server.Query($indexScript, $db.Name)
                    }
                }
            }
        }

        function PeformFileOperation($server, $db, $sql) {
            #TIM C: There might be a better way to approach this, but this works until a better way comes along
            # A t-log backup could be occurring which would cause this script to break, so lets pause for a bit to try again, if we get that specific error
            # https://blog.sqlauthority.com/2014/11/09/sql-server-fix-error-msg-3023-level-16-state-2-backup-file-manipulation-operations-such-as-alter-database-add-file-and-encryption-changes-on-a-database-must-be-serialized/
            $tryAgain = $false
            $tryAgainCount = 0
            $sleep = 15
            [int]$tryAgainCountMax = (300 / $sleep) # 300 (seconds) == 5 minutes wait, unless it succeeds

            do {
                $tryAgain = $false
                try {
                    $server.Query($sql, $db.Name)
                } catch {
                    $msg = $_.Exception.GetBaseException().Message
                    if (++$tryAgainCount -lt $tryAgainCountMax -and $msg -imatch "Backup,\s+file\s+manipulation\s+operations\s+\(such\s+as .*?\)\s+and\s+encryption\s+changes\s+on\s+a\s+database\s+must\s+be\s+serialized\.") {
                        Write-Message -Level Warning -Message "BACKUP SERIALIZATION ERROR, PAUSING FOR ($sleep) SECONDS, AND TRYING AGAIN. TRY: $($tryAgainCount + 1)"
                        $tryAgain = $true
                        Start-Sleep -Seconds $sleep
                    } else {
                        # not the exception about a backup blocking us, or we are out of retries, so bail
                        throw
                    }
                }
            } while ($tryAgain)
        }

        function ShrinkFile($server, $db, $file, $minimum) {
            $fileName = $file.Name
            [int]$size = $file.Size / 1000 #size is in KB, convert to MB for the shrink statement

            $rawsql = "DBCC SHRINKFILE($fileName, {0}) WITH NO_INFOMSGS;"
            if ($size -gt $minimum) {
                do {
                    Write-Message -Level Verbose -Message "LOOPING SHRINKFILE"
                    $size = ShrinkFileIncremental -server $server -db $db -size $size -rawSql $rawsql -minimum $minimum | Select-Object -Last 1
                } while ($size -gt $minimum)
            }

            $sql = $rawsql -f $minimum
            Write-Message -Level Verbose -Message "PERFORMING: $sql"
            $server.Query($sql, $db.Name)
        }

        function ShrinkFileIncremental($server, $db, [string] $rawSql, [int]$size, $minimum) {
            # this function tries to step down the shrink using a formula to calculate the step size based upon the size of the file
            # the bigger the file, the lower the percent, the smaller, the higher. shrinking large chunks at a time is very very slow
            $percent = (0.20 - (0.00007 * ($size / 1000)))
            [int]$shrinkIncrement = $size * $percent

            if ($shrinkIncrement -gt 0) {
                for ($x = $size; $x -gt $minimum; $x -= $shrinkIncrement) {
                    $size = $x
                    $sql = $rawsql -f $x
                    Write-Message -Level Verbose -Message "PERFORMING: $sql"
                    $server.Query($sql, $db.Name)
                }
            }
            return $size
        }

        function CreateShrinkFileGroup($server, $db, $baseFile, $fileSize) {
            $shrinkFG = $db.FileGroups | Where-Object { $_.Name -ieq "$shrinkName" } | Select-Object -First 1

            if (!$shrinkFG) {
                $createFGSql = "
                    ALTER DATABASE [$($db.Name)] ADD FILEGROUP $shrinkName
                    ALTER DATABASE [$($db.Name)]
                        ADD FILE (
                            NAME = '$shrinkName',
                            FILENAME = '$($baseFile.FileName)_$shrinkName.mdf',
                            FILEGROWTH = $($baseFile.Growth)$($baseFile.GrowthType),
                            SIZE = $($fileSize)KB
                        )
                    TO FILEGROUP $shrinkName
                "

                Write-Message -Level Verbose -Message "CREATING FILEGROUP / FILE $shrinkName"
                PeformFileOperation -server $server -db $db -sql "$createFGSql"
            }
        }

        function RemoveShrinkFileGroup($server, $db) {
            Write-Message -Level Verbose -Message "REMOVING $shrinkName FG AND FILE"
            $sql = "
                ALTER DATABASE [$($db.Name)] REMOVE FILE $shrinkName
                ALTER DATABASE [$($db.Name)] REMOVE FILEGROUP $shrinkName
            "
            PeformFileOperation -server $server -db $db -sql "$sql"
        }
    }

    process {
        if (Test-FunctionInterrupt) { return }

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
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
                if ($db.Tables.Count -eq 0) {
                    Write-Message -Level Warning -Message "The database $db on server $instance contains no tables and cannot be shrunk using this method. Skipping database."
                    continue
                }


                foreach ($fileGroup in $db.FileGroups) {
                    if ($PSCmdlet.ShouldProcess("$db on $instance", "Shrinking file group: [$($fileGroup.Name)]")) {
                        Write-Message -Level Verbose -Message "Beginning shrink of $db file group [$($fileGroup.Name)]"

                        # find the primary file for the FG, we will use its sizing to create our temp FG / File
                        $primaryFile = $fileGroup.Files | Where-Object { $_.IsPrimaryFile } | Select-Object -First 1
                        $usedSizes = $fileGroup.Files | Measure-Object -Property UsedSpace -Sum -Minimum -Average
                        $totalSizes = $fileGroup.Files | Measure-Object -Property Size -Sum -Minimum -Average

                        # find the total used size of all the data files. We will size our temp file to 75% of that to reduce file growths
                        $sumFileSize = $usedSizes.Sum * 0.75
                        # this will be our minimum target when shrinking the file
                        $minFileSize = $usedSizes.Minimum * 0.75

                        [dbasize]$spaceAvailable = ($totalSizes.Sum - $usedSizes.Sum)

                        if ($MinimumFreeSpace -gt $spaceAvailable) {
                            Write-Message -Level Warning -Message "The total unused space $($spaceAvailable) of the filegroup $($fileGroup.Name) is less than or equal to the desired minimum free space $([dbasize]$MinimumFreeSpace). Skipping file group."
                            continue
                        }

                        $output = @{}

                        foreach ($file in $fileGroup.Files) {
                            [dbasize]$startingSize = $file.Size
                            [dbasize]$spaceUsed = $file.UsedSpace
                            [dbasize]$spaceAvailable = ($file.Size - $file.UsedSpace)

                            Write-Message -Level Verbose -Message "File: $($file.Name)"
                            Write-Message -Level Verbose -Message "Initial Size: $($startingSize)"
                            Write-Message -Level Verbose -Message "Space Used: $($spaceUsed)"
                            Write-Message -Level Verbose -Message "Initial Free space: $($spaceAvailable)"

                            $object = [PSCustomObject]@{
                                ComputerName     = $server.ComputerName
                                InstanceName     = $server.ServiceName
                                SqlInstance      = $server.DomainInstanceName
                                Database         = $db.name
                                FileGroup        = $fileGroup.Name
                                File             = $file.name
                                Start            = (Get-Date)
                                End              = $null
                                Elapsed          = $null
                                Success          = $null
                                InitialSize      = ($startingSize * 1024)
                                InitialUsed      = ($spaceUsed * 1024)
                                InitialAvailable = ($spaceAvailable * 1024)
                                FinalAvailable   = $null
                                FinalSize        = $null
                                PercentShrunk    = $null
                            }
                            $output.Add("$($db.Name)_$($file.Name)", $object)
                        }

                        try {
                            # create a new temporary file group based off the current primary file, and all used size
                            CreateShrinkFileGroup -server $server -db $db -baseFile $primaryFile -fileSize $sumFileSize

                            # move all of the indexes off to the new temporary file group an file
                            MoveIndexes -server $server -db $db -fromFG $fileGroup.Name -toFG "$shrinkName"

                            # now shrink all of the files in the file group down to the minimum size. even though these files are now empty, shrinking them takes a long time. go figure
                            # sadly alter file with modify file can only be specified to make the file larger.
                            # https://docs.microsoft.com/en-us/sql/t-sql/statements/alter-database-transact-sql-file-and-filegroup-options?view=sql-server-ver15#:~:text=If%20SIZE%20is%20specified%2C%20the%20new%20size%20must%20be%20larger%20than%20the%20current%20file%20size.
                            foreach ($file in $fileGroup.Files) {
                                ShrinkFile -server $server -db $db -file $file -minimum $minFileSize
                            }

                            # now that we have shrunk all of the files down to the minimum size, lets move all of the indexes back
                            MoveIndexes -server $server -db $db -fromFG "$shrinkName" -toFG $fileGroup.Name

                            # finally we need to cleanup and remove the temporary filegroup and file
                            RemoveShrinkFileGroup -server $server -db $db

                            $success = $true
                        } catch {
                            $success = $false
                            Stop-Function -message "Failure" -EnableException $EnableException -ErrorRecord $_ -Continue
                            continue
                        }

                        #now lets loop the files after the shink has done, and get our updated stats
                        foreach ($file in $fileGroup.Files) {
                            $file.Refresh()

                            [dbasize]$finalFileSize = $file.Size
                            [dbasize]$finalSpaceAvailable = ($file.Size - $file.UsedSpace)
                            Write-Message -Level Verbose -Message "Final file size: $($finalFileSize)"
                            Write-Message -Level Verbose -Message "Final file space available: $($finalSpaceAvailable)"

                            $out = $output["$($db.Name)_$($file.Name)"]
                            $out.end = Get-Date
                            $out.Elapsed = (New-TimeSpan -Start $out.Start -End $out.End).ToString("hh\:mm\:ss")
                            $out.Success = $success
                            $out.FinalAvailable = ($finalSpaceAvailable * 1024)
                            $out.FinalSize = ($finalFileSize * 1024)
                            $out.PercentShrunk = [math]::Round((($out.InitialSize.Megabyte - $out.FinalSize.Megabyte) / $out.InitialSize.Megabyte) * 100, 2)
                        }

                        $output.Values
                    }
                }
            }
        }
    }
}