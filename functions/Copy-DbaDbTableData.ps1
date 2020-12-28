function Copy-DbaDbTableData {
    <#
    .SYNOPSIS
        Copies data between SQL Server tables.

    .DESCRIPTION
        Copies data between SQL Server tables using SQL Bulk Copy.
        The same can be achieved also using Invoke-DbaQuery and Write-DbaDbTableData but it will buffer the contents of that table in memory of the machine running the commands.
        This function prevents that by streaming a copy of the data in the most speedy and least resource-intensive way.

    .PARAMETER SqlInstance
        Source SQL Server.You must have sysadmin access and server version must be SQL Server version 2000 or greater.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Destination
        Destination Sql Server. You must have sysadmin access and server version must be SQL Server version 2000 or greater.

    .PARAMETER DestinationSqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The database to copy the table from.

    .PARAMETER DestinationDatabase
        The database to copy the table to. If not specified, it is assumed to be the same of Database

    .PARAMETER Table
        Specify a table to use as a source. You can specify a 2 or 3 part name.
        If the object has special characters please wrap them in square brackets.

        Note: Cannot specify a view if a table value is provided

    .PARAMETER View
        Specify a view to use as a source. You can specify a 2 or 3 part name (see examples).
        If the object has special characters please wrap them in square brackets.

        Note: Cannot specify a table if a view value is provided

    .PARAMETER DestinationTable
        The table you want to use as destination. If not specified, it is assumed to be the same of Table

    .PARAMETER Query
        Define a query to use as a source. Note: 3 or 4 part object names may be used (see examples)
        Ensure to select all required columns.
        Calculated Columns or columns with default values may be excluded.

        Note: The workflow in the command requires that a valid -Table or -View parameter value be specified.

    .PARAMETER AutoCreateTable
        Creates the destination table if it does not already exist, based off of the "Export..." script of the source table.

    .PARAMETER BatchSize
        The BatchSize for the import defaults to 50000.

    .PARAMETER NotifyAfter
        Sets the option to show the notification after so many rows of import. The default is 5000 rows.

    .PARAMETER NoTableLock
        If this switch is enabled, a table lock (TABLOCK) will not be placed on the destination table. By default, this operation will lock the destination table while running.

    .PARAMETER CheckConstraints
        If this switch is enabled, the SqlBulkCopy option to process check constraints will be enabled.

        Per Microsoft "Check constraints while data is being inserted. By default, constraints are not checked."

    .PARAMETER FireTriggers
        If this switch is enabled, the SqlBulkCopy option to fire insert triggers will be enabled.

        Per Microsoft "When specified, cause the server to fire the insert triggers for the rows being inserted into the Database."

    .PARAMETER KeepIdentity
        If this switch is enabled, the SqlBulkCopy option to preserve source identity values will be enabled.

        Per Microsoft "Preserve source identity values. When not specified, identity values are assigned by the destination."

    .PARAMETER KeepNulls
        If this switch is enabled, the SqlBulkCopy option to preserve NULL values will be enabled.

        Per Microsoft "Preserve null values in the destination table regardless of the settings for default values. When not specified, null values are replaced by default values where applicable."

    .PARAMETER Truncate
        If this switch is enabled, the destination table will be truncated after prompting for confirmation.

    .PARAMETER BulkCopyTimeOut
        Value in seconds for the BulkCopy operations timeout. The default is 5000 seconds.

    .PARAMETER InputObject
        Enables piping of Table objects from Get-DbaDbTable

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Migration
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
        >> Table = '[AdventureWorks2017].[Person].[EmailPromotion]'
        >> BatchSize = 10000
        >> Query = "SELECT * FROM [OtherDb].[Person].[Person] where EmailPromotion = 1"
        >> }
        >>
        PS C:\> Copy-DbaDbTableData @params

        Copies data returned from the query on server1 into the AdventureWorks2017 on server1, using a 4-part name for the -Table parameter.
        See the -Query param documentation for more details.
        Copy is processed in BatchSize of 10000 rows.

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
        [int]$bulkCopyTimeOut = 5000,
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
                $bulkCopyOptions += $([Data.SqlClient.SqlBulkCopyOptions]::$option).value__
            }
        }

        #region Utility Functions
        function Get-AdjustedTotalRowsCopied {
            <#
            .SYNOPSIS
                The legacy bulk copy library still uses a 4 byte integer to track the number of rows copied. That 4 byte integer is subject to overflow/wraparound
                if the number of rows copied is greater than an integer can support. The SqlRowsCopiedEventArgs.RowsCopied property is defined as an Int64
                but a 4 byte integer is used in the underlying legacy library. See https://github.com/sqlcollaborative/dbatools/issues/6927 for more details.

            .DESCRIPTION
                Determines the accurate total rows copied even if the bulkcopy.RowsCopied has experienced integer wrap.

            .PARAMETER ReportedRowsCopied
                The number of rows copied as reported by the bulk copy library (i.e. https://docs.microsoft.com/en-us/dotnet/api/system.data.sqlclient.sqlrowscopiedeventargs.rowscopied)

            .PARAMETER PreviousRowsCopied
                The previous number of rows reported by the bulk copy library.
        #>
            [CmdletBinding()]
            param (
                $ReportedRowsCopied,
                $PreviousRowsCopied
            )

            $newRowCountAdded = 0

            if ($ReportedRowsCopied -gt 0) {
                if ($PreviousRowsCopied -ge 0) {
                    $newRowCountAdded = $ReportedRowsCopied - $PreviousRowsCopied
                } else {
                    # integer wrap just changed from negative to positive
                    $newRowCountAdded = [math]::Abs($PreviousRowsCopied) + $ReportedRowsCopied
                }
            } elseif ($ReportedRowsCopied -lt 0) {
                if ($PreviousRowsCopied -ge 0) {
                    # integer wrap just changed from positive to negative
                    $newRowCountAdded = ([int32]::MaxValue - $PreviousRowsCopied) + [math]::Abs(([int32]::MinValue - ($ReportedRowsCopied))) + 1
                } else {
                    $newRowCountAdded = [math]::Abs($PreviousRowsCopied) - [math]::Abs($ReportedRowsCopied)
                }
            }

            [pscustomobject]@{
                NewRowCountAdded = $newRowCountAdded
            }
        }
    }

    process {
        if ((Test-Bound -Not -ParameterName Table, View, SqlInstance) -and (Test-Bound -Not -ParameterName InputObject)) {
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
            if ((Test-Bound -Not -ParameterName Database)) {
                Stop-Function -Message "Database is required when passing a SqlInstance" -Target $SourceObject
                return
            }

            if ((Test-Bound -Not -ParameterName Destination, DestinationDatabase, DestinationTable)) {
                Stop-Function -Message "Cannot copy $SourceObject into itself. One of the parameters Destination (Server), DestinationDatabase, or DestinationTable must be specified " -Target $SourceObject
                return
            }

            try {
                # Ensuring that the default db connection is to the passed in $Database instead of the master db. This way callers don't have to remember to do 3 part queries.
                $server = Connect-SqlInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $SqlInstance and database $Database" -Category ConnectionError -ErrorRecord $_ -Target $SqlInstance
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

            foreach ($destinationserver in $Destination) {
                try {
                    $destServer = Connect-SqlInstance -SqlInstance $destinationserver -SqlCredential $DestinationSqlCredential
                } catch {
                    Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $destinationserver
                    return
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
                            $tablescript = $tempTable | Export-DbaScript -Passthru | Out-String
                            # cleanup
                            Invoke-DbaQuery -SqlInstance $server -Database $Database -Query "DROP TABLE tempdb..$tempTableName" -EnableException
                        } else {
                            $tablescript = $sqlObject | Export-DbaScript -Passthru | Out-String
                            $schemaNameToReplace = $sqlObject.Schema
                            $tableNameToReplace = $sqlObject.Name
                        }

                        #replacing table name
                        if ($newTableParts.Name) {
                            $rX = "(CREATE TABLE \[$([regex]::Escape($schemaNameToReplace))\]\.\[)$([regex]::Escape($tableNameToReplace))(\]\()"
                            $tablescript = $tablescript -replace $rX, "`$1$($newTableParts.Name)`$2"
                        }
                        #replacing table schema
                        if ($newTableParts.Schema) {
                            $rX = "(CREATE TABLE \[)$([regex]::Escape($schemaNameToReplace))(\]\.\[$([regex]::Escape($newTableParts.Name))\]\()"
                            $tablescript = $tablescript -replace $rX, "`$1$($newTableParts.Schema)`$2"
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
                        $cmd.CommandTimeout = 0
                        $cmd.CommandText = $Query
                        if ($server.ConnectionContext.IsOpen -eq $false) {
                            $server.ConnectionContext.SqlConnectionObject.Open()
                        }
                        $bulkCopy = New-Object Data.SqlClient.SqlBulkCopy("$connstring;Database=$DestinationDatabase", $bulkCopyOptions)
                        $bulkCopy.DestinationTableName = $fqtndest
                        $bulkCopy.EnableStreaming = $true
                        $bulkCopy.BatchSize = $BatchSize
                        $bulkCopy.NotifyAfter = $NotifyAfter
                        $bulkCopy.BulkCopyTimeOut = $BulkCopyTimeOut

                        # The legacy bulk copy library uses a 4 byte integer to track the RowsCopied, so the only option is to use
                        # integer wrap so that copy operations of row counts greater than [int32]::MaxValue will report accurate numbers.
                        # See https://github.com/sqlcollaborative/dbatools/issues/6927 for more details
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

                        [pscustomobject]@{
                            SourceInstance      = $server.Name
                            SourceDatabase      = $Database
                            SourceSchema        = $sqlObject.Schema
                            SourceTable         = $sqlObject.Name
                            DestinationInstance = $destServer.Name
                            DestinationDatabase = $DestinationDatabase
                            DestinationSchema   = $desttable.Schema
                            DestinationTable    = $desttable.Name
                            RowsCopied          = $RowsTotal
                            Elapsed             = [prettytimespan]$elapsed.Elapsed
                        }
                    }
                } catch {
                    Stop-Function -Message "Something went wrong" -ErrorRecord $_ -Target $server -continue
                }
            }
        }
    }
}