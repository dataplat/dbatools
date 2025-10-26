function Copy-DbaDbTableData {
    <#
    .SYNOPSIS
        Streams table data between SQL Server instances using high-performance bulk copy operations.

    .DESCRIPTION
        Copies data between SQL Server tables using SQL Bulk Copy for maximum performance and minimal memory usage.
        Unlike Invoke-DbaQuery and Write-DbaDbTableData which buffer entire table contents in memory, this function streams data directly from source to destination.
        This approach prevents memory exhaustion when copying large tables and provides the fastest data transfer method available.
        Supports copying between different servers, databases, and schemas while preserving data integrity options like identity values, constraints, and triggers.
        Can automatically create destination tables based on source table structure, making it ideal for data migration, ETL processes, and table replication tasks.

        Note: System-versioned temporal tables require special handling. The -AutoCreateTable parameter does not support temporal table creation.
        When copying to an existing temporal table, use the -Query parameter to exclude GENERATED ALWAYS columns (e.g., ValidFrom, ValidTo).
        Temporal version history cannot be preserved as these values are system-managed.

    .PARAMETER SqlInstance
        Source SQL Server.You must have sysadmin access and server version must be SQL Server version 2000 or greater.

    .PARAMETER SqlCredential
        Login to the source instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Destination
        Target SQL Server instance where table data will be copied to. Accepts one or more SQL Server instances.
        Specify this when copying data to a different server than the source, or when doing cross-instance data transfers.

    .PARAMETER DestinationSqlCredential
        Alternative credentials for authenticating to the destination instance. Required when your current Windows credentials don't have access to the target server.
        Use this for cross-domain scenarios, SQL authentication, or when the destination requires different security context than the source.

    .PARAMETER Database
        Source database containing the table or view to copy data from. Required when not using pipeline input.
        Must exist on the source instance and your account must have read permissions on the specified objects.

    .PARAMETER DestinationDatabase
        Target database where copied data will be inserted. Defaults to the same database name as the source.
        Use this when copying data to a different database name on the destination instance or for cross-database copies within the same server.

    .PARAMETER Table
        Source table name to copy data from. Accepts 2-part ([schema].[table]) or 3-part ([database].[schema].[table]) names.
        Use square brackets for names with spaces or special characters. Cannot be used simultaneously with the View parameter.

    .PARAMETER View
        Source view name to copy data from. Accepts 2-part ([schema].[view]) or 3-part ([database].[schema].[view]) names.
        Use square brackets for names with spaces or special characters. Cannot be used simultaneously with the Table parameter.

    .PARAMETER DestinationTable
        Target table name where data will be inserted. Defaults to the same name as the source table.
        Use this when copying to a table with a different name or schema, or when specifying 3-part names for cross-database operations.

    .PARAMETER Query
        Custom SQL SELECT query to use as the data source instead of copying the entire table or view. Supports 3 or 4-part object names.
        Use this when you need to filter rows, join multiple tables, or transform data during the copy operation. Still requires specifying a Table or View parameter for metadata purposes.

    .PARAMETER AutoCreateTable
        Automatically creates the destination table if it doesn't exist, using the same structure as the source table.
        Essential for initial data migrations or when copying to new environments where destination tables haven't been created yet.

    .PARAMETER BatchSize
        Number of rows to process in each bulk copy batch. Defaults to 50000 rows.
        Reduce this value for memory-constrained systems or increase it for faster transfers when copying large tables with sufficient memory.

    .PARAMETER NotifyAfter
        Number of rows to process before displaying progress updates. Defaults to 5000 rows.
        Set to a lower value for frequent updates on small tables or higher for less verbose output on large table copies.

    .PARAMETER NoTableLock
        Disables the default table lock (TABLOCK) on the destination table during bulk copy operations.
        Use this when you need to allow concurrent read access to the destination table, though it may reduce bulk copy performance.

    .PARAMETER CheckConstraints
        Enables constraint checking during bulk copy operations. By default, constraints are ignored for performance.
        Use this when data integrity validation is more important than copy speed, particularly when copying from untrusted sources.

    .PARAMETER FireTriggers
        Enables INSERT triggers to fire during bulk copy operations. By default, triggers are bypassed for performance.
        Use this when you need audit trails, logging, or other trigger-based business logic to execute during the data copy.

    .PARAMETER KeepIdentity
        Preserves the original identity column values from the source table. By default, the destination generates new identity values.
        Essential when copying reference tables or when you need to maintain exact ID relationships across systems.

    .PARAMETER KeepNulls
        Preserves NULL values from the source data instead of replacing them with destination column defaults.
        Use this when you need exact source data reproduction, especially when NULL has specific business meaning versus default values.

    .PARAMETER Truncate
        Removes all existing data from the destination table before copying new data. Prompts for confirmation unless -Force is used.
        Essential for refresh scenarios where you want to replace all destination data with current source data.

    .PARAMETER BulkCopyTimeout
        Maximum time in seconds to wait for bulk copy operations to complete. Defaults to 5000 seconds (83 minutes).
        Increase this value when copying very large tables that may take longer than the default timeout period.

    .PARAMETER CommandTimeout
        Maximum time in seconds to wait for the source query execution before timing out. Defaults to 0 (no timeout).
        Set this when querying large tables or complex views that may take longer to read than typical query timeouts allow.

    .PARAMETER InputObject
        Accepts table or view objects from Get-DbaDbTable or Get-DbaDbView for pipeline operations.
        Use this to copy multiple tables efficiently by piping them from discovery commands.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER UseDefaultFileGroup
        Creates new tables using the destination database's default filegroup instead of matching the source table's filegroup name.
        Use this when the destination database has different filegroup configurations or when you want all copied tables in the PRIMARY filegroup.

    .NOTES
        Tags: Table, Data
        Author: Simone Bizzotto (@niphlod)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Copy-DbaDbTableData

    .EXAMPLE
        PS C:\> Copy-DbaDbTableData -SqlInstance sql1 -Destination sql2 -Database dbatools_from -Table dbo.test_table

        Copies all the data from table dbo.test_table (2-part name) in database dbatools_from on sql1 to table test_table in database dbatools_from on sql2.

    .EXAMPLE
        PS C:\> Copy-DbaDbTableData -SqlInstance sql1 -Destination sql2 -Database dbatools_from -DestinationDatabase dbatools_dest -Table [Schema].[test table]

        Copies all the data from table [Schema].[test table] (2-part name) in database dbatools_from on sql1 to table [Schema].[test table] in database dbatools_dest on sql2

    .EXAMPLE
        PS C:\> Get-DbaDbTable -SqlInstance sql1 -Database tempdb -Table tb1, tb2 | Copy-DbaDbTableData -DestinationTable tb3

        Copies all data from tables tb1 and tb2 in tempdb on sql1 to tb3 in tempdb on sql1

    .EXAMPLE
        PS C:\> Get-DbaDbTable -SqlInstance sql1 -Database tempdb -Table tb1, tb2 | Copy-DbaDbTableData -Destination sql2

        Copies data from tb1 and tb2 in tempdb on sql1 to the same table in tempdb on sql2

    .EXAMPLE
        PS C:\> Copy-DbaDbTableData -SqlInstance sql1 -Destination sql2 -Database dbatools_from -Table test_table -KeepIdentity -Truncate

        Copies all the data in table test_table from sql1 to sql2, using the database dbatools_from, keeping identity columns and truncating the destination

    .EXAMPLE
        PS C:\> $params = @{
        >> SqlInstance = 'sql1'
        >> Destination = 'sql2'
        >> Database = 'dbatools_from'
        >> DestinationDatabase = 'dbatools_dest'
        >> Table = '[Schema].[Table]'
        >> DestinationTable = '[dbo].[Table.Copy]'
        >> KeepIdentity = $true
        >> KeepNulls = $true
        >> Truncate = $true
        >> BatchSize = 10000
        >> }
        >>
        PS C:\> Copy-DbaDbTableData @params

        Copies all the data from table [Schema].[Table] (2-part name) in database dbatools_from on sql1 to table [dbo].[Table.Copy] in database dbatools_dest on sql2
        Keeps identity columns and Nulls, truncates the destination and processes in BatchSize of 10000.

    .EXAMPLE
        PS C:\> $params = @{
        >> SqlInstance = 'server1'
        >> Destination = 'server1'
        >> Database = 'AdventureWorks2017'
        >> DestinationDatabase = 'AdventureWorks2017'
        >> DestinationTable = '[AdventureWorks2017].[Person].[EmailPromotion]'
        >> BatchSize = 10000
        >> Table = '[OtherDb].[Person].[Person]'
        >> Query = "SELECT * FROM [OtherDb].[Person].[Person] where EmailPromotion = 1"
        >> }
        >>
        PS C:\> Copy-DbaDbTableData @params

        Copies data returned from the query on server1 into the AdventureWorks2017 on server1, using a 3-part name for the DestinationTable parameter. Copy is processed in BatchSize of 10000 rows.

        See the Query param documentation for more details.

    .EXAMPLE
       Copy-DbaDbTableData -SqlInstance sql1 -Database tempdb -View [tempdb].[dbo].[vw1] -DestinationTable [SampleDb].[SampleSchema].[SampleTable] -AutoCreateTable

       Copies all data from [tempdb].[dbo].[vw1] (3-part name) view on instance sql1 to an auto-created table [SampleDb].[SampleSchema].[SampleTable] on instance sql1
    #>
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess)]
    param (
        [DbaInstanceParameter]$SqlInstance,
        [PSCredential]$SqlCredential,
        [DbaInstanceParameter[]]$Destination,
        [PSCredential]$DestinationSqlCredential,
        [string]$Database,
        [string]$DestinationDatabase,
        [string[]]$Table,
        [string[]]$View, # Copy-DbaDbTableData and Copy-DbaDbViewData are consolidated to reduce maintenance cost, so this param is specific to calls of Copy-DbaDbViewData
        [string]$Query,
        [switch]$AutoCreateTable,
        [int]$BatchSize = 50000,
        [int]$NotifyAfter = 5000,
        [string]$DestinationTable,
        [switch]$NoTableLock,
        [switch]$CheckConstraints,
        [switch]$FireTriggers,
        [switch]$KeepIdentity,
        [switch]$KeepNulls,
        [switch]$Truncate,
        [int]$BulkCopyTimeout = 5000,
        [int]$CommandTimeout = 0,
        [switch]$UseDefaultFileGroup,
        [Parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.TableViewBase[]]$InputObject,
        [switch]$EnableException
    )

    begin {

        $bulkCopyOptions = 0
        $options = "TableLock", "CheckConstraints", "FireTriggers", "KeepIdentity", "KeepNulls", "Default"

        foreach ($option in $options) {
            $optionValue = Get-Variable $option -ValueOnly -ErrorAction SilentlyContinue
            if ($option -eq "TableLock" -and (!$NoTableLock)) {
                $optionValue = $true
            }
            if ($optionValue -eq $true) {
                $bulkCopyOptions += $([Microsoft.Data.SqlClient.SqlBulkCopyOptions]::$option).value__
            }
        }

        $defaultFGScriptingOption = @{
            ScriptingOptionsObject = $(
                $so = New-DbaScriptingOption
                $so.NoFileGroup = $UseDefaultFileGroup
                $so
            )
        }
    }

    process {
        if ((Test-Bound -Not -ParameterName InputObject) -and ((Test-Bound -Not -ParameterName SqlInstance, Database -And) -or (Test-Bound -Not -ParameterName Table, View))) {
            Stop-Function -Message "You must pipe in a table or specify SqlInstance, Database and [View|Table]."
            return
        }

        # determine if -Table or -View was used
        $SourceObject = $Table
        if ((Test-Bound -ParameterName View) -and (Test-Bound -ParameterName Table)) {
            Stop-Function -Message "Only one of [View|Table] may be specified."
            return
        } elseif ( Test-Bound -ParameterName View ) {
            $SourceObject = $View
        }

        if ($SqlInstance) {
            if ((Test-Bound -Not -ParameterName Destination, DestinationDatabase, DestinationTable)) {
                Stop-Function -Message "Cannot copy $SourceObject into itself. One of the parameters Destination (Server), DestinationDatabase, or DestinationTable must be specified " -Target $SourceObject
                return
            }

            try {
                # Ensuring that the default db connection is to the passed in $Database instead of the master db. This way callers don't have to remember to do 3 part queries.
                $server = Connect-DbaInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $SqlInstance
                return
            }

            try {
                foreach ($sourceDataObject in $SourceObject) {
                    $dbObject = $null

                    if ( Test-Bound -ParameterName View ) {
                        $dbObject = Get-DbaDbView -SqlInstance $server -View $sourceDataObject -Database $Database -EnableException -Verbose:$false
                    } else {
                        $dbObject = Get-DbaDbTable -SqlInstance $server -Table $sourceDataObject -Database $Database -EnableException -Verbose:$false
                    }

                    if ($dbObject.Count -eq 1) {
                        $InputObject += $dbObject
                    } else {
                        Stop-Function -Message "The object $sourceDataObject matches $($dbObject.Count) objects. Unable to determine which object to copy" -Continue
                    }
                }
            } catch {
                Stop-Function -Message "Unable to determine source : $SourceObject"
                return
            }
        }

        foreach ($sqlObject in $InputObject) {
            $Database = $sqlObject.Parent.Name
            $server = $sqlObject.Parent.Parent

            if ((Test-Bound -Not -ParameterName DestinationTable)) {
                $DestinationTable = '[' + $sqlObject.Schema + '].[' + $sqlObject.Name + ']'
            }

            $newTableParts = Get-ObjectNameParts -ObjectName $DestinationTable
            #using FQTN to determine database name
            if ($newTableParts.Database) {
                $DestinationDatabase = $newTableParts.Database
            } elseif ((Test-Bound -Not -ParameterName DestinationDatabase)) {
                $DestinationDatabase = $Database
            }

            if (-not $Destination) {
                $Destination = $server
            }

            foreach ($destinstance in $Destination) {
                try {
                    $destServer = Connect-DbaInstance -SqlInstance $destinstance -SqlCredential $DestinationSqlCredential -Database $DestinationDatabase
                } catch {
                    Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $destinstance -Continue
                }

                if ($DestinationDatabase -notin $destServer.Databases.Name) {
                    Stop-Function -Message "Database $DestinationDatabase doesn't exist on $destServer"
                    return
                }

                $desttable = Get-DbaDbTable -SqlInstance $destServer -Table $DestinationTable -Database $DestinationDatabase -Verbose:$false | Select-Object -First 1
                if (-not $desttable -and $AutoCreateTable) {
                    try {
                        $tablescript = $null
                        $schemaNameToReplace = $null
                        $tableNameToReplace = $null
                        if ( Test-Bound -ParameterName View ) {
                            #select view into tempdb to generate script
                            $tempTableName = "$($sqlObject.Name)_table"
                            $createquery = "SELECT * INTO tempdb..$tempTableName FROM [$($sqlObject.Schema)].[$($sqlObject.Name)] WHERE 1=2"
                            Invoke-DbaQuery -SqlInstance $server -Database $Database -Query $createquery -EnableException
                            #refreshing table list to make sure get-dbadbtable will find the new table
                            $server.Databases['tempdb'].Tables.Refresh($true)
                            $tempTable = Get-DbaDbTable -SqlInstance $server -Database tempdb -Table $tempTableName
                            # need these for generating the script of the table and then replacing the schema and name
                            $schemaNameToReplace = $tempTable.Schema
                            $tableNameToReplace = $tempTable.Name
                            $tablescript = $tempTable |
                                Export-DbaScript @defaultFGScriptingOption -Passthru |
                                Out-String
                            # cleanup
                            Invoke-DbaQuery -SqlInstance $server -Database $Database -Query "DROP TABLE tempdb..$tempTableName" -EnableException
                        } else {
                            $tablescript = $sqlObject |
                                Export-DbaScript @defaultFGScriptingOption -Passthru |
                                Out-String
                            $schemaNameToReplace = $sqlObject.Schema
                            $tableNameToReplace = $sqlObject.Name
                        }

                        #replacing table name
                        if ($newTableParts.Name) {
                            $rX = "(CREATE|ALTER)( TABLE \[$([regex]::Escape($schemaNameToReplace))\]\.\[)$([regex]::Escape($tableNameToReplace))(\])"
                            $tablescript = $tablescript -replace $rX, "`${1}`${2}$($newTableParts.Name)`${3}"
                        }
                        #replacing table schema
                        if ($newTableParts.Schema) {
                            $rX = "(CREATE|ALTER)( TABLE \[)$([regex]::Escape($schemaNameToReplace))(\]\.\[$([regex]::Escape($newTableParts.Name))\])"
                            $tablescript = $tablescript -replace $rX, "`${1}`${2}$($newTableParts.Schema)`${3}"
                        }

                        if ($PSCmdlet.ShouldProcess($destServer, "Creating new table: $DestinationTable")) {
                            Write-Message -Message "New table script: $tablescript" -Level VeryVerbose
                            Invoke-DbaQuery -SqlInstance $destServer -Database $DestinationDatabase -Query "$tablescript" -EnableException # add some string assurance there
                            #table list was updated, let's grab a fresh one
                            $destServer.Databases[$DestinationDatabase].Tables.Refresh()
                            $desttable = Get-DbaDbTable -SqlInstance $destServer -Table $DestinationTable -Database $DestinationDatabase -Verbose:$false
                            Write-Message -Message "New table created: $desttable" -Level Verbose
                        }
                    } catch {
                        Stop-Function -Message "Unable to determine destination table: $DestinationTable" -ErrorRecord $_
                        return
                    }
                }
                if (-not $desttable) {
                    Stop-Function -Message "Table $DestinationTable cannot be found in $DestinationDatabase. Use -AutoCreateTable to automatically create the table on the destination." -Continue
                }

                $connstring = $destServer.ConnectionContext.ConnectionString

                if ($server.DatabaseEngineType -eq "SqlAzureDatabase") {
                    $fqtnfrom = "$sqlObject"
                } else {
                    $fqtnfrom = "$($server.Databases[$Database]).$sqlObject"
                }

                if ($destServer.DatabaseEngineType -eq "SqlAzureDatabase") {
                    $fqtndest = "$desttable"
                } else {
                    $fqtndest = "$($destServer.Databases[$DestinationDatabase]).$desttable"
                }

                if ($fqtndest -eq $fqtnfrom -and $server.Name -eq $destServer.Name -and (Test-Bound -ParameterName Query -Not)) {
                    Stop-Function -Message "Cannot copy $fqtnfrom on $($server.Name) into $fqtndest on ($destServer.Name). Source and Destination must be different " -Target $Table
                    return
                }


                if (Test-Bound -ParameterName Query -Not) {
                    $Query = "SELECT * FROM $fqtnfrom"
                    $sourceLabel = $fqtnfrom
                } else {
                    $sourceLabel = "Query"
                }
                try {
                    if ($Truncate -eq $true) {
                        if ($Pscmdlet.ShouldProcess($destServer, "Truncating table $fqtndest")) {
                            Invoke-DbaQuery -SqlInstance $destServer -Database $DestinationDatabase -Query "TRUNCATE TABLE $fqtndest" -EnableException
                        }
                    }
                    if ($Pscmdlet.ShouldProcess($server, "Copy data from $sourceLabel")) {
                        $cmd = $server.ConnectionContext.SqlConnectionObject.CreateCommand()
                        $cmd.CommandTimeout = $CommandTimeout
                        $cmd.CommandText = $Query
                        if ($server.ConnectionContext.IsOpen -eq $false) {
                            $server.ConnectionContext.SqlConnectionObject.Open()
                        }
                        $bulkCopy = New-Object Microsoft.Data.SqlClient.SqlBulkCopy("$connstring;Database=$DestinationDatabase", $bulkCopyOptions)
                        $bulkCopy.DestinationTableName = $fqtndest
                        $bulkCopy.EnableStreaming = $true
                        $bulkCopy.BatchSize = $BatchSize
                        $bulkCopy.NotifyAfter = $NotifyAfter
                        $bulkCopy.BulkCopyTimeout = $BulkCopyTimeout

                        # The legacy bulk copy library uses a 4 byte integer to track the RowsCopied, so the only option is to use
                        # integer wrap so that copy operations of row counts greater than [int32]::MaxValue will report accurate numbers.
                        # See https://github.com/dataplat/dbatools/issues/6927 for more details
                        $script:prevRowsCopied = [int64]0
                        $script:totalRowsCopied = [int64]0

                        $elapsed = [System.Diagnostics.Stopwatch]::StartNew()
                        # Add RowCount output
                        $bulkCopy.Add_SqlRowsCopied( {

                                $script:totalRowsCopied += (Get-AdjustedTotalRowsCopied -ReportedRowsCopied $args[1].RowsCopied -PreviousRowsCopied $script:prevRowsCopied).NewRowCountAdded

                                $tstamp = $(Get-Date -format 'yyyyMMddHHmmss')
                                Write-Message -Level Verbose -Message "[$tstamp] The bulk copy library reported RowsCopied = $($args[1].RowsCopied). The previous RowsCopied = $($script:prevRowsCopied). The adjusted total rows copied = $($script:totalRowsCopied)"

                                $RowsPerSec = [math]::Round($script:totalRowsCopied / $elapsed.ElapsedMilliseconds * 1000.0, 1)
                                Write-Progress -Id 1 -Activity "Inserting rows" -Status ([System.String]::Format("{0} rows ({1} rows/sec)", $script:totalRowsCopied, $RowsPerSec))

                                # save the previous count of rows copied to be used on the next event notification
                                $script:prevRowsCopied = $args[1].RowsCopied
                            })
                    }

                    if ($Pscmdlet.ShouldProcess($destServer, "Writing rows to $fqtndest")) {
                        $reader = $cmd.ExecuteReader()
                        $bulkCopy.WriteToServer($reader)
                        $finalRowCountReported = Get-BulkRowsCopiedCount $bulkCopy

                        $script:totalRowsCopied += (Get-AdjustedTotalRowsCopied -ReportedRowsCopied $finalRowCountReported -PreviousRowsCopied $script:prevRowsCopied).NewRowCountAdded

                        $RowsTotal = $script:totalRowsCopied
                        $TotalTime = [math]::Round($elapsed.Elapsed.TotalSeconds, 1)
                        Write-Message -Level Verbose -Message "$RowsTotal rows inserted in $TotalTime sec"
                        if ($RowsTotal -gt 0) {
                            Write-Progress -Id 1 -Activity "Inserting rows" -Status "Complete" -Completed
                        }

                        $server.ConnectionContext.SqlConnectionObject.Close()
                        $bulkCopy.Close()
                        $bulkCopy.Dispose()
                        $reader.Close()

                        [PSCustomObject]@{
                            SourceInstance        = $server.Name
                            SourceDatabase        = $Database
                            SourceDatabaseID      = $sqlObject.Parent.ID
                            SourceSchema          = $sqlObject.Schema
                            SourceTable           = $sqlObject.Name
                            DestinationInstance   = $destServer.Name
                            DestinationDatabase   = $DestinationDatabase
                            DestinationDatabaseID = $desttable.Parent.ID
                            DestinationSchema     = $desttable.Schema
                            DestinationTable      = $desttable.Name
                            RowsCopied            = $RowsTotal
                            Elapsed               = [prettytimespan]$elapsed.Elapsed
                        }
                    }
                } catch {
                    Stop-Function -Message "Something went wrong" -ErrorRecord $_ -Target $server -continue
                }
            }
        }
    }
}