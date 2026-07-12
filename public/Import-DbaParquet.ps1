function Import-DbaParquet {
    <#
    .SYNOPSIS
        Imports Parquet files into SQL Server tables using high-performance bulk copy operations.

    .DESCRIPTION
        Import-DbaParquet uses .NET's SqlBulkCopy class to efficiently load Parquet data into SQL Server tables, handling files of any size from small datasets to multi-gigabyte imports. The function wraps the entire operation in a transaction, so any failure or interruption rolls back all changes automatically.

        Parquet files are read using Parquet.NET, which provides high-performance columnar data access. Unlike CSV, Parquet files contain schema information including column names and data types, which are used automatically during import.

        When the target table doesn't exist, you can use -AutoCreateTable to create it on the fly with string columns using UTF-8 varchar(MAX) by default (or nvarchar(MAX) with -NoUtf8). For production use, create your table first with proper data types and constraints. The function intelligently maps Parquet columns to table columns by name, with fallback to ordinal position when needed.

        Column mapping lets you import specific columns or rename them during import, while schema detection can automatically place data in the correct schema based on filename patterns.

        Perfect for ETL processes, data migrations, or loading reference data where you need reliable, fast imports with proper error handling and transaction safety.

    .PARAMETER Path
        Specifies the file path to Parquet files for import. Supports single files, multiple files, or pipeline input from Get-ChildItem.

    .PARAMETER SqlInstance
        The SQL Server Instance to import data into.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies the target database for the Parquet import. The database must exist on the SQL Server instance.
        Use this to direct your data load to the appropriate database, whether it's a staging, ETL, or production database.

    .PARAMETER Schema
        Specifies the target schema for the table. Defaults to 'dbo' if not specified.
        If the schema doesn't exist, it will be created automatically when using -AutoCreateTable. This parameter takes precedence over -UseFileNameForSchema.

    .PARAMETER Table
        Specifies the destination table name. If omitted, uses the Parquet filename as the table name.
        The table will be created automatically with -AutoCreateTable using UTF-8 varchar(MAX) columns for strings by default, but for production use, create the table first with proper data types and constraints.

    .PARAMETER Column
        Imports only the specified columns from the Parquet file, ignoring all others. Column names must match exactly.
        Use this to selectively load data when you only need certain fields, reducing import time and storage requirements.

    .PARAMETER ColumnMap
        Maps Parquet columns to different table column names using a hashtable. Keys are Parquet column names, values are table column names.
        Use this when your Parquet headers don't match your table structure or when importing from systems with different naming conventions.

    .PARAMETER KeepOrdinalOrder
        Maps columns by position rather than by name matching. The first Parquet column goes to the first table column, second to second, etc.
        Use this when column names don't match but the order is correct, or when dealing with files that have inconsistent naming.

    .PARAMETER AutoCreateTable
        Creates the destination table automatically if it doesn't exist, using Parquet schema types for SQL column definitions.
        String columns are created as UTF-8 varchar(MAX) by default (or nvarchar(MAX) with -NoUtf8), then automatically optimized based on actual data lengths.
        For production use with specific constraints, create tables manually with appropriate data types, indexes, and constraints.

    .PARAMETER NoUtf8
        Switches AutoCreateTable string columns from UTF-8 varchar to nvarchar.
        By default, string columns are created as varchar(MAX) COLLATE Latin1_General_100_BIN2_UTF8.
        Use this switch to create string columns as nvarchar(MAX) instead.

    .PARAMETER NoColumnOptimize
        Skips the automatic column size optimization that runs after AutoCreateTable imports.
        By default, AutoCreateTable creates string columns as UTF-8 varchar(MAX) (or nvarchar(MAX) with -NoUtf8) and then shrinks them to fit the imported data.
        Use this switch when importing multiple Parquet files into the same auto-created table, so that later files
        with longer values are not rejected due to columns being shrunk to fit only the first file's data.

    .PARAMETER Truncate
        Removes all existing data from the destination table before importing. The truncate operation is part of the transaction.
        Use this for full data refreshes where you want to replace all existing data with the Parquet contents.

    .PARAMETER NotifyAfter
        Sets how often progress notifications are displayed during the import, measured in rows. Defaults to 50,000.
        Lower values provide more frequent updates but may slow the import slightly, while higher values reduce overhead for very large files.

    .PARAMETER BatchSize
        Controls how many rows are sent to SQL Server in each batch during the bulk copy operation. Defaults to 50,000.
        Larger batches are generally more efficient but use more memory, while smaller batches provide better granular control and error isolation.

    .PARAMETER UseFileNameForSchema
        Extracts the schema name from the filename using the first period as a delimiter. For example, 'sales.customers.parquet' imports to the 'sales' schema.
        If no period is found, defaults to 'dbo'. The schema will be created if it doesn't exist. This parameter is ignored if -Schema is explicitly specified.

    .PARAMETER TableLock
        Acquires an exclusive table lock for the duration of the import instead of using row-level locks.
        Improves performance for large imports by reducing lock overhead, but blocks other operations on the table during the import.

    .PARAMETER CheckConstraints
        Enforces check constraints, foreign keys, and other table constraints during the import. By default, constraints are not checked for performance.
        Enable this when data integrity validation is critical, but expect slower import performance.

    .PARAMETER FireTriggers
        Executes INSERT triggers on the destination table during the bulk copy operation. By default, triggers are not fired for performance.
        Use this when your triggers perform essential business logic like auditing, logging, or cascading updates that must run during import.

    .PARAMETER KeepIdentity
        Preserves identity column values from the Parquet file instead of generating new ones. By default, the destination assigns new identity values.
        Use this when migrating data and you need to maintain existing primary key values or referential integrity.

    .PARAMETER NoProgress
        Disables the progress bar display during import to improve performance, especially for very large files.
        Use this in automated scripts or when maximum import speed is more important than visual progress feedback.

    .PARAMETER NoTransaction
        Disables the automatic transaction wrapper, allowing partial imports to remain committed even if the operation fails.
        Use this for very large imports where you want to commit data in batches, but be aware that failed imports may leave partial data.

    .PARAMETER StaticColumns
        A hashtable of static column names and values to add to every row.
        Useful for tagging imported data with metadata like source filename or import timestamp.
        Keys are column names, values are the static values to insert.
        Example: @{ SourceFile = "data.parquet"; ImportDate = (Get-Date) }

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Import, Data, Utility
        Author: Jovan Popovic, the dbatools team + Claude

        Website: https://dbatools.io
        Copyright: (c) 2026 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        Requires Parquet.NET. Use Install-DbaParquet to install the external Parquet.NET assemblies if they are not already available.

    .LINK
        https://dbatools.io/Import-DbaParquet


    .OUTPUTS
        PSCustomObject

        Returns one object per Parquet file imported. Each object contains comprehensive metrics about the import operation.

        Properties:
        - ComputerName: The computer name of the SQL Server instance where the Parquet file was imported
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance format)
        - Database: The database name where data was imported
        - Table: The table name where Parquet data was loaded
        - Schema: The schema name containing the target table
        - RowsCopied: The total number of rows successfully copied from the Parquet file (int64)
        - Elapsed: The elapsed time for the import operation in elapsed time format (automatically formatted as HH:mm:ss.fff)
        - RowsPerSecond: The average import rate calculated as total rows divided by elapsed time in seconds (decimal)
        - Path: The full file system path of the imported Parquet file

    .EXAMPLE
        PS C:\> Import-DbaParquet -Path C:\temp\housing.parquet -SqlInstance sql001 -Database markets

        Imports the entire housing.parquet to the SQL "markets" database on a SQL Server named sql001.

        Since a table name was not specified, the table name is automatically determined from filename as "housing".

    .EXAMPLE
        PS C:\> Get-ChildItem -Path \\FileServer\parquets -Filter *.parquet | Import-DbaParquet -SqlInstance sql001, sql002 -Database tempdb -AutoCreateTable

        Imports every Parquet file in the \\FileServer\parquets path into both sql001 and sql002's tempdb database. Each Parquet file will be imported into an automatically determined table name.

    .EXAMPLE
        PS C:\> Get-ChildItem -Path \\FileServer\parquets -Filter *.parquet | Import-DbaParquet -SqlInstance sql001, sql002 -Database tempdb -AutoCreateTable -WhatIf

        Shows what would happen if the command were to be executed

    .EXAMPLE
        PS C:\> Import-DbaParquet -Path c:\temp\dataset.parquet -SqlInstance sql2016 -Database tempdb -Column Name, Address, Mobile

        Import only Name, Address and Mobile even if other columns exist. All other columns are ignored and therefore null or default values.

    .EXAMPLE
        PS C:\> Import-DbaParquet -Path C:\temp\schema.data.parquet -SqlInstance sql2016 -database tempdb -UseFileNameForSchema

        Will import the contents of C:\temp\schema.data.parquet to table 'data' in schema 'schema'.

    .EXAMPLE
        PS C:\> Import-DbaParquet -Path C:\temp\schema.data.parquet -SqlInstance sql2016 -database tempdb -UseFileNameForSchema -Table testtable

        Will import the contents of C:\temp\schema.data.parquet to table 'testtable' in schema 'schema'.

    .EXAMPLE
        PS C:\> $columns = @{
        >> Text = "FirstName"
        >> Number = "PhoneNumber"
        >> }
        PS C:\> Import-DbaParquet -Path c:\temp\supersmall.parquet -SqlInstance sql2016 -Database tempdb -ColumnMap $columns

        The Parquet field 'Text' is inserted into SQL column 'FirstName' and Parquet field Number is inserted into the SQL Column 'PhoneNumber'. All other columns are ignored and therefore null or default values.

    .EXAMPLE
        PS C:\> Import-DbaParquet -Path C:\temp\refresh.parquet -SqlInstance sql001 -Database tempdb -Table LookupData -Truncate

        Performs a full data refresh by truncating the existing table before importing. The truncate and import
        operations are wrapped in a transaction, so if the import fails, the original data is preserved.

    .EXAMPLE
        PS C:\> $static = @{ SourceFile = "sales_2024.parquet"; ImportDate = (Get-Date); Region = "EMEA" }
        PS C:\> Import-DbaParquet -Path C:\temp\sales.parquet -SqlInstance sql001 -Database sales -Table SalesData -StaticColumns $static -AutoCreateTable

        Imports Parquet data and adds three static columns (SourceFile, ImportDate, Region) to every row.
        This is useful for tracking data lineage and tagging imported records with metadata.

    .EXAMPLE
        PS C:\> Import-DbaParquet -Path C:\temp\quickload.parquet -SqlInstance sql001 -Database tempdb -Table QuickData -AutoCreateTable

        Imports quickload.parquet with AutoCreateTable. After import completes, column sizes are automatically
        optimized by querying actual max lengths and altering columns from varchar(MAX) to padded sizes
        like varchar(16), varchar(32), varchar(64), etc.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low")]
    param (
        [parameter(ValueFromPipeline)]
        [ValidateNotNullOrEmpty()]
        [Alias("Parquet", "FullPath")]
        [object[]]$Path,
        [Parameter(Mandatory)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [Parameter(Mandatory)]
        [string]$Database,
        [string]$Table,
        [string]$Schema,
        [switch]$Truncate,
        [int]$BatchSize = 50000,
        [int]$NotifyAfter = 50000,
        [switch]$TableLock,
        [switch]$CheckConstraints,
        [switch]$FireTriggers,
        [switch]$KeepIdentity,
        [string[]]$Column,
        [hashtable]$ColumnMap,
        [switch]$KeepOrdinalOrder,
        [switch]$AutoCreateTable,
        [switch]$NoUtf8,
        [switch]$NoColumnOptimize,
        [switch]$NoProgress,
        [switch]$UseFileNameForSchema,
        [switch]$NoTransaction,
        [hashtable]$StaticColumns,
        [switch]$EnableException
    )
    begin {
        $scriptelapsed = [System.Diagnostics.Stopwatch]::StartNew()
        $StoreStringAsUtf8 = -not $NoUtf8

        if ($PSBoundParameters.UseFileNameForSchema -and $PSBoundParameters.Schema) {
            Write-Message -Level Warning -Message "Schema and UseFileNameForSchema parameters both specified. UseSchemaInFileName will be ignored."
        }

        # Load Parquet.NET assembly
        $parquetAssembly = [System.AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.GetName().Name -eq "Parquet" }
        if (-not $parquetAssembly) {
            $parquetDllPath = Get-DbaParquetPath -EnableException:$EnableException
            if (-not $parquetDllPath) {
                return
            }

            $parquetDirectory = Split-Path -Path $parquetDllPath -Parent
            $script:dbatools_ParquetAssemblyPath = $parquetDirectory
            if (-not $script:dbatools_ParquetAssemblyResolveRegistered) {
                $script:dbatools_ParquetAssemblyResolve = [System.ResolveEventHandler] {
                    param($sender, $resolveArgs)

                    $assemblyName = (New-Object -TypeName System.Reflection.AssemblyName -ArgumentList $resolveArgs.Name).Name
                    $candidate = Join-Path -Path $script:dbatools_ParquetAssemblyPath -ChildPath "$assemblyName.dll"
                    if (Test-Path -Path $candidate) {
                        return [System.Reflection.Assembly]::LoadFrom($candidate)
                    }
                    return $null
                }
                [System.AppDomain]::CurrentDomain.add_AssemblyResolve($script:dbatools_ParquetAssemblyResolve)
                $script:dbatools_ParquetAssemblyResolveRegistered = $true
            }

            Get-ChildItem -Path $parquetDirectory -Filter "*.dll" | Where-Object Name -notin "Parquet.dll", "Parquet.Net.dll" | Sort-Object Name | ForEach-Object {
                try {
                    Add-Type -Path $PSItem.FullName -ErrorAction Stop
                } catch {
                    Write-Message -Level Verbose -Message "Could not preload Parquet.NET dependency $($PSItem.Name): $($_.Exception.Message)"
                }
            }

            try {
                Add-Type -Path $parquetDllPath -ErrorAction Stop
            } catch {
                Stop-Function -Message "Could not load Parquet.NET from $parquetDllPath. Run Install-DbaParquet to install the required assemblies." -ErrorRecord $_ -EnableException $EnableException
                return
            }
        }

        function Get-ParquetReader {
            param([string]$Path)
            $stream = [System.IO.File]::OpenRead($Path)
            try {
                $reader = [Parquet.ParquetReader]::CreateAsync($stream).GetAwaiter().GetResult()
                return $reader
            } catch {
                $stream.Dispose()
                throw
            }
        }

        function Get-ParquetDataFields {
            param($Reader)
            $dataFields = $Reader.Schema.GetDataFields()
            # Fail-fast on nested/complex types
            foreach ($df in $dataFields) {
                if ($df.ClrType -eq [System.Object] -or
                    $df.ClrType.IsArray -and $df.ClrType -ne [byte[]]) {
                    Stop-Function -Message "Nested Parquet types not supported: $($df.Name) (type: $($df.ClrType.FullName))" -EnableException $true
                    return
                }
            }
            return $dataFields
        }

        function Get-ParquetDataTable {
            param(
                $Reader,
                [string[]]$Column,
                [hashtable]$StaticColumns,
                [int]$RowGroupIndex
            )

            function Convert-ParquetValueForColumn {
                param(
                    [object]$Value,
                    [System.Type]$TargetType,
                    [string]$ColumnName
                )

                if ($null -eq $Value) {
                    return [DBNull]::Value
                }

                if ($TargetType -eq [byte[]]) {
                    if ($Value -is [byte[]]) {
                        return , $Value
                    }

                    if ($Value -is [System.Array]) {
                        $converted = New-Object byte[] ($Value.Length)
                        for ($index = 0; $index -lt $Value.Length; $index++) {
                            $item = $Value[$index]

                            if ($item -is [byte]) {
                                $converted[$index] = $item
                                continue
                            }

                            if ($item -is [int] -and $item -ge [byte]::MinValue -and $item -le [byte]::MaxValue) {
                                $converted[$index] = [byte]$item
                                continue
                            }

                            Stop-Function -Message "Could not convert value in column $ColumnName to byte array. Element type: $($item.GetType().FullName)." -EnableException $true
                            return
                        }

                        return , $converted
                    }

                    Stop-Function -Message "Could not convert value in column $ColumnName from type $($Value.GetType().FullName) to byte array." -EnableException $true
                    return
                }

                return $Value
            }

            $dataFields = $Reader.Schema.GetDataFields()
            $dataTable = New-Object System.Data.DataTable

            foreach ($df in $dataFields) {
                if ($Column -and $Column -notcontains $df.Name) { continue }
                [void]$dataTable.Columns.Add($df.Name, $df.ClrType)
            }

            if ($StaticColumns) {
                foreach ($key in $StaticColumns.Keys) {
                    if (-not $dataTable.Columns.Contains($key)) {
                        [void]$dataTable.Columns.Add($key, [string])
                    }
                }
            }

            $rowGroupReader = $Reader.OpenRowGroupReader($RowGroupIndex)
            $columns = @{ }
            $rowCount = 0
            foreach ($df in $dataFields) {
                if ($Column -and $Column -notcontains $df.Name) { continue }
                $col = $rowGroupReader.ReadColumnAsync($df).GetAwaiter().GetResult()
                $columns[$df.Name] = $col.Data
                $rowCount = $col.Data.Length
            }

            for ($row = 0; $row -lt $rowCount; $row++) {
                $dataRow = $dataTable.NewRow()
                foreach ($name in $columns.Keys) {
                    $val = $columns[$name][$row]
                    $targetType = $dataTable.Columns[$name].DataType
                    $dataRow[$name] = Convert-ParquetValueForColumn -Value $val -TargetType $targetType -ColumnName $name
                }
                if ($StaticColumns) {
                    foreach ($key in $StaticColumns.Keys) {
                        $dataRow[$key] = $StaticColumns[$key]
                    }
                }
                [void]$dataTable.Rows.Add($dataRow)
            }

            if ($rowGroupReader -is [System.IDisposable]) { $rowGroupReader.Dispose() }

            return , $dataTable
        }

        function Convert-ParquetTypeToSqlType {
            param([object]$DataField)
            $clrType = $DataField.ClrType
            switch ($clrType.FullName) {
                "System.String" {
                    $stringLength = "MAX"
                    if ($DataField.SchemaElement -and
                        $DataField.SchemaElement.Type -eq "FIXED_LEN_BYTE_ARRAY" -and
                        $DataField.SchemaElement.TypeLength -gt 0) {
                        $maxAllowed = if ($StoreStringAsUtf8) { 8000 } else { 4000 }
                        $typeLength = [int]$DataField.SchemaElement.TypeLength
                        if ($typeLength -le $maxAllowed) {
                            $stringLength = $typeLength
                        }
                    }

                    if ($StoreStringAsUtf8) {
                        return "varchar($stringLength) COLLATE Latin1_General_100_BIN2_UTF8"
                    }
                    return "nvarchar($stringLength)"
                }
                "System.Int32" { return "int" }
                "System.Int64" { return "bigint" }
                "System.Int16" { return "smallint" }
                "System.Byte" { return "tinyint" }
                "System.Boolean" { return "bit" }
                "System.Single" { return "real" }
                "System.Double" { return "float" }
                "System.Decimal" {
                    $precision = 38
                    $scale = 18

                    if ($DataField.GetType().Name -eq "DecimalDataField") {
                        $precision = $DataField.Precision
                        $scale = $DataField.Scale
                    }

                    if ($precision -gt 38) {
                        $precision = 38
                    }

                    if ($scale -gt $precision) {
                        $scale = $precision
                    }

                    return "decimal($precision,$scale)"
                }
                "System.DateTime" { return "datetime2(6)" }
                "System.DateTimeOffset" { return "datetimeoffset" }
                "System.TimeSpan" { return "time" }
                "System.Byte[]" {
                    if ($DataField.SchemaElement -and
                        $DataField.SchemaElement.Type -eq "FIXED_LEN_BYTE_ARRAY" -and
                        $DataField.SchemaElement.TypeLength -gt 0) {
                        return "varbinary($($DataField.SchemaElement.TypeLength))"
                    }
                    return "varbinary(MAX)"
                }
                "System.Guid" { return "uniqueidentifier" }
                default {
                    Stop-Function -Message "Unsupported Parquet type: $($clrType.FullName)" -EnableException $true
                    return
                }
            }
        }

        function New-SqlTable {
            <#
                .SYNOPSIS
                    Creates new Table using existing SqlCommand.

                    SQL datatypes are inferred from Parquet schema data fields.
                    String columns use UTF-8 varchar(MAX) by default (or nvarchar(MAX) when requested) and can be post-optimized.

                .EXAMPLE
                    New-SqlTable -DataFields $dataFields -SqlConn $sqlconn -Transaction $transaction

                .OUTPUTS
                    Creates new table
            #>
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseShouldProcessForStateChangingFunctions", "")]
            param (
                [Parameter(Mandatory)]
                [object[]]$DataFields,
                [Microsoft.Data.SqlClient.SqlConnection]$sqlconn,
                [Microsoft.Data.SqlClient.SqlTransaction]$transaction,
                [hashtable]$StaticColumns
            )

            $sqldatatypes = @()
            foreach ($df in $DataFields) {
                $sqlType = Convert-ParquetTypeToSqlType -DataField $df
                $sqldatatypes += "[$($df.Name)] $sqlType NULL"
            }

            # Static columns ride along on every row in the DataTable, so they must exist in the
            # destination too — otherwise SqlBulkCopy.ColumnMappings.Add fails with "does not match
            # up with any column in the source or destination". Use the same string column shape
            # the rest of AutoCreateTable picks for parquet strings.
            if ($StaticColumns) {
                $stringSqlType = if ($StoreStringAsUtf8) { "varchar(MAX) COLLATE Latin1_General_100_BIN2_UTF8" } else { "nvarchar(MAX)" }
                foreach ($key in $StaticColumns.Keys) {
                    $sqldatatypes += "[$key] $stringSqlType NULL"
                }
            }

            $sql = "BEGIN CREATE TABLE [$schema].[$table] ($($sqldatatypes -join ", ")) END"
            $sqlcmd = New-Object Microsoft.Data.SqlClient.SqlCommand($sql, $sqlconn, $transaction)

            try {
                $null = $sqlcmd.ExecuteNonQuery()
            } catch {
                Stop-Function -Continue -Message "Failed to execute $sql" -ErrorRecord $_
            }

            Write-Message -Level Verbose -Message "Successfully created table $schema.$table with the following column definitions:`n $($sqldatatypes -join "`n ")"
            Write-Message -Level Verbose -Message "This is inefficient but allows the script to import without issues."
            Write-Message -Level Verbose -Message "Consider creating the table first using best practices if the data will be used in production."
        }

        function Optimize-ColumnSize {
            <#
                .SYNOPSIS
                    Optimizes varchar(MAX) columns to appropriate sizes after import.

                .DESCRIPTION
                    Queries MAX(LEN()) for each column and ALTERs to appropriate varchar sizes.
                    This is called automatically when AutoCreateTable is used.

                .NOTES
                    Requires SQL Server 2005 or higher. This is not a limitation since varchar(MAX)
                    was introduced in SQL Server 2005 - the feature this optimizes cannot exist on SQL 2000.
            #>
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseShouldProcessForStateChangingFunctions", "")]
            param (
                [Microsoft.Data.SqlClient.SqlConnection]$SqlConn,
                [string]$Schema,
                [string]$Table
            )

            Write-Message -Level Verbose -Message "Optimizing column sizes for $Schema.$Table..."

            # Get column names and their current types from the table
            $getColumnsSql = @"
SELECT c.name AS ColumnName, t.name AS TypeName, c.collation_name AS CollationName
FROM sys.columns c
INNER JOIN sys.types t ON c.user_type_id = t.user_type_id
WHERE c.object_id = OBJECT_ID(@tableName)
  AND t.name IN ('nvarchar', 'varchar')
  AND c.max_length = -1
"@
            $sqlcmd = New-Object Microsoft.Data.SqlClient.SqlCommand($getColumnsSql, $SqlConn)
            $null = $sqlcmd.Parameters.AddWithValue("tableName", "[$Schema].[$Table]")

            $columns = @{ }
            $reader = $sqlcmd.ExecuteReader()
            while ($reader.Read()) {
                $columns[$reader["ColumnName"]] = [PSCustomObject]@{
                    TypeName      = $reader["TypeName"]
                    CollationName = if ($reader["CollationName"] -is [DBNull]) { $null } else { [string]$reader["CollationName"] }
                }
            }
            $reader.Close()

            if ($columns.Count -eq 0) {
                Write-Message -Level Verbose -Message "No nvarchar(MAX)/varchar(MAX) columns to optimize."
                return
            }

            # Build MAX(LEN()) query for all columns
            $columnNames = @($columns.Keys)
            $maxLenSelects = $columnNames | ForEach-Object { "MAX(LEN([$_])) AS [$_]" }
            $maxLenSql = "SELECT $($maxLenSelects -join ", ") FROM [$Schema].[$Table]"

            $sqlcmd = New-Object Microsoft.Data.SqlClient.SqlCommand($maxLenSql, $SqlConn)
            $reader = $sqlcmd.ExecuteReader()

            $maxLengths = @{ }
            if ($reader.Read()) {
                foreach ($col in $columnNames) {
                    $val = $reader[$col]
                    if ($val -is [DBNull] -or $null -eq $val) {
                        $maxLengths[$col] = 1
                    } else {
                        $maxLengths[$col] = [int]$val
                    }
                }
            }
            $reader.Close()

            # ALTER each column to appropriate size, preserving original type
            foreach ($col in $columnNames) {
                $maxLen = $maxLengths[$col]
                if ($maxLen -eq 0) { $maxLen = 1 }

                # Preserve the original column type (nvarchar stays nvarchar, varchar stays varchar)
                # This is safer than trying to detect Unicode - no risk of data loss
                $baseType = $columns[$col].TypeName
                $maxAllowed = if ($baseType -eq "nvarchar") { 4000 } else { 8000 }

                if ($maxLen -gt $maxAllowed) {
                    # Keep as MAX if truly needed
                    Write-Message -Level Verbose -Message "Column [$col] requires $baseType(MAX) - max length is $maxLen"
                    continue
                }

                # Add padding to the length to allow for future data that may be slightly longer
                # This prevents issues when re-importing to the same table with -Truncate
                # Round up to common sizes: 16, 32, 64, 128, 256, 512, 1024, 2048, 4000/8000
                $paddedLen = switch ($true) {
                    ($maxLen -le 16) { 16; break }
                    ($maxLen -le 32) { 32; break }
                    ($maxLen -le 64) { 64; break }
                    ($maxLen -le 128) { 128; break }
                    ($maxLen -le 256) { 256; break }
                    ($maxLen -le 512) { 512; break }
                    ($maxLen -le 1024) { 1024; break }
                    ($maxLen -le 2048) { 2048; break }
                    default { $maxAllowed }
                }
                # Ensure we don't exceed the max allowed
                if ($paddedLen -gt $maxAllowed) { $paddedLen = $maxAllowed }

                $newType = "${baseType}($paddedLen)"
                $collateClause = ""
                if ($columns[$col].CollationName) {
                    $collateClause = " COLLATE $($columns[$col].CollationName)"
                }
                # SQL Server 2008 R2 and earlier require NULL/NOT NULL in ALTER COLUMN
                # Original columns were varchar(MAX) NULL, so we preserve NULL
                $alterSql = "ALTER TABLE [$Schema].[$Table] ALTER COLUMN [$col] $newType$collateClause NULL"

                Write-Message -Level Verbose -Message "Optimizing [$col]: $baseType(MAX) -> $newType (max data length: $maxLen, padded to: $paddedLen)"

                try {
                    $sqlcmd = New-Object Microsoft.Data.SqlClient.SqlCommand($alterSql, $SqlConn)
                    $null = $sqlcmd.ExecuteNonQuery()
                } catch {
                    Write-Message -Level Warning -Message "Failed to optimize column [$col]: $($_.Exception.Message)"
                }
            }

            Write-Message -Level Verbose -Message "Column size optimization complete."
        }

        Write-Message -Level Verbose -Message "Started at $(Get-Date)"
    }
    process {
        foreach ($filename in $Path) {
            if (-not $PSBoundParameters.ColumnMap) {
                $ColumnMap = $null
            }

            if ($filename.FullName) {
                $filename = $filename.FullName
            }

            if (-not (Test-Path -Path $filename)) {
                Stop-Function -Continue -Message "$filename cannot be found"
            }

            $file = (Resolve-Path -Path $filename).ProviderPath

            $filename = [IO.Path]::GetFileNameWithoutExtension($file)

            # Automatically generate Table name if not specified
            if (-not $PSBoundParameters.Table) {
                $periodFound = $false
                if ($filename.IndexOf(".") -ne -1) { $periodFound = $true }

                if ($UseFileNameForSchema -and $periodFound -and -not $PSBoundParameters.Schema) {
                    $table = $filename.Remove(0, $filename.IndexOf(".") + 1)
                    Write-Message -Level Verbose -Message "Table name not specified, using $table from file name"
                } else {
                    $table = $filename
                    Write-Message -Level Verbose -Message "Table name not specified, using $table"
                }
            }

            # Use dbo as schema name if not specified in params, or as first string before a period in filename
            if (-not ($PSBoundParameters.Schema)) {
                if ($UseFileNameForSchema) {
                    if ($filename.IndexOf(".") -eq -1) {
                        $schema = "dbo"
                        Write-Message -Level Verbose -Message "Schema not specified, and not found in file name, using dbo"
                    } else {
                        $schema = $filename.SubString(0, $filename.IndexOf("."))
                        Write-Message -Level Verbose -Message "Schema detected in filename, using $schema"
                    }
                } else {
                    $schema = "dbo"
                    Write-Message -Level Verbose -Message "Schema not specified, using dbo"
                }
            }

            foreach ($instance in $SqlInstance) {
                $elapsed = [System.Diagnostics.Stopwatch]::StartNew()
                # Open Connection to SQL Server
                # Detect if user passed an already-open connection that we should preserve
                $startedWithAnOpenConnection = $false
                try {
                    # Check if user passed a Server SMO object with an open connection
                    # Following the pattern from Invoke-DbaQuery.ps1
                    if ($instance.InputObject.GetType().Name -eq "Server" -and
                        (-not $SqlCredential) -and
                        ($instance.InputObject.ConnectionContext.DatabaseName -eq $Database -or -not $Database)) {
                        $startedWithAnOpenConnection = $true
                        Write-Message -Level Debug -Message "User provided an open connection - will preserve it after import"
                    }

                    $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -Database $Database -MinimumVersion 9
                    $sqlconn = $server.ConnectionContext.SqlConnectionObject
                    if ($sqlconn.State -ne "Open") {
                        $sqlconn.Open()
                    }
                } catch {
                    Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
                }

                if (-not $NoTransaction) {
                    if ($PSCmdlet.ShouldProcess($instance, "Starting transaction in $Database")) {
                        # Everything will be contained within 1 transaction, even creating a new table if required
                        # and truncating the table, if specified.
                        $transaction = $sqlconn.BeginTransaction()
                    }
                }

                # Ensure Schema exists
                $sql = "SELECT COUNT(*) FROM sys.schemas WHERE name = @schema"
                $sqlcmd = New-Object Microsoft.Data.SqlClient.SqlCommand($sql, $sqlconn, $transaction)
                $null = $sqlcmd.Parameters.AddWithValue("schema", $schema)
                # If Schema doesn't exist create it
                # Defaulting to dbo.
                if (($sqlcmd.ExecuteScalar()) -eq 0) {
                    if (-not $AutoCreateTable) {
                        Stop-Function -Continue -Message "Schema $Schema does not exist and AutoCreateTable was not specified"
                    }
                    $sql = "CREATE SCHEMA [$schema] AUTHORIZATION dbo"
                    if ($PSCmdlet.ShouldProcess($instance, "Creating schema $schema")) {
                        $sqlcmd = New-Object Microsoft.Data.SqlClient.SqlCommand($sql, $sqlconn, $transaction)
                        try {
                            $null = $sqlcmd.ExecuteNonQuery()
                        } catch {
                            Stop-Function -Continue -Message "Could not create $schema" -ErrorRecord $_
                        }
                    }
                }

                # Ensure table or view exists
                $sql = "SELECT COUNT(*) FROM sys.tables WHERE name = @table AND schema_id = schema_id(@schema)"
                $sqlcmd = New-Object Microsoft.Data.SqlClient.SqlCommand($sql, $sqlconn, $transaction)
                $null = $sqlcmd.Parameters.AddWithValue("schema", $schema)
                $null = $sqlcmd.Parameters.AddWithValue("table", $table)

                $sql2 = "SELECT COUNT(*) FROM sys.views WHERE name = @table AND schema_id=schema_id(@schema)"
                $sqlcmd2 = New-Object Microsoft.Data.SqlClient.SqlCommand($sql2, $sqlconn, $transaction)
                $null = $sqlcmd2.Parameters.AddWithValue("schema", $schema)
                $null = $sqlcmd2.Parameters.AddWithValue("table", $table)

                # Track if we created a "fat" table (varchar(MAX) for all columns) that needs post-import optimization
                $createdFatTable = $false

                # Open Parquet reader to get schema information
                $parquetReader = $null
                try {
                    $parquetReader = Get-ParquetReader -Path $file
                    $dataFields = Get-ParquetDataFields -Reader $parquetReader
                } catch {
                    Stop-Function -Continue -Message "Failed to open Parquet file: $file" -ErrorRecord $_
                }

                # Create the table if required. Remember, this will occur within a transaction, so if the script fails, the
                # new table will no longer exist.
                if (($sqlcmd.ExecuteScalar()) -eq 0 -and ($sqlcmd2.ExecuteScalar()) -eq 0) {
                    if (-not $AutoCreateTable) {
                        Stop-Function -Continue -Message "Table or view $table does not exist and AutoCreateTable was not specified"
                    }
                    Write-Message -Level Verbose -Message "Table does not exist"

                    if ($PSCmdlet.ShouldProcess($instance, "Creating table $table")) {
                        try {
                            $splatNewSqlTable = @{
                                DataFields  = $dataFields
                                SqlConn     = $sqlconn
                                Transaction = $transaction
                            }
                            if ($PSBoundParameters.StaticColumns) {
                                $splatNewSqlTable.StaticColumns = $StaticColumns
                            }
                            New-SqlTable @splatNewSqlTable
                            $createdFatTable = $true
                        } catch {
                            Stop-Function -Continue -Message "Failure" -ErrorRecord $_
                        }
                    }
                } else {
                    Write-Message -Level Verbose -Message "Table exists"
                }

                # Truncate if specified. Remember, this will occur within a transaction, so if the script fails, the
                # truncate will not be committed.
                if ($Truncate) {
                    $sql = "TRUNCATE TABLE [$schema].[$table]"
                    if ($PSCmdlet.ShouldProcess($instance, "Performing TRUNCATE TABLE [$schema].[$table] on $Database")) {
                        $sqlcmd = New-Object Microsoft.Data.SqlClient.SqlCommand($sql, $sqlconn, $transaction)
                        try {
                            $null = $sqlcmd.ExecuteNonQuery()
                        } catch {
                            Stop-Function -Continue -Message "Could not truncate $schema.$table" -ErrorRecord $_
                        }
                    }
                }

                # Setup bulk copy
                Write-Message -Level Verbose -Message "Starting bulk copy for $(Split-Path $file -Leaf)"

                # Setup bulk copy options
                [int]$bulkCopyOptions = ([Microsoft.Data.SqlClient.SqlBulkCopyOptions]::Default)
                $options = "TableLock", "CheckConstraints", "FireTriggers", "KeepIdentity"
                foreach ($option in $options) {
                    $optionValue = Get-Variable $option -ValueOnly -ErrorAction SilentlyContinue
                    if ($optionValue -eq $true) {
                        $bulkCopyOptions += $([Microsoft.Data.SqlClient.SqlBulkCopyOptions]::$option).value__
                    }
                }

                if ($PSCmdlet.ShouldProcess($instance, "Performing import from $file")) {
                    try {
                        # Create SqlBulkCopy using default options, or options specified in command line.
                        if ($bulkCopyOptions) {
                            $bulkcopy = New-Object Microsoft.Data.SqlClient.SqlBulkCopy($sqlconn, $bulkCopyOptions, $transaction)
                        } else {
                            $bulkcopy = New-Object Microsoft.Data.SqlClient.SqlBulkCopy($sqlconn, ([Microsoft.Data.SqlClient.SqlBulkCopyOptions]::Default), $transaction)
                        }

                        $bulkcopy.DestinationTableName = "[$schema].[$table]"
                        $bulkcopy.BulkCopyTimeout = 0
                        $bulkCopy.BatchSize = $BatchSize
                        $bulkCopy.NotifyAfter = $NotifyAfter
                        $bulkCopy.EnableStreaming = $true

                        # Auto-create column mapping from Parquet schema for name-based matching
                        if (-not $KeepOrdinalOrder -and -not $Column) {
                            if ($ColumnMap) {
                                Write-Message -Level Verbose -Message "ColumnMap was supplied. Additional auto-mapping will not be attempted."
                            } else {
                                try {
                                    $ColumnMap = @{ }
                                    foreach ($df in $dataFields) {
                                        Write-Message -Level Verbose -Message "Adding $($df.Name) to ColumnMap"
                                        $ColumnMap.Add($df.Name, $df.Name)
                                    }
                                } catch {
                                    # oh well, we tried
                                    Write-Message -Level Verbose -Message "Couldn't auto create ColumnMap from Parquet schema"
                                    $ColumnMap = $null
                                }
                            }
                        }

                        if ($ColumnMap) {
                            foreach ($columnname in $ColumnMap) {
                                foreach ($key in $columnname.Keys | Sort-Object) {
                                    #sort added in case of column maps done by ordinal
                                    $null = $bulkcopy.ColumnMappings.Add($key, $columnname[$key])
                                }
                            }
                        }

                        if ($Column) {
                            foreach ($columnname in $Column) {
                                $null = $bulkcopy.ColumnMappings.Add($columnname, $columnname)
                            }
                        }

                        # Add static column mappings for metadata tagging
                        if ($PSBoundParameters.StaticColumns) {
                            foreach ($key in $StaticColumns.Keys) {
                                $null = $bulkcopy.ColumnMappings.Add($key, $key)
                            }
                        }

                    } catch {
                        Stop-Function -Continue -Message "Failure" -ErrorRecord $_
                    }

                    # Write to server
                    try {

                        # The legacy bulk copy library uses a 4 byte integer to track the RowsCopied, so the only option is to use
                        # integer wrap so that copy operations of row counts greater than [int32]::MaxValue will report accurate numbers.
                        # See https://github.com/dataplat/dbatools/issues/6927 for more details
                        $script:prevRowsCopied = [int64]0
                        $script:totalRowsCopied = [int64]0

                        # Add rowcount output
                        $bulkCopy.Add_SqlRowsCopied( {
                                $script:totalRowsCopied += (Get-AdjustedTotalRowsCopied -ReportedRowsCopied $args[1].RowsCopied -PreviousRowsCopied $script:prevRowsCopied).NewRowCountAdded

                                Write-Message -Level Verbose -FunctionName "Import-DbaParquet" -Message " Total rows copied = $($script:totalRowsCopied)"
                                # save the previous count of rows copied to be used on the next event notification
                                $script:prevRowsCopied = $args[1].RowsCopied
                            })

                        for ($rgIndex = 0; $rgIndex -lt $parquetReader.RowGroupCount; $rgIndex++) {
                            $dataTable = Get-ParquetDataTable -Reader $parquetReader -Column $Column -StaticColumns $StaticColumns -RowGroupIndex $rgIndex

                            if (-not $NoProgress) {
                                $timetaken = [math]::Round($elapsed.Elapsed.TotalSeconds, 2)
                                $percent = [int]((($rgIndex + 1) / $parquetReader.RowGroupCount) * 100)
                                Write-ProgressHelper -StepNumber $percent -TotalSteps 100 -Activity "Importing from $file" -Message ([System.String]::Format("Progress: {0} rows {1}% in {2} seconds", $script:totalRowsCopied, $percent, $timetaken))
                            }

                            $dataReader = $dataTable.CreateDataReader()
                            $bulkCopy.WriteToServer($dataReader)
                            $dataReader.Dispose()
                            $dataTable.Dispose()
                        }

                        $completed = $true
                    } catch {
                        $completed = $false
                        Stop-Function -Continue -Message "Failure" -ErrorRecord $_
                    } finally {
                        try {
                            if ($parquetReader) {
                                $parquetReader.Dispose()
                                $parquetReader = $null
                            }
                        } catch {
                        }

                        if (-not $NoTransaction) {
                            if ($completed) {
                                try {
                                    $null = $transaction.Commit()
                                } catch {
                                }

                                # Optimize column sizes after commit if we created a fat table
                                if ($createdFatTable -and -not $NoColumnOptimize) {
                                    try {
                                        Optimize-ColumnSize -SqlConn $sqlconn -Schema $schema -Table $table
                                    } catch {
                                        Write-Message -Level Warning -Message "Column size optimization failed: $($_.Exception.Message)"
                                    }
                                }
                            } else {
                                try {
                                    $null = $transaction.Rollback()
                                } catch {
                                }
                            }
                        } elseif ($completed -and $createdFatTable -and -not $NoColumnOptimize) {
                            # NoTransaction mode - still optimize if we created a fat table
                            try {
                                Optimize-ColumnSize -SqlConn $sqlconn -Schema $schema -Table $table
                            } catch {
                                Write-Message -Level Warning -Message "Column size optimization failed: $($_.Exception.Message)"
                            }
                        }

                        # Only close connection if we created it (not user-provided)
                        if (-not $startedWithAnOpenConnection) {
                            try {
                                $sqlconn.Close()
                                $sqlconn.Dispose()
                            } catch {
                            }
                        }

                        try {
                            $bulkCopy.Close()
                            $bulkcopy.Dispose()
                        } catch {
                        }

                        $finalRowCountReported = Get-BulkRowsCopiedCount $bulkCopy

                        $script:totalRowsCopied += (Get-AdjustedTotalRowsCopied -ReportedRowsCopied $finalRowCountReported -PreviousRowsCopied $script:prevRowsCopied).NewRowCountAdded

                        if ($completed) {
                            Write-Progress -Id 1 -Activity "Inserting $($script:totalRowsCopied) rows" -Status "Complete" -Completed
                        } else {
                            Write-Progress -Id 1 -Activity "Inserting $($script:totalRowsCopied) rows" -Status "Failed" -Completed
                        }
                    }
                }
                # Clean up Parquet reader if ShouldProcess was skipped (WhatIf mode)
                if ($parquetReader) {
                    try { $parquetReader.Dispose() } catch { }
                    $parquetReader = $null
                }
                if ($PSCmdlet.ShouldProcess($instance, "Finalizing import")) {
                    if ($completed) {
                        # "Note: This count does not take into consideration the number of rows actually inserted when Ignore Duplicates is set to ON."
                        $rowsPerSec = [math]::Round($script:totalRowsCopied / $elapsed.ElapsedMilliseconds * 1000.0, 1)

                        Write-Message -Level Verbose -Message "$($script:totalRowsCopied) total rows copied"

                        [PSCustomObject]@{
                            ComputerName  = $server.ComputerName
                            InstanceName  = $server.ServiceName
                            SqlInstance   = $server.DomainInstanceName
                            Database      = $Database
                            Table         = $table
                            Schema        = $schema
                            RowsCopied    = $script:totalRowsCopied
                            Elapsed       = [prettytimespan]$elapsed.Elapsed
                            RowsPerSecond = $rowsPerSec
                            Path          = $file
                        }
                    } else {
                        Stop-Function -Message "Transaction rolled back."
                        return
                    }
                }
            }
        }
    }
    end {
        $totaltime = [math]::Round($scriptelapsed.Elapsed.TotalSeconds, 2)
        Write-Message -Level Verbose -Message "Total Elapsed Time for everything: $totaltime seconds"
    }
}
