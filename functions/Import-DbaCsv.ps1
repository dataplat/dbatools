function Import-DbaCsv {
    <#
    .SYNOPSIS
        Efficiently imports very large (and small) CSV files into SQL Server.

    .DESCRIPTION
        Import-DbaCsv takes advantage of .NET's super fast SqlBulkCopy class to import CSV files into SQL Server.

        The entire import is performed within a transaction, so if a failure occurs or the script is aborted, no changes will persist.

        If the table or view specified does not exist and -AutoCreateTable, it will be automatically created using slow and inefficient but accommodating data types.

        This importer supports fields spanning multiple lines. The only restriction is that they must be quoted, otherwise it would not be possible to distinguish between malformed data and multi-line values.

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
        The maxmimum length (in bytes) for any quoted field.

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
        Tags: Migration, Import
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

        The CSV column 'Text' is inserted into SQL column 'FirstName' and CSV column Number is inserted into the SQL Column 'PhoneNumber'. All other columns are ignored and therefore null or default values.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param (
        [parameter(ValueFromPipeline)]
        [ValidateNotNullOrEmpty()]
        [Alias("Csv", "FullPath")]
        [object[]]$Path,
        [Parameter(Mandatory)]
        [DbaInstanceParameter[]]$SqlInstance,
        [pscredential]$SqlCredential,
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
        [hashtable[]]$ColumnMap,
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

        try {
            # SilentContinue isn't enough
            Add-Type -Path "$script:PSModuleRoot\bin\csv\LumenWorks.Framework.IO.dll" -ErrorAction Stop
        } catch {
            $null = 1
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
                [System.Data.SqlClient.SqlConnection]$sqlconn,
                [System.Data.SqlClient.SqlTransaction]$transaction
            )
            $reader = New-Object LumenWorks.Framework.IO.Csv.CsvReader(
                (New-Object System.IO.StreamReader($Path, [System.Text.Encoding]::$Encoding)),
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
            $reader.Close()
            $reader.Dispose()

            # Get SQL datatypes by best guess on first data row
            $sqldatatypes = @();

            foreach ($column in $Columns) {
                $sqldatatypes += "[$column] varchar(MAX)"
            }

            $sql = "BEGIN CREATE TABLE [$schema].[$table] ($($sqldatatypes -join ' NULL,')) END"
            $sqlcmd = New-Object System.Data.SqlClient.SqlCommand($sql, $sqlconn, $transaction)

            try {
                $null = $sqlcmd.ExecuteNonQuery()
            } catch {
                $errormessage = $_.Exception.Message.ToString()
                Stop-Function -Continue -Message "Failed to execute $sql. `nDid you specify the proper delimiter? `n$errormessage"
            }

            Write-Message -Level Verbose -Message "Successfully created table $schema.$table with the following column definitions:`n $($sqldatatypes -join "`n ")"
            # Write-Message -Level Warning -Message "All columns are created using a best guess, and use their maximum datatype."
            Write-Message -Level Verbose -Message "This is inefficient but allows the script to import without issues."
            Write-Message -Level Verbose -Message "Consider creating the table first using best practices if the data will be used in production."
        }

        Write-Message -Level Verbose -Message "Started at $(Get-Date)"
    }
    process {
        foreach ($filename in $Path) {

            if ($filename.FullName) {
                $filename = $filename.FullName
            }

            if (-not (Test-Path -Path $filename)) {
                Stop-Function -Continue -Message "$filename cannot be found"
            }

            $file = (Resolve-Path -Path $filename).ProviderPath

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

            # Automatically generate Table name if not specified
            if (-not $PSBoundParameters.Table) {
                $filename = [IO.Path]::GetFileNameWithoutExtension($file)

                if ($filename.IndexOf('.') -ne -1) { $periodFound = $true }

                if ($UseFileNameForSchema -and $periodFound -and -not $PSBoundParameters.Schema) {
                    $table = $filename.Remove(0, $filename.IndexOf('.') + 1)
                    Write-Message -Level Verbose -Message "Table name not specified, using $table from file name"
                } else {
                    $table = [IO.Path]::GetFileNameWithoutExtension($file)
                    Write-Message -Level Verbose -Message "Table name not specified, using $table"
                }
            }

            # Use dbo as schema name if not specified in parms, or as first string before a period in filename
            if (-not ($PSBoundParameters.Schema)) {
                if ($UseFileNameForSchema) {
                    $filename = [IO.Path]::GetFileNameWithoutExtension($file)
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
                    $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -StatementTimeout 0 -MinimumVersion 9
                    $sqlconn = $server.ConnectionContext.SqlConnectionObject
                    if ($sqlconn.State -ne 'Open') {
                        $sqlconn.Open()
                    }
                } catch {
                    Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
                }

                if (-not $NoTransaction) {
                    if ($PSCmdlet.ShouldProcess($instance, "Starting transaction in $Database")) {
                        # Everything will be contained within 1 transaction, even creating a new table if required
                        # and truncating the table, if specified.
                        $transaction = $sqlconn.BeginTransaction()
                    }
                }

                # Ensure database exists
                $sql = "select count(*) from master.dbo.sysdatabases where name = '$Database'"
                $sqlcmd = New-Object System.Data.SqlClient.SqlCommand($sql, $sqlconn, $transaction)
                if (($sqlcmd.ExecuteScalar()) -eq 0) {
                    Stop-Function -Continue -Message "Database does not exist on $instance"
                }
                Write-Message -Level Verbose -Message "Database exists"
                $sqlconn.ChangeDatabase($Database)

                # Ensure Schema exists
                $sql = "select count(*) from [$Database].sys.schemas where name='$schema'"
                $sqlcmd = New-Object System.Data.SqlClient.SqlCommand($sql, $sqlconn, $transaction)

                # If Schema doesn't exist create it
                # Defaulting to dbo.
                if (($sqlcmd.ExecuteScalar()) -eq 0) {
                    if (-not $AutoCreateTable) {
                        Stop-Function -Continue -Message "Schema $Schema does not exist and AutoCreateTable was not specified"
                    }
                    $sql = "CREATE SCHEMA [$schema] AUTHORIZATION dbo"
                    if ($PSCmdlet.ShouldProcess($instance, "Creating schema $schema")) {
                        $sqlcmd = New-Object System.Data.SqlClient.SqlCommand($sql, $sqlconn, $transaction)
                        try {
                            $null = $sqlcmd.ExecuteNonQuery()
                        } catch {
                            Stop-Function -Continue -Message "Could not create $schema" -ErrorRecord $_
                        }
                    }
                }

                # Ensure table or view exists
                $sql = "select count(*) from [$Database].sys.tables where name = '$table' and schema_id=schema_id('$schema')"
                $sqlcmd = New-Object System.Data.SqlClient.SqlCommand($sql, $sqlconn, $transaction)

                $sql2 = "select count(*) from [$Database].sys.views where name = '$table' and schema_id=schema_id('$schema')"
                $sqlcmd2 = New-Object System.Data.SqlClient.SqlCommand($sql2, $sqlconn, $transaction)

                # Create the table if required. Remember, this will occur within a transaction, so if the script fails, the
                # new table will no longer exist.
                if (($sqlcmd.ExecuteScalar()) -eq 0 -and ($sqlcmd2.ExecuteScalar()) -eq 0) {
                    if (-not $AutoCreateTable) {
                        Stop-Function -Continue -Message "Table or view $table does not exist and AutoCreateTable was not specified"
                    }
                    Write-Message -Level Verbose -Message "Table does not exist"
                    if ($PSCmdlet.ShouldProcess($instance, "Creating table $table")) {
                        try {
                            New-SqlTable -Path $file -Delimiter $Delimiter -FirstRowHeader $FirstRowHeader -SqlConn $sqlconn -Transaction $transaction
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
                        $sqlcmd = New-Object System.Data.SqlClient.SqlCommand($sql, $sqlconn, $transaction)
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
                [int]$bulkCopyOptions = ([System.Data.SqlClient.SqlBulkCopyOptions]::Default)
                $options = "TableLock", "CheckConstraints", "FireTriggers", "KeepIdentity", "KeepNulls"
                foreach ($option in $options) {
                    $optionValue = Get-Variable $option -ValueOnly -ErrorAction SilentlyContinue
                    if ($optionValue -eq $true) {
                        $bulkCopyOptions += $([System.Data.SqlClient.SqlBulkCopyOptions]::$option).value__
                    }
                }

                if ($PSCmdlet.ShouldProcess($instance, "Performing import from $file")) {
                    try {
                        # Create SqlBulkCopy using default options, or options specified in command line.
                        if ($bulkCopyOptions) {
                            $bulkcopy = New-Object Data.SqlClient.SqlBulkCopy($sqlconn, $bulkCopyOptions, $transaction)
                        } else {
                            $bulkcopy = New-Object Data.SqlClient.SqlBulkCopy($sqlconn, ([System.Data.SqlClient.SqlBulkCopyOptions]::Default), $transaction)
                        }

                        $bulkcopy.DestinationTableName = "[$schema].[$table]"
                        $bulkcopy.BulkCopyTimeout = 0
                        $bulkCopy.BatchSize = $BatchSize
                        $bulkCopy.NotifyAfter = $NotifyAfter
                        $bulkCopy.EnableStreaming = $true

                        if (-not $KeepOrdinalOrder -and -not $AutoCreateTable) {
                            if ($ColumnMap) {
                                Write-Message -Level Verbose -Message "ColumnMap was supplied. Additional auto-mapping will not be attempted."
                            } else {
                                try {
                                    $firstline = Get-Content -Path $file -TotalCount 1 -ErrorAction Stop
                                    $ColumnMapping = @{ }
                                    $firstline -split "$Delimiter", 0, "SimpleMatch" | ForEach-Object {
                                        $ColumnMapping.Add($_, $_)
                                    }
                                    $ColumnMap += $ColumnMapping
                                } catch {
                                    # oh well, we tried
                                    $ColumnMap = $null
                                }
                            }
                        }

                        if ($ColumnMap) {
                            foreach ($columnname in $ColumnMap) {
                                foreach ($key in $columnname.Keys) {
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
                        $reader = New-Object LumenWorks.Framework.IO.Csv.CsvReader(
                            (New-Object System.IO.StreamReader($file, [System.Text.Encoding]::$Encoding)),
                            $FirstRowHeader,
                            $Delimiter,
                            $Quote,
                            $Escape,
                            $Comment,
                            [LumenWorks.Framework.IO.Csv.ValueTrimmingOptions]::$TrimmingOption,
                            $BufferSize,
                            $NullValue
                        )

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

                        # Add rowcount output
                        $bulkCopy.Add_SqlRowsCopied( {
                                $script:totalrows = $args[1].RowsCopied
                                if (-not $NoProgress) {
                                    $timetaken = [math]::Round($elapsed.Elapsed.TotalSeconds, 2)
                                    Write-ProgressHelper -StepNumber 1 -TotalSteps 2 -Activity "Importing from $file" -Message ([System.String]::Format("Progress: {0} rows in {2} seconds", $script:totalrows, $percent, $timetaken)) -ExcludePercent
                                }
                            })

                        $bulkCopy.WriteToServer($reader)

                        if ($resultcount -is [int]) {
                            Write-Progress -id 1 -activity "Inserting $resultcount rows" -status "Complete" -Completed
                        }

                        $reader.Close()
                        $reader.Dispose()
                        $completed = $true
                    } catch {
                        $completed = $false

                        if ($resultcount -is [int]) {
                            Write-Progress -id 1 -activity "Inserting $resultcount rows" -status "Failed" -Completed
                        }
                        Stop-Function -Continue -Message "Failure" -ErrorRecord $_
                    }
                }
                if ($PSCmdlet.ShouldProcess($instance, "Finalizing import")) {
                    if ($completed) {
                        # "Note: This count does not take into consideration the number of rows actually inserted when Ignore Duplicates is set to ON."
                        if (-not $NoTransaction) {
                            $null = $transaction.Commit()
                        }
                        $rowscopied = Get-BulkRowsCopiedCount $bulkcopy
                        $rps = [int]($rowscopied / $elapsed.Elapsed.TotalSeconds)

                        Write-Message -Level Verbose -Message "$rowscopied total rows copied"

                        [pscustomobject]@{
                            ComputerName  = $server.ComputerName
                            InstanceName  = $server.ServiceName
                            SqlInstance   = $server.DomainInstanceName
                            Database      = $Database
                            Table         = $table
                            Schema        = $schema
                            RowsCopied    = $rowscopied
                            Elapsed       = [prettytimespan]$elapsed.Elapsed
                            RowsPerSecond = $rps
                            Path          = $file
                        }
                    } else {
                        Stop-Function -Message "Transaction rolled back. Was the proper delimiter specified? Is the first row the column name?" -ErrorRecord $_
                        return
                    }
                }

                # Close everything just in case & ignore errors
                try {
                    $null = $sqlconn.close(); $null = $sqlconn.Dispose();
                    $null = $bulkCopy.close(); $bulkcopy.dispose();
                    $null = $reader.close(); $null = $reader.dispose()
                } catch {
                    #here to avoid an empty catch
                    $null = 1
                }
            }
        }
    }
    end {
        # Close everything just in case & ignore errors
        try {
            $null = $sqlconn.close(); $null = $sqlconn.Dispose();
            $null = $bulkCopy.close(); $bulkcopy.dispose();
            $null = $reader.close(); $null = $reader.dispose()
        } catch {
            #here to avoid an empty catch
            $null = 1
        }

        # Script is finished. Show elapsed time.
        $totaltime = [math]::Round($scriptelapsed.Elapsed.TotalSeconds, 2)
        Write-Message -Level Verbose -Message "Total Elapsed Time for everything: $totaltime seconds"
    }
}
