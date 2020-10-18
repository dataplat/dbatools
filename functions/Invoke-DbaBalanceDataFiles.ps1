function Invoke-DbaBalanceDataFiles {
    <#
    .SYNOPSIS
        Re-balance data between data files

    .DESCRIPTION
        When you have a large database with a single data file and add another file, SQL Server will only use the new file until it's about the same size.
        You may want to balance the data between all the data files.

        The function will check the server version and edition to see if the it allows for online index rebuilds.
        If the server does support it, it will try to rebuild the index online.
        If the server doesn't support it, it will rebuild the index offline. Be carefull though, this can cause downtime

        The tables must have a clustered index to be able to balance out the data.
        The function does NOT yet support heaps.

        The function will also check if the file groups are subject to balance out.
        A file group whould have at least have 2 data files and should be writable.
        If a table is within such a file group it will be subject for processing. If not the table will be skipped.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The database(s) to process.

    .PARAMETER Table
        The tables(s) of the database to process. If unspecified, all tables will be processed.

    .PARAMETER RebuildOffline
        Will set all the indexes to rebuild offline.
        This option is also needed when the server version is below 2005.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run

    .PARAMETER Confirm
        Prompts for confirmation of every step. For example:

        The server does not support online rebuilds of indexes.
        Do you want to rebuild the indexes offline?
        [Y] Yes  [N] No   [?] Help (default is "Y"):

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER Force
        This will disable the check for enough disk space for the action to be successful.
        Use this with caution!!

    .NOTES
        Tags: Database, FileManagement, File, Space
        Author: Sander Stad (@sqlstad), sqlstad.nl

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Invoke-DbaBalanceDataFiles

    .EXAMPLE
        PS C:\> Invoke-DbaBalanceDataFiles -SqlInstance sql1 -Database db1

        This command will distribute the data in database db1 on instance sql1

    .EXAMPLE
        PS C:\> Invoke-DbaBalanceDataFiles -SqlInstance sql1 -Database db1 | Select-Object -ExpandProperty DataFilesEnd

        This command will distribute the data in database db1 on instance sql1

    .EXAMPLE
        PS C:\> Invoke-DbaBalanceDataFiles -SqlInstance sql1 -Database db1 -Table table1,table2,table5

        This command will distribute the data for only the tables table1,table2 and table5

    .EXAMPLE
        PS C:\> Invoke-DbaBalanceDataFiles -SqlInstance sql1 -Database db1 -RebuildOffline

        This command will consider the fact that there might be a SQL Server edition that does not support online rebuilds of indexes.
        By supplying this parameter you give permission to do the rebuilds offline if the edition does not support it.

    #>
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess, ConfirmImpact = "Medium")]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseSingularNouns", "", Justification = "Singular Noun doesn't make sense")]
    param (
        [parameter(ParameterSetName = "Pipe", Mandatory)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [Alias("Tables")]
        [object[]]$Table,
        [switch]$RebuildOffline,
        [switch]$EnableException,
        [switch]$Force
    )
    begin {
        if ($Force) { $ConfirmPreference = 'none' }
    }
    process {

        Write-Message -Message "Starting balancing out data files" -Level Verbose

        # Set the initial success flag
        [bool]$success = $true

        foreach ($instance in $SqlInstance) {
            # Try connecting to the instance
            try {
                $Server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            # Check the database parameter
            if ($Database) {
                if ($Database -notin $server.Databases.Name) {
                    Stop-Function -Message "One or more databases cannot be found on instance on instance $instance" -Target $instance -Continue
                }

                $DatabaseCollection = $server.Databases | Where-Object { $_.Name -in $Database }
            } else {
                Stop-Function -Message "Please supply a database to balance out" -Target $instance -Continue
            }

            # Get the server version
            $serverVersion = $server.Version.Major

            # Check edition of the sql instance
            if ($RebuildOffline) {
                Write-Message -Message "Continuing with offline rebuild." -Level Verbose
            } elseif (-not $RebuildOffline -and ($serverVersion -lt 9 -or (([string]$Server.Edition -notmatch "Developer") -and ($Server.Edition -notmatch "Enterprise")))) {
                # Set up the confirm part
                $message = "The server does not support online rebuilds of indexes. `nDo you want to rebuild the indexes offline?"
                $choiceYes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", "Answer Yes."
                $choiceNo = New-Object System.Management.Automation.Host.ChoiceDescription "&No", "Answer No."
                $options = [System.Management.Automation.Host.ChoiceDescription[]]($choiceYes, $choiceNo)
                $result = $host.ui.PromptForChoice($title, $message, $options, 0)

                # Check the result from the confirm
                switch ($result) {
                    # If yes
                    0 {
                        # Set the option to generate a full backup
                        Write-Message -Message "Continuing with offline rebuild." -Level Verbose

                        [bool]$supportOnlineRebuild = $false
                    }
                    1 {
                        Stop-Function -Message "You chose to not allow offline rebuilds of indexes. Use -RebuildOffline" -Target $instance
                        return
                    }
                } # switch
            } elseif ($serverVersion -ge 9 -and (([string]$Server.Edition -like "Developer*") -or ($Server.Edition -like "Enterprise*"))) {
                [bool]$supportOnlineRebuild = $true
            }

            # Loop through each of the databases
            foreach ($db in $DatabaseCollection) {
                $dataFilesStarting = Get-DbaDbFile -SqlInstance $server -Database $db.Name | Where-Object { $_.TypeDescription -eq 'ROWS' } | Select-Object ID, LogicalName, PhysicalName, Size, UsedSpace, AvailableSpace | Sort-Object ID

                if (-not $Force) {
                    # Check the amount of disk space available
                    $query = "SELECT SUBSTRING(physical_name, 0, 4) AS 'Drive' ,
                                        SUM(( size * 8 ) / 1024) AS 'SizeMB'
                                FROM	sys.master_files
                                WHERE	DB_NAME(database_id) = '$($db.Name)'
                                GROUP BY SUBSTRING(physical_name, 0, 4)"
                    # Execute the query
                    $dbDiskUsage = $Server.Query($query)

                    # Get the free space for each drive
                    $result = $Server.Query("xp_fixeddrives")
                    $MbFreeColName = $result[0].psobject.Properties.Name[1]
                    $diskFreeSpace = $result | Select-Object Drive, @{ Name = 'FreeMB'; Expression = { $_.$MbFreeColName } }

                    # Loop through each of the drives to see if the size of files on that
                    # particular disk do not exceed the free space of that disk
                    foreach ($d in $dbDiskUsage) {
                        $freeSpace = $diskFreeSpace | Where-Object { $_.Drive -eq $d.Drive.Trim(':\') } | Select-Object FreeMB
                        if ($d.SizeMB -gt $freeSpace.FreeMB) {
                            # Set the success flag
                            $success = $false

                            Stop-Function -Message "The available space may not be sufficient to continue the process. Please use -Force to try anyway." -Target $instance -Continue
                            return
                        }
                    }
                }

                # Create the start time
                $start = Get-Date

                # Check if the function needs to continue
                if ($success) {

                    # Get the database files before all the alterations
                    Write-Message -Message "Retrieving data files before data move" -Level Verbose
                    Write-Message -Message "Processing database $db" -Level Verbose

                    # Check the datafiles of the database
                    $dataFiles = Get-DbaDbFile -SqlInstance $instance -Database $db | Where-Object { $_.TypeDescription -eq 'ROWS' }
                    if ($dataFiles.Count -eq 1) {
                        # Set the success flag
                        $success = $false

                        Stop-Function -Message "Database $db only has one data file. Please add a data file to balance out the data" -Target $instance -Continue
                    }

                    # Check the tables parameter
                    if ($Table) {
                        if ($Table -notin $db.Table) {
                            # Set the success flag
                            $success = $false

                            Stop-Function -Message "One or more tables cannot be found in database $db on instance $instance" -Target $instance -Continue
                        }

                        $tableCollection = $db.Tables | Where-Object { $_.Name -in $Table }
                    } else {
                        $tableCollection = $db.Tables
                    }

                    # Get the database file groups and check the aount of data files
                    Write-Message -Message "Retrieving file groups" -Level Verbose
                    $fileGroups = $Server.Databases[$db.Name].FileGroups

                    # ARray to hold the file groups with properties
                    $balanceableTables = @()

                    # Loop through each of the file groups

                    foreach ($fg in $fileGroups) {

                        # If there is less than 2 files balancing out data is not possible
                        if (($fg.Files.Count -ge 2) -and ($fg.Readonly -eq $false)) {
                            $balanceableTables += $fg.EnumObjects() | Where-Object { $_.GetType().Name -eq 'Table' }
                        }
                    }

                    $unsuccessfulTables = @()

                    # Loop through each of the tables
                    foreach ($tbl in $tableCollection) {

                        # Chck if the table balanceable
                        if ($tbl.Name -in $balanceableTables.Name) {

                            Write-Message -Message "Processing table $tbl" -Level Verbose

                            # Chck the tables and get the clustered indexes
                            if ($tableCollection.Indexes.Count -lt 1) {
                                # Set the success flag
                                $success = $false

                                Stop-Function -Message "Table $tbl does not contain any indexes" -Target $instance -Continue
                            } else {

                                # Get all the clustered indexes for the table
                                $clusteredIndexes = $tableCollection.Indexes | Where-Object { $_.IndexType -eq 'ClusteredIndex' }

                                if ($clusteredIndexes.Count -lt 1) {
                                    # Set the success flag
                                    $success = $false

                                    Stop-Function -Message "No clustered indexes found in table $tbl" -Target $instance -Continue
                                }
                            }

                            # Loop through each of the clustered indexes and rebuild them
                            Write-Message -Message "$($clusteredIndexes.Count) clustered index(es) found for table $tbl" -Level Verbose
                            if ($PSCmdlet.ShouldProcess("Rebuilding indexes to balance data")) {
                                foreach ($ci in $clusteredIndexes) {

                                    Write-Message -Message "Rebuilding index $($ci.Name)" -Level Verbose

                                    # Get the original index operation
                                    [bool]$originalIndexOperation = $ci.OnlineIndexOperation

                                    # Set the rebuild option to be either offline or online
                                    if ($RebuildOffline) {
                                        $ci.OnlineIndexOperation = $false
                                    } elseif ($serverVersion -ge 9 -and $supportOnlineRebuild -and -not $RebuildOffline) {
                                        Write-Message -Message "Setting the index operation for index $($ci.Name) to online" -Level Verbose
                                        $ci.OnlineIndexOperation = $true
                                    }

                                    # Rebuild the index
                                    try {
                                        Write-Message -Message "Rebuilding index $($ci.Name)" -Level Verbose
                                        $ci.Rebuild()

                                        # Set the success flag
                                        $success = $true
                                    } catch {
                                        # Set the original index operation back for the index
                                        $ci.OnlineIndexOperation = $originalIndexOperation

                                        # Set the success flag
                                        $success = $false

                                        Stop-Function -Message "Something went wrong rebuilding index $($ci.Name). `n$($_.Exception.Message)" -ErrorRecord $_ -Target $instance -Continue
                                    }

                                    # Set the original index operation back for the index
                                    Write-Message -Message "Setting the index operation for index $($ci.Name) back to the original value" -Level Verbose
                                    $ci.OnlineIndexOperation = $originalIndexOperation

                                } # foreach index

                            } # if process

                        } # if table is balanceable
                        else {
                            # Add the table to the unsuccessful array
                            $unsuccessfulTables += $tbl.Name

                            # Set the success flag
                            $success = $false

                            Write-Message -Message "Table $tbl cannot be balanced out" -Level Verbose
                        }

                    } #foreach table
                }

                # Create the end time
                $end = Get-Date

                # Create the time span
                $timespan = New-TimeSpan -Start $start -End $end
                $ts = [timespan]::fromseconds($timespan.TotalSeconds)
                $elapsed = "{0:HH:mm:ss}" -f ([datetime]$ts.Ticks)

                # Get the database files after all the alterations
                Write-Message -Message "Retrieving data files after data move" -Level Verbose
                $dataFilesEnding = Get-DbaDbFile -SqlInstance $server -Database $db.Name | Where-Object { $_.TypeDescription -eq 'ROWS' } | Select-Object ID, LogicalName, PhysicalName, Size, UsedSpace, AvailableSpace | Sort-Object ID

                [pscustomobject]@{
                    ComputerName   = $server.ComputerName
                    InstanceName   = $server.ServiceName
                    SqlInstance    = $server.DomainInstanceName
                    Database       = $db.Name
                    Start          = $start
                    End            = $end
                    Elapsed        = $elapsed
                    Success        = $success
                    Unsuccessful   = $unsuccessfulTables -join ","
                    DataFilesStart = $dataFilesStarting
                    DataFilesEnd   = $dataFilesEnding
                }

            } # foreach database

        } # end process
    }
}