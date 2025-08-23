function Write-DbaDbTableData {
    <#
    .SYNOPSIS
        Performs high-speed bulk inserts of data into SQL Server tables using SqlBulkCopy.

    .DESCRIPTION
        Imports data from various sources (CSV files, DataTables, DataSets, PowerShell objects) into SQL Server tables using SqlBulkCopy for optimal performance. This command handles the heavy lifting of data type conversion from PowerShell to SQL Server, automatically creates missing tables when needed, and provides fine-grained control over bulk copy operations. Commonly used for data migration, ETL processes, and importing large datasets where INSERT statements would be too slow.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies the target database for the bulk insert operation. Required when using one or two-part table names.
        Use this when you need to target a specific database different from the default connection database.

    .PARAMETER InputObject
        Accepts various data formats including DataTable, DataSet, CSV files, or PowerShell objects for bulk insertion.
        Use DataSet for optimal performance as all records import in a single SqlBulkCopy call. DataTable also performs well but avoid piping directly as it converts to slower DataRow processing.
        PowerShell objects are automatically converted to DataTable format before import.

    .PARAMETER Table
        Specifies the destination table using one, two, or three-part naming (database.schema.table). Supports temp tables with # prefix.
        Use square brackets for special characters: [Schema.Name].[Table]] for tables containing brackets. Three-part names override the Database parameter.
        Combine with -AutoCreateTable to create missing tables, though manual table creation provides better data type control.

    .PARAMETER Schema
        Sets the schema for the destination table when not specified in the table name. Defaults to 'dbo'.
        Use this when working with non-default schemas or when security policies require specific schema targeting.

    .PARAMETER BatchSize
        Controls how many rows are sent to SQL Server in each batch operation. Defaults to 50,000 rows.
        Lower values (5,000-10,000) work better for wide tables or limited memory, while higher values improve performance for narrow tables with sufficient resources.

    .PARAMETER NotifyAfter
        Determines how frequently progress notifications appear during the import operation. Defaults to every 5,000 rows.
        Set higher for less frequent updates on large imports, or lower for more granular progress tracking on smaller datasets.

    .PARAMETER AutoCreateTable
        Automatically creates the destination table when it doesn't exist, using data types inferred from the source data.
        Convenient for quick imports but creates generic data types like NVARCHAR(MAX). For production use, manually create tables with appropriate data types and constraints.

    .PARAMETER NoTableLock
        Disables the default TABLOCK hint during bulk insert operations, allowing concurrent access to the destination table.
        Use when importing to tables that need concurrent read access, though this may reduce import performance compared to the default exclusive lock.

    .PARAMETER CheckConstraints
        Enforces check constraints during the bulk insert operation instead of the default behavior of bypassing them.
        Use when data integrity validation is critical, though this reduces import performance. Constraints are normally checked after bulk operations complete.

    .PARAMETER FireTriggers
        Executes INSERT triggers during the bulk copy operation instead of bypassing them for performance.
        Essential when triggers maintain audit trails, calculated fields, or related table updates. Significantly impacts import speed but preserves all database logic.

    .PARAMETER KeepIdentity
        Preserves identity column values from the source data instead of generating new sequential values.
        Critical for maintaining referential integrity when importing related tables or restoring data with existing identity dependencies.

    .PARAMETER KeepNulls
        Maintains NULL values from source data instead of replacing them with column default values.
        Use when NULL has specific business meaning in your data or when you need to preserve exact source data representation including missing values.

    .PARAMETER Truncate
        Removes all existing data from the destination table before performing the bulk insert operation.
        Useful for refreshing tables with new data while maintaining table structure, indexes, and permissions. Always prompts for confirmation before execution.

    .PARAMETER BulkCopyTimeOut
        Sets the maximum time in seconds to wait for the bulk copy operation to complete. Defaults to 5,000 seconds.
        Increase for very large datasets or slow storage systems. Set to 0 for unlimited timeout when importing millions of rows.

    .PARAMETER ColumnMap
        Defines custom mapping between source and destination columns using a hashtable when automatic column mapping fails.
        Use when column names differ between source and target, or when you need to import only specific columns. Format: @{SourceColumn='DestColumn'}.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER UseDynamicStringLength
        Creates string columns with lengths based on source data MaxLength property instead of defaulting to NVARCHAR(MAX).
        Improves storage efficiency and query performance when AutoCreateTable is used, but requires source data to provide accurate length information.

    .NOTES
        Tags: Table, Data, Insert
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Write-DbaDbTableData

    .EXAMPLE
        PS C:\> $DataTable = Import-Csv C:\temp\customers.csv
        PS C:\> Write-DbaDbTableData -SqlInstance sql2014 -InputObject $DataTable -Table mydb.dbo.customers

        Performs a bulk insert of all the data in customers.csv into database mydb, schema dbo, table customers. A progress bar will be shown as rows are inserted. If the destination table does not exist, the import will be halted.

    .EXAMPLE
        PS C:\> $tableName = "MyTestData"
        PS C:\> $query = "SELECT name, create_date, owner_sid FROM sys.databases"
        PS C:\> $dataset = Invoke-DbaQuery -SqlInstance 'localhost,1417' -SqlCredential $containerCred -Database master -Query $query -As DataSet
        PS C:\> $dataset | Write-DbaDbTableData -SqlInstance 'localhost,1417' -SqlCredential $containerCred -Database tempdb -Table $tableName -AutoCreateTable

        Pulls data from a SQL Server instance and then performs a bulk insert of the dataset to a new, auto-generated table tempdb.dbo.MyTestData.

    .EXAMPLE
        PS C:\> $DataTable = Import-Csv C:\temp\customers.csv
        PS C:\> Write-DbaDbTableData -SqlInstance sql2014 -InputObject $DataTable -Table mydb.dbo.customers -AutoCreateTable -Confirm

        Performs a bulk insert of all the data in customers.csv. If mydb.dbo.customers does not exist, it will be created with inefficient but forgiving DataTypes.

        Prompts for confirmation before a variety of steps.

    .EXAMPLE
        PS C:\> $DataTable = Import-Csv C:\temp\customers.csv
        PS C:\> Write-DbaDbTableData -SqlInstance sql2014 -InputObject $DataTable -Table mydb.dbo.customers -Truncate

        Performs a bulk insert of all the data in customers.csv. Prior to importing into mydb.dbo.customers, the user is informed that the table will be truncated and asks for confirmation. The user is prompted again to perform the import.

    .EXAMPLE
        PS C:\> $DataTable = Import-Csv C:\temp\customers.csv
        PS C:\> Write-DbaDbTableData -SqlInstance sql2014 -InputObject $DataTable -Database mydb -Table customers -KeepNulls

        Performs a bulk insert of all the data in customers.csv into mydb.dbo.customers. Because Schema was not specified, dbo was used. NULL values in the destination table will be preserved.

    .EXAMPLE
        PS C:\> $passwd = (Get-Credential NoUsernameNeeded).Password
        PS C:\> $AzureCredential = New-Object System.Management.Automation.PSCredential("AzureAccount"),$passwd)
        PS C:\> $DataTable = Import-Csv C:\temp\customers.csv
        PS C:\> Write-DbaDbTableData -SqlInstance AzureDB.database.windows.net -InputObject $DataTable -Database mydb -Table customers -KeepNulls -SqlCredential $AzureCredential -BulkCopyTimeOut 300

        This performs the same operation as the previous example, but against a SQL Azure Database instance using the required credentials.

    .EXAMPLE
        PS C:\> $process = Get-Process
        PS C:\> Write-DbaDbTableData -InputObject $process -SqlInstance sql2014 -Table "[[DbName]]].[Schema.With.Dots].[`"[Process]]`"]" -AutoCreateTable

        Creates a table based on the Process object with over 60 columns, converted from PowerShell data types to SQL Server data types. After the table is created a bulk insert is performed to add process information into the table
        Writes the results of Get-Process to a table named: "[Process]" in schema named: Schema.With.Dots in database named: [DbName]
        The Table name, Schema name and Database name must be wrapped in square brackets [ ]
        Special characters like " must be escaped by a ` character.
        In addition any actual instance of the ] character must be escaped by being duplicated.

        This is an example of the type conversion in action. All process properties are converted, including special types like TimeSpan. Script properties are resolved before the type conversion starts thanks to ConvertTo-DbaDataTable.

    .EXAMPLE
        PS C:\> $server = Connect-DbaInstance -SqlInstance SRV1
        PS C:\> $server.Invoke("CREATE TABLE tempdb.dbo.test (col1 INT, col2 VARCHAR(100))")
        PS C:\> $data = Invoke-DbaQuery -SqlInstance $server -Query "SELECT 123 AS value1, 'Hello world' AS value2" -As DataSet
        PS C:\> $data | Write-DbaDbTableData -SqlInstance $server -Table 'tempdb.dbo.test' -ColumnMap @{ value1 = 'col1' ; value2 = 'col2' }

        The dataset column 'value1' is inserted into SQL column 'col1' and dataset column value2 is inserted into the SQL Column 'col2'. All other columns are ignored and therefore null or default values.

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low")]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [DbaInstanceParameter]$SqlInstance,
        [ValidateNotNull()]
        [PSCredential]$SqlCredential,
        [object]$Database,
        [Parameter(Mandatory, ValueFromPipeline)]
        [Alias("DataTable")]
        [ValidateNotNull()]
        [object]$InputObject,
        [Parameter(Position = 3, Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Table,
        [Parameter(Position = 4)]
        [ValidateNotNullOrEmpty()]
        [string]$Schema = 'dbo',
        [ValidateNotNull()]
        [int]$BatchSize = 50000,
        [ValidateNotNull()]
        [int]$NotifyAfter = 5000,
        [switch]$AutoCreateTable,
        [switch]$NoTableLock,
        [switch]$CheckConstraints,
        [switch]$FireTriggers,
        [switch]$KeepIdentity,
        [switch]$KeepNulls,
        [switch]$Truncate,
        [ValidateNotNull()]
        [int]$BulkCopyTimeOut = 5000,
        [hashtable]$ColumnMap,
        [switch]$EnableException,
        [switch]$UseDynamicStringLength
    )

    begin {
        # Null variable to make sure upper-scope variables don't interfere later
        $steppablePipeline = $null

        $context = if ($SqlInstance.InputObject.ConnectionContext) {
            $SqlInstance.InputObject.ConnectionContext
        } else {
            $SqlInstance.ConnectionContext
        }
        $startedWithANonPooledConnection = [bool]$context.NonPooledConnection

        if (-not $PSBoundParameters.Database) {
            if ($context.DatabaseName) {
                $Database = $context.DatabaseName
                $PSBoundParameters.Database = $context.DatabaseName
                $databaseName = $context.DatabaseName
            } else {
                $dbname = (Invoke-DbaQuery -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Query "SELECT DB_NAME() AS dbname").dbname
                $Database = $dbname
                $PSBoundParameters.Database = $dbname
                $databaseName = $dbname
            }
        }


        #region Utility Functions
        function Invoke-BulkCopy {
            <#
            .SYNOPSIS
                Copies a datatable in bulk over to a table.

            .DESCRIPTION
                Copies a datatable in bulk over to a table.

            .PARAMETER DataTable
                The datatable to copy.

            .PARAMETER SqlInstance
                Needs not be specified. The SqlInstance targeted. For message purposes only.

            .PARAMETER Fqtn
                Needs not be specified. The fqtn written to. For message purposes only.

            .PARAMETER BulkCopy
                Needs not be specified. The bulk copy object used to perform the copy operation.
            #>
            [CmdletBinding()]
            param (
                $DataTable,
                [DbaInstance]$SqlInstance = $SqlInstance,
                [string]$Fqtn = $fqtn,
                $BulkCopy = $bulkCopy
            )
            Write-Message -Level Verbose -Message "Importing in bulk to $fqtn"

            $rowCount = $DataTable.Rows.Count
            if ($rowCount -eq 0) {
                $rowCount = 1
            }

            if ($Pscmdlet.ShouldProcess($SqlInstance, "Writing $rowCount rows to $Fqtn")) {
                if ($ColumnMap) {
                    foreach ($columnname in $ColumnMap) {
                        foreach ($key in $columnname.Keys) {
                            $null = $bulkCopy.ColumnMappings.Add($key, $columnname[$key])
                        }
                    }
                } else {
                    foreach ($prop in $DataTable.Columns.ColumnName) {
                        $null = $bulkCopy.ColumnMappings.Add($prop, $prop)
                    }
                }

                $bulkCopy.WriteToServer($DataTable)
                if ($rowCount) {
                    Write-Progress -Id 1 -Activity "Inserting $rowCount rows" -Status "Complete" -Completed
                }
            }
        }

        function New-Table {
            <#
            .SYNOPSIS
                Creates a table, based upon a DataTable.

            .DESCRIPTION
                Creates a table, based upon a DataTable.

            .PARAMETER DataTable
                The DataTable to base the table structure upon.

            .PARAMETER PStoSQLTypes
                Automatically inherits from parent.

            .PARAMETER SqlInstance
                Automatically inherits from parent.

            .PARAMETER Fqtn
                Automatically inherits from parent.

            .PARAMETER Server
                Automatically inherits from parent.

            .PARAMETER DatabaseName
                Automatically inherits from parent.

            .PARAMETER EnableException
                By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
                This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
                Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

            .PARAMETER UseDynamicStringLength
                Automatically inherits from parent.
        #>
            [CmdletBinding(SupportsShouldProcess)]
            param (
                $DataTable,
                $PStoSQLTypes = $PStoSQLTypes,
                $SqlInstance = $SqlInstance,
                $Fqtn = $fqtn,
                $Server = $server,
                $DatabaseName = $databaseName,
                [switch]$EnableException
            )

            Write-Message -Level Verbose -Message "Creating table for $fqtn"

            # Get SQL datatypes by best guess on first data row
            $sqlDataTypes = @();
            $columns = $DataTable.Columns

            if ($null -eq $columns) {
                $columns = $DataTable.Table.Columns
            }

            if ($null -eq $columns) {
                Stop-Function -Message "Unable to get column definition from input data, so AutoCreateTable is not possible"
                return
            }

            foreach ($column in $columns) {
                $sqlColumnName = $column.ColumnName

                try {
                    $columnValue = $DataTable.Rows[0].$sqlColumnName
                } catch {
                    $columnValue = $DataTable.$sqlColumnName
                }

                if ($null -eq $columnValue) {
                    $columnValue = $DataTable.$sqlColumnName
                }

                <#
                PS to SQL type conversion
                If data type exists in hash table, use the corresponding SQL type
                Else, fallback to nvarchar.
                If UseDynamicStringLength is specified, the DataColumn MaxLength is used if specified
            #>
                if ($PStoSQLTypes.Keys -contains $column.DataType) {
                    $sqlDataType = $PStoSQLTypes[$($column.DataType.toString())]
                    if ($UseDynamicStringLength -and $column.MaxLength -gt 0 -and ($column.DataType -in ("String", "System.String"))) {
                        $sqlDataType = $sqlDataType.Replace("(MAX)", "($($column.MaxLength))")
                    }
                } else {
                    $sqlDataType = "nvarchar(MAX)"
                }

                $sqlDataTypes += "[$sqlColumnName] $sqlDataType"
            }

            $sql = "BEGIN CREATE TABLE $fqtn ($($sqlDataTypes -join ' NULL,')) END"

            Write-Message -Level Debug -Message $sql

            if ($Pscmdlet.ShouldProcess($SqlInstance, "Creating table $Fqtn")) {
                try {
                    $null = $Server.Databases[$DatabaseName].Query($sql)
                } catch {
                    Stop-Function -Message "The following query failed: $sql" -ErrorRecord $_
                    return
                }
            }
        }

        #endregion Utility Functions

        #region Prepare type for bulk copy
        if (-not $Truncate) { $ConfirmPreference = "None" }

        #endregion Prepare type for bulk copy

        #region Resolve Full Qualified Table Name
        $fqtnObj = Get-ObjectNameParts -ObjectName $Table

        if (-not $fqtnObj.Parsed) {
            Stop-Function -Message "Unable to parse $($fqtnObj.InputValue) as a valid tablename."
            return
        }

        if ($null -eq $fqtnObj.Database -and $null -eq $Database) {
            Stop-Function -Message "You must specify a database or fully qualified table name."
            return
        }

        if (Test-Bound -ParameterName Database) {
            if ($null -eq $fqtnObj.Database) {
                $databaseName = "$Database"
            } else {
                if ($fqtnObj.Database -eq $Database) {
                    $databaseName = "$Database"
                } else {
                    Stop-Function -Message "The database parameter $($Database) differs from value from the fully qualified table name $($fqtnObj.Database)."
                    return
                }
            }
        } else {
            $databaseName = $fqtnObj.Database
        }

        if ($fqtnObj.Schema) {
            $schemaName = $fqtnObj.Schema
        } else {
            $schemaName = $Schema
        }

        $originalDatabaseName = $databaseName
        $tableName = $fqtnObj.Name

        $usingGlobalTempTable = $false
        if ($tableName.StartsWith('#')) {
            Write-Message -Level Verbose -Message "The table $tableName should be in tempdb.dbo so we ignore input database and schema."
            $databaseName = 'tempdb'
            $schemaName = 'dbo'
            if ($tableName.StartsWith('##')) {
                # do not disconnect the SqlInstance if using a global temp table.
                $usingGlobalTempTable = $true
            } elseif (-not $startedWithANonPooledConnection) {
                # if using a session temp table, you must also give an already created connection to be able to use it in the same session it was created in.
                Write-Message -Level Warning -Message "The temp table being created will not be usable after this command completes. Either use a global temp table, like '#${tableName}', or pass a NonPooled SqlConnection."
            }
        }

        $quotedFQTN = New-Object System.Text.StringBuilder

        #region Connect to server
        try {
            if ($startedWithANonPooledConnection) {
                if (-not $context.IsOpen) {
                    $context.SqlConnectionObject.Open()
                }
                $server = $SqlInstance.InputObject
            } else {
                $server = Connect-DbaInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $databaseName -NonPooledConnection
            }
        } catch {
            Stop-Function -Message "Error occurred while establishing connection to $SqlInstance" -Category ConnectionError -ErrorRecord $_ -Target $SqlInstance
            return
        }
        #endregion Connect to server

        #region Resolve Full Qualified Table Name
        if ($server.ServerType -ne 'SqlAzureDatabase') {
            <#
                Skip adding database name to Fully Qualified Tablename for Azure SQL DB
                Azure SQL DB does not support Three Part names
            #>
            [void]$quotedFQTN.Append( '[' )
            if ($databaseName.Contains(']')) {
                [void]$quotedFQTN.Append( $databaseName.Replace(']', ']]') )
            } else {
                [void]$quotedFQTN.Append( $databaseName )
            }
            [void]$quotedFQTN.Append( '].' )
        }

        [void]$quotedFQTN.Append( '[' )
        if ($schemaName.Contains(']')) {
            [void]$quotedFQTN.Append( $schemaName.Replace(']', ']]') )
        } else {
            [void]$quotedFQTN.Append( $schemaName )
        }
        [void]$quotedFQTN.Append( '].' )

        [void]$quotedFQTN.Append( '[' )
        if ($tableName.Contains(']')) {
            [void]$quotedFQTN.Append( $tableName.Replace(']', ']]') )
        } else {
            [void]$quotedFQTN.Append( $tableName )
        }
        [void]$quotedFQTN.Append( ']' )

        $fqtn = $quotedFQTN.ToString()
        Write-Message -Level SomewhatVerbose -Message "FQTN processed: $fqtn"
        #endregion Resolve Full Qualified Table Name

        #region Test if table exists
        if ($tableName.StartsWith('#')) {
            try {
                Write-Message -Level Verbose -Message "The table $tableName should be in tempdb and we try to find it."
                $null = $server.ConnectionContext.ExecuteScalar("SELECT TOP(1) 1 FROM [$tableName]")
                $tableExists = $true
            } catch {
                $tableExists = $false
            }
        } else {
            # We don't use SMO here because it does not work for Azure SQL Database connected with AccessToken.
            try {
                $null = $server.ConnectionContext.ExecuteScalar("SELECT TOP(1) 1 FROM $fqtn")
                $tableExists = $true
            } catch {
                $tableExists = $false
            }
        }

        if ((-not $tableExists) -and (-not $AutoCreateTable)) {
            Stop-Function -Message "Table does not exist and automatic creation of the table has not been selected. Specify the '-AutoCreateTable'-parameter to generate a suitable table."
            return
        }
        #endregion Test if table exists

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

        if ($Truncate -eq $true) {
            if ($Pscmdlet.ShouldProcess($SqlInstance, "Truncating $fqtn")) {
                try {
                    Write-Message -Level Verbose -Message "Truncating $fqtn."
                    $null = $server.Databases[$databaseName].Query("TRUNCATE TABLE $fqtn")
                } catch {
                    Write-Message -Level Warning -Message "Could not truncate $fqtn. Table may not exist or may have key constraints." -ErrorRecord $_
                }
            }
        }

        Write-Message -Level Verbose -Message "Creating SqlBulkCopy object"
        try {
            $bulkCopy = New-Object Microsoft.Data.SqlClient.SqlBulkCopy($server.ConnectionContext.SqlConnectionObject, $bulkCopyOptions, $null)
        } catch {
            $bulkCopy = New-Object Microsoft.Data.SqlClient.SqlBulkCopy($server.ConnectionContext.ConnectionString, $bulkCopyOptions)
        }

        $bulkCopy.DestinationTableName = $fqtn
        $bulkCopy.BatchSize = $BatchSize
        $bulkCopy.NotifyAfter = $NotifyAfter
        $bulkCopy.BulkCopyTimeOut = $BulkCopyTimeOut

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

                $percent = [int](($script:totalRowsCopied / $rowCount) * 100)
                $timeTaken = [math]::Round($elapsed.Elapsed.TotalSeconds, 1)
                Write-Progress -Id 1 -Activity "Inserting $rowCount rows." -PercentComplete $percent -Status ([System.String]::Format("Progress: {0} rows ({1}%) in {2} seconds", $script:totalRowsCopied, $percent, $timeTaken))

                # save the previous count of rows copied to be used on the next event notification
                $script:prevRowsCopied = $args[1].RowsCopied
            })

        $PStoSQLTypes = @{
            #PS datatype      = SQL data type
            'System.Int32'          = 'int';
            'System.UInt32'         = 'bigint';
            'System.Int16'          = 'smallint';
            'System.UInt16'         = 'int';
            'System.Int64'          = 'bigint';
            'System.UInt64'         = 'decimal(20,0)';
            'System.Decimal'        = 'decimal(38,5)';
            'System.Single'         = 'bigint';
            'System.Double'         = 'float';
            'System.Byte'           = 'tinyint';
            'System.Byte[]'         = 'varbinary(MAX)';
            'System.SByte'          = 'smallint';
            'System.TimeSpan'       = 'nvarchar(30)';
            'System.String'         = 'nvarchar(MAX)';
            'System.Char'           = 'nvarchar(1)'
            'System.DateTime'       = 'datetime2';
            'System.DateTimeOffset' = 'datetimeoffset';
            'System.Boolean'        = 'bit';
            'System.Guid'           = 'uniqueidentifier';
            'Int32'                 = 'int';
            'UInt32'                = 'bigint';
            'Int16'                 = 'smallint';
            'UInt16'                = 'int';
            'Int64'                 = 'bigint';
            'UInt64'                = 'decimal(20,0)';
            'Decimal'               = 'decimal(38,5)';
            'Single'                = 'bigint';
            'Double'                = 'float';
            'Byte'                  = 'tinyint';
            'Byte[]'                = 'varbinary(MAX)';
            'SByte'                 = 'smallint';
            'TimeSpan'              = 'nvarchar(30)';
            'String'                = 'nvarchar(MAX)';
            'Char'                  = 'nvarchar(1)'
            'DateTime'              = 'datetime2';
            'DateTimeOffset'        = 'datetimeoffset';
            'Boolean'               = 'bit';
            'Bool'                  = 'bit';
            'Guid'                  = 'uniqueidentifier';
            'int'                   = 'int';
            'long'                  = 'bigint';
        }

        $validTypes = @([System.Data.DataSet], [System.Data.DataTable], [System.Data.DataRow], [System.Data.DataRow[]])
        #endregion Prepare database and bulk operations

        #region ConvertTo-DbaDataTable wrapper
        try {
            $wrappedCmd = $ExecutionContext.InvokeCommand.GetCommand('ConvertTo-DbaDataTable', [System.Management.Automation.CommandTypes]::Function)
            $splatCDDT = @{
                TimeSpanType = (Get-DbatoolsConfigValue -FullName 'commands.Write-DbaDbTableData.timespantype' -Fallback 'TotalMilliseconds')
                SizeType     = (Get-DbatoolsConfigValue -FullName 'commands.Write-DbaDbTableData.sizetype' -Fallback 'Int64')
                IgnoreNull   = (Get-DbatoolsConfigValue -FullName 'commands.Write-DbaDbTableData.ignorenull' -Fallback $false)
                Raw          = (Get-DbatoolsConfigValue -FullName 'commands.Write-DbaDbTableData.raw' -Fallback $false)
            }
            $scriptCmd = { & $wrappedCmd @splatCDDT }
            $steppablePipeline = $scriptCmd.GetSteppablePipeline()
            $steppablePipeline.Begin($true)
        } catch {
            Stop-Function -Message "Failed to initialize "
        }
        #endregion ConvertTo-DbaDataTable wrapper
    }
    process {
        if (Test-FunctionInterrupt) { return }

        if ($null -ne $InputObject) { $inputType = $InputObject.GetType() }
        else { $inputType = $null }

        if ($inputType -eq [System.Data.DataSet]) {
            $inputData = $InputObject.Tables
            $inputType = [System.Data.DataTable[]]
        } else {
            $inputData = $InputObject
        }

        #region Scenario 1: Single valid table
        if ($inputType -in $validTypes) {
            if (-not $tableExists) {
                try {
                    New-Table -DataTable $InputObject -EnableException
                    $tableExists = $true
                } catch {
                    Stop-Function -Message "Failed to create table $fqtn" -ErrorRecord $_ -Target $SqlInstance
                    return
                }
            }

            try { Invoke-BulkCopy -DataTable $InputObject }
            catch {
                Stop-Function -Message "Failed to bulk import to $fqtn" -ErrorRecord $_ -Target $SqlInstance
            }
            return
        }
        #endregion Scenario 1: Single valid table

        foreach ($object in $inputData) {
            #region Scenario 2: Multiple valid tables
            if ($object.GetType() -in $validTypes) {
                if (-not $tableExists) {
                    try {
                        New-Table -DataTable $object -EnableException
                        $tableExists = $true
                    } catch {
                        Stop-Function -Message "Failed to create table $fqtn" -ErrorRecord $_ -Target $SqlInstance
                        return
                    }
                }

                try { Invoke-BulkCopy -DataTable $object }
                catch {
                    Stop-Function -Message "Failed to bulk import to $fqtn" -ErrorRecord $_ -Target $SqlInstance -Continue
                }
                continue
            }
            #endregion Scenario 2: Multiple valid tables

            #region Scenario 3: Invalid data types
            else {
                $null = $steppablePipeline.Process($object)
                continue
            }
            #endregion Scenario 3: Invalid data types
        }
    }
    end {
        if (Test-FunctionInterrupt) { return }
        #region ConvertTo-DbaDataTable wrapper
        $dataTable = $steppablePipeline.End()
        if ($dataTable[0].Rows.Count -gt 0) {

            if (-not $tableExists) {
                try {
                    New-Table -DataTable $dataTable[0] -EnableException
                    $tableExists = $true
                } catch {
                    Stop-Function -Message "Failed to create table $fqtn" -ErrorRecord $_ -Target $SqlInstance
                    return
                }
            }

            try { Invoke-BulkCopy -DataTable $dataTable[0] }
            catch {
                Stop-Function -Message "Failed to bulk import to $fqtn" -ErrorRecord $_ -Target $SqlInstance
            }
        }
        #endregion ConvertTo-DbaDataTable wrapper

        if ($bulkCopy) {
            $bulkCopy.Close()
            $bulkCopy.Dispose()
        }

        if (-not ($startedWithANonPooledConnection -or $usingGlobalTempTable) ) {
            # Close non-pooled connection as this is not done automatically. If it is a reused Server SMO, connection will be opened again automatically on next request.
            $null = $server | Disconnect-DbaInstance
        } elseif ($originalDatabaseName -ne $databaseName) {
            # if a temptable was created, it sets the open connection's database to tempdb indefinitely. We want to get back to the original database context at the start of this command.
            Write-Message -Level Verbose -Message "The current database has changed from the original database. switching back to the original database."
            $context.ExecuteNonQuery("use [$originalDatabaseName]")
        }
    }
}