function Copy-DbaDbTableData {
    <#
    .SYNOPSIS
        Copies data between SQL Server tables.

    .DESCRIPTION
        Copies data between SQL Server tables using SQL Bulk Copy.
        The same can be achieved also doing
        $sourcetable = Invoke-DbaQuery -SqlInstance instance1 ... -As DataTable
        Write-DbaDbTableData -SqlInstance ... -InputObject $sourcetable
        but it will force buffering the contents on the table in memory (high RAM usage for large tables).
        With this function, a streaming copy will be done in the most speedy and least resource-intensive way.

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
        Specify a table to use as a source. You can specify a two-part name or a three-part name such as db.sch.tbl.
        If the object has special characters please wrap them in square brackets [ ].
        Example: [SampleDB].[First].[Table] will try to find the table named 'Table' in the schema 'First' and the database 'SampleDB'.

    .PARAMETER View
        Specify a view to use as a source. You can specify a two-part name or a three-part name such as db.sch.vw.
        Note: Only one of -View or -Table may be specified during command invocation.
        If the object has special characters please wrap them in square brackets [ ].
        Example: [SampleDB].[First].[View] will try to find the view named 'View' in the schema 'First' and the database 'SampleDB'.

    .PARAMETER DestinationTable
        The table you want to use as destination. If not specified, it is assumed to be the same of Table

    .PARAMETER Query
        Define a query to use as a source. Note: 3 or 4 part object names may be used as described in https://docs.microsoft.com/en-us/sql/t-sql/language-elements/transact-sql-syntax-conventions-transact-sql
        Ensure to select all required columns. Calculated Columns or columns with default values may be excluded.
        Note: Even when the -Query param is used a valid -Table or -View must be specified. This is due to the workflow used in the command.

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

        Copies all the data from table dbo.test_table in database dbatools_from on sql1 to table test_table in database dbatools_from on sql2.

    .EXAMPLE
        PS C:\> Copy-DbaDbTableData -SqlInstance sql1 -Destination sql2 -Database dbatools_from -DestinationDatabase dbatools_dest -Table [Schema].[test table]

        Copies all the data from table [Schema].[test table] in database dbatools_from on sql1 to table [Schema].[test table] in database dbatools_dest on sql2

    .EXAMPLE
        PS C:\> Get-DbaDbTable -SqlInstance sql1 -Database tempdb -Table tb1, tb2 | Copy-DbaDbTableData -DestinationTable tb3

        Copies all data from tables tb1 and tb2 in tempdb on sql1 to tb3 in tempdb on sql1

    .EXAMPLE
        PS C:\> Get-DbaDbTable -SqlInstance sql1 -Database tempdb -Table tb1, tb2 | Copy-DbaDbTableData -Destination sql2

        Copies data from tbl1 in tempdb on sql1 to tbl1 in tempdb on sql2
        then
        Copies data from tbl2 in tempdb on sql1 to tbl2 in tempdb on sql2

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

        Copies all the data from table [Schema].[Table] in database dbatools_from on sql1 to table [dbo].[Table.Copy] in database dbatools_dest on sql2
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

        Copies data returned from the query on server1 into the AdventureWorks2017 on server1. Note that 3 or 4 part names can be used.
        See the -Query param documentation for more details.
        Copy is processed in BatchSize of 10000 rows.
    
    .EXAMPLE
       Copy-DbaDbTableData -SqlInstance sql1 -Database tempdb -View [tempdb].[dbo].[vw1] -DestinationTable [SampleDb].[SampleSchema].[SampleTable] -AutoCreateTable
       
       Copies all data from [tempdb].[dbo].[vw1] on instance sql1 to an auto-created table [SampleDb].[SampleSchema].[SampleTable] on instance sql1

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
                        Stop-Function -Message "The table $tbl matches $($dbObject.Count) objects. Unable to determine which object to copy" -Continue
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

                        $elapsed = [System.Diagnostics.Stopwatch]::StartNew()
                        # Add RowCount output
                        $bulkCopy.Add_SqlRowsCopied( {
                                $RowsPerSec = [math]::Round($args[1].RowsCopied / $elapsed.ElapsedMilliseconds * 1000.0, 1)
                                Write-Progress -Id 1 -Activity "Inserting rows" -Status ([System.String]::Format("{0} rows ({1} rows/sec)", $args[1].RowsCopied, $RowsPerSec))
                            })
                    }

                    if ($Pscmdlet.ShouldProcess($destServer, "Writing rows to $fqtndest")) {
                        $reader = $cmd.ExecuteReader()
                        $bulkCopy.WriteToServer($reader)
                        $RowsTotal = Get-BulkRowsCopiedCount $bulkCopy
                        $TotalTime = [math]::Round($elapsed.Elapsed.TotalSeconds, 1)
                        Write-Message -Level Verbose -Message "$RowsTotal rows inserted in $TotalTime sec"
                        if ($rowCount -is [int]) {
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
                            RowsCopied          = $rowstotal
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