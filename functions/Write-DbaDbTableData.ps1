function Write-DbaDbTableData {
    <#
    .SYNOPSIS
        Writes data to a SQL Server Table.

    .DESCRIPTION
        Writes a .NET DataTable to a SQL Server table using SQL Bulk Copy.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The database to import the table into.

    .PARAMETER InputObject
        This is the DataTable (or data row) to import to SQL Server.

    .PARAMETER Table
        The table name to import data into. You can specify a one, two, or three part table name. If you specify a one or two part name, you must also use -Database.

        If the table does not exist, you can use -AutoCreateTable to automatically create the table with inefficient data types.

        If the object has special characters please wrap them in square brackets [ ].
        Using dbo.First.Table will try to import to a table named 'Table' on schema 'First' and database 'dbo'.
        The correct way to import to a table named 'First.Table' on schema 'dbo' is by passing dbo.[First.Table]
        Any actual usage of the ] must be escaped by duplicating the ] character.
        The correct way to import to a table Name] in schema Schema.Name is by passing [Schema.Name].[Name]]]

    .PARAMETER Schema
        Defaults to dbo if no schema is specified.

    .PARAMETER BatchSize
        The BatchSize for the import defaults to 5000.

    .PARAMETER NotifyAfter
        Sets the option to show the notification after so many rows of import

    .PARAMETER AutoCreateTable
        If this switch is enabled, the table will be created if it does not already exist. The table will be created with sub-optimal data types such as nvarchar(max)

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
        Value in seconds for the BulkCopy operations timeout. The default is 30 seconds.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER UseDynamicStringLength
        By default, all string columns will be NVARCHAR(MAX).
        If this switch is enabled, all columns will get the length specified by the column's MaxLength property (if specified)

    .NOTES
        Tags: DataTable, Insert
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
        PS C:\> $dataset = Invoke-DbaQuery -SqlInstance 'localhost,1417' -SqlCredential $containerCred -Database master -Query $query
        PS C:\> $dataset | Select-Object name, create_date, @{L="owner_sid";E={$_."owner_sid"}} | Write-DbaDbTableData -SqlInstance 'localhost,1417' -SqlCredential $containerCred -Database tempdb -Table myTestData -Schema dbo -AutoCreateTable

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
        PS C:\> $passwd = ConvertTo-SecureString "P@ssw0rd" -AsPlainText -Force
        PS C:\> $AzureCredential = New-Object System.Management.Automation.PSCredential("AzureAccount"),$passwd)
        PS C:\> $DataTable = Import-Csv C:\temp\customers.csv
        PS C:\> Write-DbaDbTableData -SqlInstance AzureDB.database.windows.net -InputObject $DataTable -Database mydb -Table customers -KeepNulls -Credential $AzureCredential -BulkCopyTimeOut 300

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
        [int]$bulkCopyTimeOut = 5000,
        [switch]$EnableException,
        [switch]$UseDynamicStringLength
    )

    begin {
        # Null variable to make sure upper-scope variables don't interfere later
        $steppablePipeline = $null

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
                foreach ($prop in $DataTable.Columns.ColumnName) {
                    $null = $bulkCopy.ColumnMappings.Add($prop, $prop)
                }

                $bulkCopy.WriteToServer($DataTable)
                if ($rowCount -is [int]) {
                    Write-Progress -id 1 -activity "Inserting $rowCount rows" -status "Complete" -Completed
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

        # Getting the total rows copied is a challenge. Use SqlBulkCopyExtension.
        # http://stackoverflow.com/questions/1188384/sqlbulkcopy-row-count-when-complete

        $sourcecode = 'namespace System.Data.SqlClient {
            using Reflection;

            public static class SqlBulkCopyExtension
            {
                const String _rowsCopiedFieldName = "_rowsCopied";
                static FieldInfo _rowsCopiedField = null;

                public static int RowsCopiedCount(this SqlBulkCopy bulkCopy)
                {
                    if (_rowsCopiedField == null) _rowsCopiedField = typeof(SqlBulkCopy).GetField(_rowsCopiedFieldName, BindingFlags.NonPublic | BindingFlags.GetField | BindingFlags.Instance);
                    return (int)_rowsCopiedField.GetValue(bulkCopy);
                }
            }
        }'
        # Load the basics
        if (-not $script:core) {
            try {
                Add-Type -ReferencedAssemblies System.Data.dll -TypeDefinition $sourcecode -ErrorAction Stop
            } catch {
                $null = 1
            }
        }
        #endregion Prepare type for bulk copy

        #region Resolve Full Qualified Table Name
        $fqtnObj = Get-ObjectNameParts -ObjectName $Table

        if ($fqtnObj.$parsed) {
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

        $tableName = $fqtnObj.Name

        $quotedFQTN = New-Object System.Text.StringBuilder

        [void]$quotedFQTN.Append( '[' )
        if ($databaseName.Contains(']')) {
            [void]$quotedFQTN.Append( $databaseName.Replace(']', ']]') )
        } else {
            [void]$quotedFQTN.Append( $databaseName )
        }
        [void]$quotedFQTN.Append( '].' )

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

        #region Connect to server and get database
        try {
            $server = Connect-SqlInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
        } catch {
            Stop-Function -Message "Error occurred while establishing connection to $SqlInstance" -Category ConnectionError -ErrorRecord $_ -Target $SqlInstance
            return
        }

        if ($server.ServerType -eq 'SqlAzureDatabase') {
            <#
                For some reasons SMO wants an initial pull when talking to Azure Sql DB
                This will throw and be caught, and then we can continue as normal.
            #>
            try {
                $null = $server.Databases
            } catch {
                # here to avoid an empty catch
                $null = 1
            }
        }
        try {
            $databaseObject = $server.Databases[$databaseName]
            #endregion Connect to server and get database

            #region Prepare database and bulk operations
            if ($null -eq $databaseObject) {
                Stop-Function -Message "$databaseName does not exist." -Target $SqlInstance
                return
            }

            $databaseObject.Tables.Refresh()
            if ($schemaName -notin $databaseObject.Schemas.Name) {
                Stop-Function -Message "Schema does not exist."
                return
            }

            $tableExists = ($tableName -in $databaseObject.Tables.Name) -and ($databaseObject.Tables.Schema -eq $schemaName)
        } catch {
            Stop-Function -Message "Failure" -ErrorRecord $_ -Continue
        }

        if ((-not $tableExists) -and (-not $AutoCreateTable)) {
            Stop-Function -Message "Table does not exist and automatic creation of the table has not been selected. Specify the '-AutoCreateTable'-parameter to generate a suitable table."
            return
        }

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

        if ($server.isAzure) {
            # will for sure have the database in connstring
            $bulkCopy = New-Object Data.SqlClient.SqlBulkCopy($server.ConnectionContext.ConnectionString, $bulkCopyOptions)
        } else {
            $bulkCopy = New-Object Data.SqlClient.SqlBulkCopy("$($server.ConnectionContext.ConnectionString);Database=$databaseName", $bulkCopyOptions)
        }
        $bulkCopy.DestinationTableName = $fqtn
        $bulkCopy.BatchSize = $BatchSize
        $bulkCopy.NotifyAfter = $NotifyAfter
        $bulkCopy.BulkCopyTimeOut = $BulkCopyTimeOut

        $elapsed = [System.Diagnostics.Stopwatch]::StartNew()
        # Add RowCount output
        $bulkCopy.Add_SqlRowsCopied( {
                $script:totalRows = $args[1].RowsCopied
                $percent = [int](($script:totalRows / $rowCount) * 100)
                $timeTaken = [math]::Round($elapsed.Elapsed.TotalSeconds, 1)
                Write-Progress -id 1 -activity "Inserting $rowCount rows." -PercentComplete $percent -Status ([System.String]::Format("Progress: {0} rows ({1}%) in {2} seconds", $script:totalRows, $percent, $timeTaken))
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
        #region ConvertTo-DbaDataTable wrapper
        if ($null -ne $steppablePipeline) {
            $dataTable = $steppablePipeline.End()

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
    }
}