function Import-DbaCsv {
    <#
    .SYNOPSIS
        Imports CSV files into SQL Server tables using high-performance bulk copy operations.

    .DESCRIPTION
        Import-DbaCsv uses .NET's SqlBulkCopy class to efficiently load CSV data into SQL Server tables, handling files of any size from small datasets to multi-gigabyte imports. The function wraps the entire operation in a transaction, so any failure or interruption rolls back all changes automatically.

        When the target table doesn't exist, you can use -AutoCreateTable to create it on the fly with basic nvarchar(max) columns. For production use, create your table first with proper data types and constraints. The function intelligently maps CSV columns to table columns by name, with fallback to ordinal position when needed.

        Supports various CSV formats including custom delimiters, quoted fields, gzip compression (.csv.gz files), and multi-line values within quoted fields. Column mapping lets you import specific columns or rename them during import, while schema detection can automatically place data in the correct schema based on filename patterns.

        Perfect for ETL processes, data migrations, or loading reference data where you need reliable, fast imports with proper error handling and transaction safety.

    .PARAMETER Path
        Specifies path to the CSV file(s) to be imported. Multiple files may be imported at once.

    .PARAMETER NoHeaderRow
        By default, the first row is used to determine column names for the data being imported.

        Use this switch if the first row contains data and not column names.

    .PARAMETER Delimiter
        Specifies the delimiter used in the imported file(s). If no delimiter is specified, comma is assumed.

        Valid delimiters are '`t`, '|', ';',' ' and ',' (tab, pipe, semicolon, space, and comma).

    .PARAMETER SingleColumn
        Specifies that the file contains a single column of data. Otherwise, the delimiter check bombs.

    .PARAMETER SqlInstance
        The SQL Server Instance to import data into.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies the name of the database the CSV will be imported into. Options for this this parameter are  auto-populated from the server.

    .PARAMETER Schema
        Specifies the schema in which the SQL table or view where CSV will be imported into resides. Default is dbo.

        If a schema does not currently exist, it will be created, after a prompt to confirm this. Authorization will be set to dbo by default.

        This parameter overrides -UseFileNameForSchema.

    .PARAMETER Table
        Specifies the SQL table or view where CSV will be imported into.

        If a table name is not specified, the table name will be automatically determined from the filename.

        If the table specified does not exist and -AutoCreateTable, it will be automatically created using slow and inefficient but accommodating data types.

        If the automatically generated table datatypes do not work for you, please create the table prior to import.

        If you want to import specific columns from a CSV, create a view with corresponding columns.

    .PARAMETER Column
        Import only specific columns. To remap column names, use the ColumnMap.

    .PARAMETER ColumnMap
        By default, the bulk copy tries to automap columns. When it doesn't work as desired, this parameter will help. Check out the examples for more information.

    .PARAMETER KeepOrdinalOrder
        By default, the importer will attempt to map exact-match columns names from the source document to the target table. Using this parameter will keep the ordinal order instead.

    .PARAMETER AutoCreateTable
        Creates a table if it does not already exist. The table will be created with sub-optimal data types such as nvarchar(max)

    .PARAMETER Truncate
        If this switch is enabled, the destination table will be truncated prior to import.

    .PARAMETER NotifyAfter
        Specifies the import row count interval for reporting progress. A notification will be shown after each group of this many rows has been imported.

    .PARAMETER BatchSize
        Specifies the batch size for the import. Defaults to 50000.

    .PARAMETER UseFileNameForSchema
        If this switch is enabled, the script will try to find the schema name in the input file by looking for a period (.) in the file name.

        If used with the -Table parameter you may still specify the target table name. If -Table is not used the file name after the first period will
        be used for the table name.

        For example test.data.csv will import the csv contents to a table in the test schema.

        If it finds one it will use the file name up to the first period as the schema. If there is no period in the filename it will default to dbo.

        If a schema does not currently exist, it will be created, after a prompt to confirm this. Authorization will be set to dbo by default.

        This behaviour will be overridden if the -Schema parameter is specified.

    .PARAMETER TableLock
        If this switch is enabled, the SqlBulkCopy option to acquire a table lock will be used.

        Per Microsoft "Obtain a bulk update lock for the duration of the bulk copy operation. When not
        specified, row locks are used."

    .PARAMETER CheckConstraints
        If this switch is enabled, the SqlBulkCopy option to check constraints will be used.

        Per Microsoft "Check constraints while data is being inserted. By default, constraints are not checked."

    .PARAMETER FireTriggers
        If this switch is enabled, the SqlBulkCopy option to allow insert triggers to be executed will be used.

        Per Microsoft "When specified, cause the server to fire the insert triggers for the rows being inserted into the database."

    .PARAMETER KeepIdentity
        If this switch is enabled, the SqlBulkCopy option to keep identity values from the source will be used.

        Per Microsoft "Preserve source identity values. When not specified, identity values are assigned by the destination."

    .PARAMETER KeepNulls
        If this switch is enabled, the SqlBulkCopy option to keep NULL values in the table will be used.

        Per Microsoft "Preserve null values in the destination table regardless of the settings for default values. When not specified, null values are replaced by default values where applicable."

    .PARAMETER NoProgress
        The progress bar is pretty but can slow down imports. Use this parameter to quietly import.

    .PARAMETER Quote
        Defines the default quote character wrapping every field.
        Default: double-quotes

    .PARAMETER Escape
        Defines the default escape character letting insert quotation characters inside a quoted field.

        The escape character can be the same as the quote character.
        Default: double-quotes

    .PARAMETER Comment
        Defines the default comment character indicating that a line is commented out.
        Default: hashtag

    .PARAMETER TrimmingOption
        Determines which values should be trimmed. Default is "None". Options are All, None, UnquotedOnly and QuotedOnly.

    .PARAMETER BufferSize
        Defines the default buffer size. The default BufferSize is 4096.

    .PARAMETER ParseErrorAction
        By default, the parse error action throws an exception and ends the import.

        You can also choose AdvanceToNextLine which basically ignores parse errors.

    .PARAMETER Encoding
        By default, set to UTF-8.

        The encoding of the file.

    .PARAMETER NullValue
        The value which denotes a DbNull-value.

    .PARAMETER MaxQuotedFieldLength
        The maximum length (in bytes) for any quoted field.

    .PARAMETER SkipEmptyLine
        Skip empty lines.

    .PARAMETER SupportsMultiline
        Indicates if the importer should support multiline fields.

    .PARAMETER UseColumnDefault
        Use the column default values if the field is not in the record.

    .PARAMETER NoTransaction
        Do not use a transaction when performing the import.

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
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Import-DbaCsv

    .EXAMPLE
        PS C:\> Import-DbaCsv -Path C:\temp\housing.csv -SqlInstance sql001 -Database markets

        Imports the entire comma-delimited housing.csv to the SQL "markets" database on a SQL Server named sql001, using the first row as column names.

        Since a table name was not specified, the table name is automatically determined from filename as "housing".

    .EXAMPLE
        PS C:\> Import-DbaCsv -Path .\housing.csv -SqlInstance sql001 -Database markets -Table housing -Delimiter "`t" -NoHeaderRow

        Imports the entire tab-delimited housing.csv, including the first row which is not used for colum names, to the SQL markets database, into the housing table, on a SQL Server named sql001.

    .EXAMPLE
        PS C:\> Import-DbaCsv -Path C:\temp\huge.txt -SqlInstance sqlcluster -Database locations -Table latitudes -Delimiter "|"

        Imports the entire pipe-delimited huge.txt to the locations database, into the latitudes table on a SQL Server named sqlcluster.

    .EXAMPLE
        PS C:\> Import-DbaCsv -Path c:\temp\SingleColumn.csv -SqlInstance sql001 -Database markets -Table TempTable -SingleColumn

        Imports the single column CSV into TempTable

    .EXAMPLE
        PS C:\> Get-ChildItem -Path \\FileServer\csvs | Import-DbaCsv -SqlInstance sql001, sql002 -Database tempdb -AutoCreateTable

        Imports every CSV in the \\FileServer\csvs path into both sql001 and sql002's tempdb database. Each CSV will be imported into an automatically determined table name.

    .EXAMPLE
        PS C:\> Get-ChildItem -Path \\FileServer\csvs | Import-DbaCsv -SqlInstance sql001, sql002 -Database tempdb -AutoCreateTable -WhatIf

        Shows what would happen if the command were to be executed

    .EXAMPLE
        PS C:\> Import-DbaCsv -Path c:\temp\dataset.csv -SqlInstance sql2016 -Database tempdb -Column Name, Address, Mobile

        Import only Name, Address and Mobile even if other columns exist. All other columns are ignored and therefore null or default values.

    .EXAMPLE
        PS C:\> Import-DbaCsv -Path C:\temp\schema.data.csv -SqlInstance sql2016 -database tempdb -UseFileNameForSchema

        Will import the contents of C:\temp\schema.data.csv to table 'data' in schema 'schema'.

    .EXAMPLE
        PS C:\> Import-DbaCsv -Path C:\temp\schema.data.csv -SqlInstance sql2016 -database tempdb -UseFileNameForSchema -Table testtable

        Will import the contents of C:\temp\schema.data.csv to table 'testtable' in schema 'schema'.

    .EXAMPLE
        PS C:\> $columns = @{
        >> Text = 'FirstName'
        >> Number = 'PhoneNumber'
        >> }
        PS C:\> Import-DbaCsv -Path c:\temp\supersmall.csv -SqlInstance sql2016 -Database tempdb -ColumnMap $columns

        The CSV field 'Text' is inserted into SQL column 'FirstName' and CSV field Number is inserted into the SQL Column 'PhoneNumber'. All other columns are ignored and therefore null or default values.

    .EXAMPLE
        PS C:\> $columns = @{
        >> 0 = 'FirstName'
        >> 1 = 'PhoneNumber'
        >> }
        PS C:\> Import-DbaCsv -Path c:\temp\supersmall.csv -SqlInstance sql2016 -Database tempdb -NoHeaderRow -ColumnMap $columns

        If the CSV has no headers, passing a ColumnMap works when you have as the key the ordinal of the column (0-based).
        In this example the first CSV field is inserted into SQL column 'FirstName' and the second CSV field is inserted into the SQL Column 'PhoneNumber'.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param (
        [parameter(ValueFromPipeline)]
        [ValidateNotNullOrEmpty()]
        [Alias("Csv", "FullPath")]
        [object[]]$Path,
        [Parameter(Mandatory)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [Parameter(Mandatory)]
        [string]$Database,
        [string]$Table,
        [string]$Schema,
        [switch]$Truncate,
        [char]$Delimiter = ",",
        [switch]$SingleColumn,
        [int]$BatchSize = 50000,
        [int]$NotifyAfter = 50000,
        [switch]$TableLock,
        [switch]$CheckConstraints,
        [switch]$FireTriggers,
        [switch]$KeepIdentity,
        [switch]$KeepNulls,
        [string[]]$Column,
        [hashtable]$ColumnMap,
        [switch]$KeepOrdinalOrder,
        [switch]$AutoCreateTable,
        [switch]$NoProgress,
        [switch]$NoHeaderRow,
        [switch]$UseFileNameForSchema,
        [char]$Quote = '"',
        [char]$Escape = '"',
        [char]$Comment = '#',
        [ValidateSet('All', 'None', 'UnquotedOnly', 'QuotedOnly')]
        [string]$TrimmingOption = "None",
        [int]$BufferSize = 4096,
        [ValidateSet('AdvanceToNextLine', 'ThrowException')]
        [string]$ParseErrorAction = 'ThrowException',
        [ValidateSet('ASCII', 'BigEndianUnicode', 'Byte', 'String', 'Unicode', 'UTF7', 'UTF8', 'Unknown')]
        [string]$Encoding = 'UTF8',
        [string]$NullValue,
        [int]$MaxQuotedFieldLength,
        [switch]$SkipEmptyLine,
        [switch]$SupportsMultiline,
        [switch]$UseColumnDefault,
        [switch]$NoTransaction,
        [switch]$EnableException
    )
    begin {
        $FirstRowHeader = $NoHeaderRow -eq $false
        $scriptelapsed = [System.Diagnostics.Stopwatch]::StartNew()

        if ($PSBoundParameters.UseFileNameForSchema -and $PSBoundParameters.Schema) {
            Write-Message -Level Warning -Message "Schema and UseFileNameForSchema parameters both specified. UseSchemaInFileName will be ignored."
        }

        function New-SqlTable {
            <#
                .SYNOPSIS
                    Creates new Table using existing SqlCommand.

                    SQL datatypes based on best guess of column data within the -ColumnText parameter.
                    Columns parameter determine column names.

                .EXAMPLE
                    New-SqlTable -Path $Path -Delimiter $Delimiter -Columns $columns -ColumnText $columntext -SqlConn $sqlconn -Transaction $transaction

                .OUTPUTS
                    Creates new table
            #>
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseShouldProcessForStateChangingFunctions", "")]
            param (
                [Parameter(Mandatory)]
                [string]$Path,
                [Parameter(Mandatory)]
                [string]$Delimiter,
                [Parameter(Mandatory)]
                [bool]$FirstRowHeader,
                [Microsoft.Data.SqlClient.SqlConnection]$sqlconn,
                [Microsoft.Data.SqlClient.SqlTransaction]$transaction,
                [bool]$IsCompressed
            )

            $stream = [System.IO.File]::OpenRead($Path);
            if ($IsCompressed) {
                $stream = New-Object System.IO.Compression.GZipStream($stream, [System.IO.Compression.CompressionMode]::Decompress)
            }
            try {
                $reader = New-Object LumenWorks.Framework.IO.Csv.CsvReader(
                    (New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::$Encoding)),
                    $FirstRowHeader,
                    $Delimiter,
                    $Quote,
                    $Escape,
                    $Comment,
                    [LumenWorks.Framework.IO.Csv.ValueTrimmingOptions]::$TrimmingOption,
                    $BufferSize,
                    $NullValue
                )
                $columns = $reader.GetFieldHeaders()
            } finally {
                $reader.Close()
                $reader.Dispose()
            }

            $sqldatatypes = @();

            foreach ($column in $Columns) {
                $sqldatatypes += "[$column] nvarchar(MAX)"
            }

            $sql = "BEGIN CREATE TABLE [$schema].[$table] ($($sqldatatypes -join ' NULL,')) END"
            $sqlcmd = New-Object Microsoft.Data.SqlClient.SqlCommand($sql, $sqlconn, $transaction)

            try {
                $null = $sqlcmd.ExecuteNonQuery()
            } catch {
                $errormessage = $_.Exception.Message.ToString()
                Stop-Function -Continue -Message "Failed to execute $sql. `nDid you specify the proper delimiter? `n$errormessage"
            }

            Write-Message -Level Verbose -Message "Successfully created table $schema.$table with the following column definitions:`n $($sqldatatypes -join "`n ")"
            Write-Message -Level Verbose -Message "This is inefficient but allows the script to import without issues."
            Write-Message -Level Verbose -Message "Consider creating the table first using best practices if the data will be used in production."
        }




        function ConvertTo-DotnetType {
            param (
                [string]$DataType
            )

            switch ($DataType) {
                'BigInt' { return [System.Int64] }
                'Binary' { return [System.Byte[]] }
                'VarBinary' { return [System.Byte[]] }
                'Bit' { return [System.Boolean] }
                'Char' { return [System.String] }
                'VarChar' { return [System.String] }
                'NChar' { return [System.String] }
                'NVarChar' { return [System.String] }
                'DateTime' { return [System.DateTime] }
                'SmallDateTime' { return [System.DateTime] }
                'Date' { return [System.DateTime] }
                'Time' { return [System.DateTime] }
                'DateTime2' { return [System.DateTime] }
                'Decimal' { return [System.Decimal] }
                'Numeric' { return [System.Decimal] }
                'Money' { return [System.Decimal] }
                'SmallMoney' { return [System.Decimal] }
                'Float' { return [System.Double] }
                'Int' { return [System.Int32] }
                'Real' { return [System.Single] }
                'UniqueIdentifier' { return [System.Guid] }
                'SmallInt' { return [System.Int16] }
                'TinyInt' { return [System.Byte] }
                'Xml' { return [System.String] }
                default { throw "Unsupported SMO DataType: $($DataType)" }
            }
        }

        function Get-TableDefinitionFromInfoSchema {
            param (
                [string]$table,
                [string]$schema,
                $sqlconn
            )

            $query = "SELECT c.COLUMN_NAME, c.DATA_TYPE, c.ORDINAL_POSITION - 1 FROM INFORMATION_SCHEMA.COLUMNS AS c WHERE TABLE_SCHEMA = @schema AND TABLE_NAME = @table;"
            $sqlcmd = New-Object Microsoft.Data.SqlClient.SqlCommand($query, $sqlconn, $transaction)
            $null = $sqlcmd.Parameters.AddWithValue('schema', $schema)
            $null = $sqlcmd.Parameters.AddWithValue('table', $table)

            $result = @()
            try {
                $reader = $sqlcmd.ExecuteReader()
                foreach ($dataRow in $reader) {
                    $result += [PSCustomObject]@{
                        Name     = $dataRow[0]
                        DataType = $dataRow[1]
                        Index    = $dataRow[2]
                    }
                }
                $reader.Close()
            } catch {
                # callers report back the error if $result is empty
            }

            return $result
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

            $ext = [System.IO.Path]::GetExtension($file).ToLower()

            $isCompressed = $ext -eq '.gz'

            if (-not $isCompressed) {
                # Does the second line contain the specified delimiter?
                try {
                    $firstlines = Get-Content -Path $file -TotalCount 2 -ErrorAction Stop
                } catch {
                    Stop-Function -Continue -Message "Failure reading $file" -ErrorRecord $_
                }
                if (-not $SingleColumn) {
                    if ($firstlines -notmatch $Delimiter) {
                        Stop-Function -Message "Delimiter ($Delimiter) not found in first few rows of $file. If this is a single column import, please specify -SingleColumn"
                        return
                    }
                }
            }

            $filename = [IO.Path]::GetFileNameWithoutExtension($file)

            # already trimmed the ".gz", if there is a ".csv", trim it as well.
            if ($isCompressed -and $filename.EndsWith(".csv", [System.StringComparison]::OrdinalIgnoreCase)) {
                $filename = [IO.Path]::GetFileNameWithoutExtension($filename)
            }

            # Automatically generate Table name if not specified
            if (-not $PSBoundParameters.Table) {
                if ($filename.IndexOf('.') -ne -1) { $periodFound = $true }

                if ($UseFileNameForSchema -and $periodFound -and -not $PSBoundParameters.Schema) {
                    $table = $filename.Remove(0, $filename.IndexOf('.') + 1)
                    Write-Message -Level Verbose -Message "Table name not specified, using $table from file name"
                } else {
                    $table = $filename
                    Write-Message -Level Verbose -Message "Table name not specified, using $table"
                }
            }

            # Use dbo as schema name if not specified in params, or as first string before a period in filename
            if (-not ($PSBoundParameters.Schema)) {
                if ($UseFileNameForSchema) {
                    if ($filename.IndexOf('.') -eq -1) {
                        $schema = "dbo"
                        Write-Message -Level Verbose -Message "Schema not specified, and not found in file name, using dbo"
                    } else {
                        $schema = $filename.SubString(0, $filename.IndexOf('.'))
                        Write-Message -Level Verbose -Message "Schema detected in filename, using $schema"
                    }
                } else {
                    $schema = 'dbo'
                    Write-Message -Level Verbose -Message "Schema not specified, using dbo"
                }
            }

            foreach ($instance in $SqlInstance) {
                $elapsed = [System.Diagnostics.Stopwatch]::StartNew()
                # Open Connection to SQL Server
                try {
                    $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -Database $Database -MinimumVersion 9
                    $sqlconn = $server.ConnectionContext.SqlConnectionObject
                    if ($sqlconn.State -ne 'Open') {
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
                $sql = "select count(*) from sys.schemas where name = @schema"
                $sqlcmd = New-Object Microsoft.Data.SqlClient.SqlCommand($sql, $sqlconn, $transaction)
                $null = $sqlcmd.Parameters.AddWithValue('schema', $schema)
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
                $sql = "select count(*) from sys.tables where name = @table and schema_id = schema_id(@schema)"
                $sqlcmd = New-Object Microsoft.Data.SqlClient.SqlCommand($sql, $sqlconn, $transaction)
                $null = $sqlcmd.Parameters.AddWithValue('schema', $schema)
                $null = $sqlcmd.Parameters.AddWithValue('table', $table)

                $sql2 = "select count(*) from sys.views where name = @table and schema_id=schema_id(@schema)"
                $sqlcmd2 = New-Object Microsoft.Data.SqlClient.SqlCommand($sql2, $sqlconn, $transaction)
                $null = $sqlcmd2.Parameters.AddWithValue('schema', $schema)
                $null = $sqlcmd2.Parameters.AddWithValue('table', $table)

                # this variable enables the machinery that needs to build a precise mapping from the table definition
                # to the type of the columns BulkCopy needs. Lumen has support for it, but since it's a tad bit expensive
                # we opt-in only if the table already exists but not when we create the default table (which is basic, and it's all nvarchar(max)s columns)
                $shouldMapCorrectTypes = $false


                # Create the table if required. Remember, this will occur within a transaction, so if the script fails, the
                # new table will no longer exist.
                if (($sqlcmd.ExecuteScalar()) -eq 0 -and ($sqlcmd2.ExecuteScalar()) -eq 0) {
                    if (-not $AutoCreateTable) {
                        Stop-Function -Continue -Message "Table or view $table does not exist and AutoCreateTable was not specified"
                    }
                    Write-Message -Level Verbose -Message "Table does not exist"
                    if ($PSCmdlet.ShouldProcess($instance, "Creating table $table")) {
                        try {
                            New-SqlTable -Path $file -Delimiter $Delimiter -FirstRowHeader $FirstRowHeader -SqlConn $sqlconn -Transaction $transaction -IsCompressed $isCompressed
                        } catch {
                            Stop-Function -Continue -Message "Failure" -ErrorRecord $_
                        }
                    }
                } else {
                    $shouldMapCorrectTypes = $true
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
                $options = "TableLock", "CheckConstraints", "FireTriggers", "KeepIdentity", "KeepNulls"
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

                        # If the first column has quotes, then we have to setup a column map
                        $quotematch = (Get-Content -Path $file -TotalCount 1 -ErrorAction Stop).ToString()

                        if ((-not $KeepOrdinalOrder -and -not $AutoCreateTable) -or ($quotematch -match "'" -or $quotematch -match '"')) {
                            if ($ColumnMap) {
                                Write-Message -Level Verbose -Message "ColumnMap was supplied. Additional auto-mapping will not be attempted."
                            } elseif ($NoHeaderRow) {
                                Write-Message -Level Verbose -Message "NoHeaderRow was supplied. Additional auto-mapping will not be attempted."
                            } else {
                                try {
                                    $ColumnMap = @{ }
                                    $firstline = Get-Content -Path $file -TotalCount 1 -ErrorAction Stop
                                    $firstline -split "$Delimiter", 0, "SimpleMatch" | ForEach-Object {
                                        $trimmed = $PSItem.Trim('"')
                                        Write-Message -Level Verbose -Message "Adding $trimmed to ColumnMap"
                                        $ColumnMap.Add($trimmed, $trimmed)
                                    }
                                } catch {
                                    # oh well, we tried
                                    Write-Message -Level Verbose -Message "Couldn't auto create ColumnMap :("
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


                    } catch {
                        Stop-Function -Continue -Message "Failure" -ErrorRecord $_
                    }

                    # Write to server :D
                    try {

                        [Action[double]] $progressCallback = {
                            param($progress)

                            if (-not $NoProgress) {
                                $timetaken = [math]::Round($elapsed.Elapsed.TotalSeconds, 2)
                                $percent = [int]($progress * 100)
                                Write-ProgressHelper -StepNumber $percent -TotalSteps 100 -Activity "Importing from $file" -Message ([System.String]::Format("Progress: {0} rows {1}% in {2} seconds", $script:totalRowsCopied, $percent, $timetaken))
                            }
                        }

                        $stream = [System.IO.File]::OpenRead($File);
                        $stream = New-Object Dataplat.Dbatools.IO.ProgressStream($stream, $progressCallback, 0.05)

                        if ($isCompressed) {
                            $stream = New-Object System.IO.Compression.GZipStream($stream, [System.IO.Compression.CompressionMode]::Decompress)
                        }

                        $textReader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::$Encoding)

                        $reader = New-Object LumenWorks.Framework.IO.Csv.CsvReader(
                            $textReader,
                            $FirstRowHeader,
                            $Delimiter,
                            $Quote,
                            $Escape,
                            $Comment,
                            [LumenWorks.Framework.IO.Csv.ValueTrimmingOptions]::$TrimmingOption,
                            $BufferSize,
                            $NullValue
                        )

                        if ($shouldMapCorrectTypes) {

                            if ($FirstRowHeader) {

                                # we can get default columns, all strings. This "fills" the $reader.Columns list, that we use later
                                $null = $reader.GetFieldHeaders()
                                # we get the table definition
                                # we do not use $server because the connection is active here
                                $tableDef = Get-TableDefinitionFromInfoSchema -table $table -schema $schema -sqlconn $sqlconn
                                if ($tableDef.Length -eq 0) {
                                    Stop-Function -Message "Could not fetch table definition for table $table in schema $schema"
                                }
                                foreach ($bcMapping in $bulkcopy.ColumnMappings) {
                                    # loop over mappings, we need to be careful and assign the correct type
                                    $colNameFromSql = $bcMapping.DestinationColumn
                                    $colNameFromCsv = $bcMapping.SourceColumn
                                    foreach ($sqlCol in $tableDef) {
                                        if ($sqlCol.Name -eq $colNameFromSql) {
                                            # now we know the column, we need to get the type, let's be extra-obvious here
                                            $colTypeFromSql = $sqlCol.DataType
                                            # and now we translate to C# type
                                            $colTypeCSharp = ConvertTo-DotnetType -DataType $colTypeFromSql
                                            # and now we assign the type to the LumenCsv column
                                            foreach ($csvCol in $reader.Columns) {
                                                if ($csvCol.Name -eq $colNameFromCsv) {
                                                    $csvCol.Type = $colTypeCSharp
                                                    Write-Message -Level Verbose -Message "Mapped $colNameFromCsv --> $colNameFromSql ($colTypeCSharp --> $colTypeFromSql)"
                                                    break
                                                }
                                            }
                                            break
                                        }
                                    }
                                }
                            } else {
                                # we need to resort to ordinals
                                # start by getting the table definition
                                $tableDef = Get-TableDefinitionFromInfoSchema -table $table -schema $schema -sqlconn $sqlconn
                                if ($tableDef.Length -eq 0) {
                                    Stop-Function -Message "Could not fetch table definition for table $table in schema $schema"
                                }
                                if ($bulkcopy.ColumnMappings.Count -eq 0) {
                                    # if we land here, we aren't (probably ? ) forcing any mappings, but we kinda need them for later
                                    foreach ($dataRow in $tableDef) {
                                        $null = $bulkcopy.ColumnMappings.Add($dataRow.Index, $dataRow.Index)
                                    }
                                }
                                # ok we got the mappings sorted

                                # we must build Lumen's columns by hand here, we can't use GetFieldHeaders()
                                $reader.Columns = New-Object System.Collections.Generic.List[LumenWorks.Framework.IO.Csv.Column]

                                foreach ($bcMapping in $bulkcopy.ColumnMappings) {
                                    # loop over mappings, we need to be careful and assign the correct type, and we're in the "natural" order of the CSV fields
                                    $colNameFromSql = $bcMapping.DestinationOrdinal
                                    $colNameFromCsv = $bcMapping.SourceOrdinal
                                    $newcol = New-Object LumenWorks.Framework.IO.Csv.Column
                                    $newcol.Name = "c$(Get-Random)" # need to assign a name, it's required for Lumen even if we're mapping just by ordinal
                                    foreach ($sqlCol in $tableDef) {
                                        if ($bcMapping.DestinationOrdinal -eq -1) {
                                            # we can map by name
                                            $colNameFromSql = $bcMapping.DestinationColumn
                                            $sqlColComparison = $sqlCol.Name
                                        } else {
                                            # we fallback to mapping by index
                                            $colNameFromSql = $bcMapping.DestinationOrdinal
                                            $sqlColComparison = $sqlCol.Index
                                        }
                                        if ($sqlColComparison -eq $colNameFromSql) {
                                            $colTypeFromSql = $sqlCol.DataType
                                            # and now we translate to C# type
                                            $colTypeCSharp = ConvertTo-DotnetType -DataType $colTypeFromSql
                                            # assign it to the column
                                            $newcol.Type = $colTypeCSharp
                                            # and adding to the column collection
                                            $null = $reader.Columns.Add($newcol)
                                            Write-Message -Level Verbose -Message "Mapped $colNameFromSql --> $colNameFromCsv ($colTypeCSharp --> $colTypeFromSql)"
                                            break
                                        }
                                    }
                                }
                            }
                        }

                        if ($PSBoundParameters.MaxQuotedFieldLength) {
                            $reader.MaxQuotedFieldLength = $MaxQuotedFieldLength
                        }
                        if ($PSBoundParameters.SkipEmptyLine) {
                            $reader.SkipEmptyLines = $SkipEmptyLine
                        }
                        if ($PSBoundParameters.SupportsMultiline) {
                            $reader.SupportsMultiline = $SupportsMultiline
                        }
                        if ($PSBoundParameters.UseColumnDefault) {
                            $reader.UseColumnDefaults = $UseColumnDefault
                        }
                        if ($PSBoundParameters.ParseErrorAction) {
                            $reader.DefaultParseErrorAction = $ParseErrorAction
                        }

                        # The legacy bulk copy library uses a 4 byte integer to track the RowsCopied, so the only option is to use
                        # integer wrap so that copy operations of row counts greater than [int32]::MaxValue will report accurate numbers.
                        # See https://github.com/dataplat/dbatools/issues/6927 for more details
                        $script:prevRowsCopied = [int64]0
                        $script:totalRowsCopied = [int64]0

                        # Add rowcount output
                        $bulkCopy.Add_SqlRowsCopied( {
                                $script:totalRowsCopied += (Get-AdjustedTotalRowsCopied -ReportedRowsCopied $args[1].RowsCopied -PreviousRowsCopied $script:prevRowsCopied).NewRowCountAdded

                                Write-Message -Level Verbose -FunctionName "Import-DbaCsv" -Message " Total rows copied = $($script:totalRowsCopied)"
                                # progress is written by the ProgressStream callback
                                # save the previous count of rows copied to be used on the next event notification
                                $script:prevRowsCopied = $args[1].RowsCopied
                            })

                        $bulkCopy.WriteToServer($reader)

                        $completed = $true
                    } catch {
                        $completed = $false
                        Stop-Function -Continue -Message "Failure" -ErrorRecord $_
                    } finally {
                        try {
                            $reader.Close()
                            $reader.Dispose()
                        } catch {
                        }

                        if (-not $NoTransaction) {
                            if ($completed) {
                                try {
                                    $null = $transaction.Commit()
                                } catch {
                                }
                            } else {
                                try {
                                    $null = $transaction.Rollback()
                                } catch {
                                }
                            }
                        }

                        try {
                            $sqlconn.Close()
                            $sqlconn.Dispose()
                        } catch {
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
                        Stop-Function -Message "Transaction rolled back. Was the proper delimiter specified? Is the first row the column name?"
                        return
                    }
                }
            }
        }
    }
    end {
        # Close everything just in case & ignore errors
        try {
            $null = $sqlconn.Close(); $null = $sqlconn.Dispose();
            $null = $bulkCopy.Close(); $bulkcopy.Dispose();
            $null = $reader.Close(); $null = $reader.Dispose()
        } catch {
            #here to avoid an empty catch
            $null = 1
        }

        # Script is finished. Show elapsed time.
        $totaltime = [math]::Round($scriptelapsed.Elapsed.TotalSeconds, 2)
        Write-Message -Level Verbose -Message "Total Elapsed Time for everything: $totaltime seconds"
    }
}