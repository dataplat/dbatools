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
        Specifies the file path to CSV files for import. Supports single files, multiple files, or pipeline input from Get-ChildItem.
        Accepts .csv files and compressed .csv.gz files for large datasets with automatic decompression.

    .PARAMETER NoHeaderRow
        Treats the first row as data instead of column headers. Use this when your CSV file starts directly with data rows.
        When enabled, columns are mapped by ordinal position and you'll need to ensure your target table column order matches the CSV.

    .PARAMETER Delimiter
        Sets the field separator used in the CSV file. Defaults to comma if not specified.
        Common values include comma (,), tab (`t), pipe (|), semicolon (;), or space for different export formats from various systems.
        Multi-character delimiters are fully supported (e.g., "::", "||", "\t\t").

    .PARAMETER SingleColumn
        Indicates the CSV contains only one column of data without delimiters. Use this for simple lists or single-value imports.
        Prevents the function from failing when no delimiter is found in the file content.

    .PARAMETER SqlInstance
        The SQL Server Instance to import data into.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies the target database for the CSV import. The database must exist on the SQL Server instance.
        Use this to direct your data load to the appropriate database, whether it's a staging, ETL, or production database.

    .PARAMETER Schema
        Specifies the target schema for the table. Defaults to 'dbo' if not specified.
        If the schema doesn't exist, it will be created automatically when using -AutoCreateTable. This parameter takes precedence over -UseFileNameForSchema.

    .PARAMETER Table
        Specifies the destination table name. If omitted, uses the CSV filename as the table name.
        The table will be created automatically with -AutoCreateTable using nvarchar(max) columns, but for production use, create the table first with proper data types and constraints.

    .PARAMETER Column
        Imports only the specified columns from the CSV file, ignoring all others. Column names must match exactly.
        Use this to selectively load data when you only need certain fields, reducing import time and storage requirements.

    .PARAMETER ColumnMap
        Maps CSV columns to different table column names using a hashtable. Keys are CSV column names, values are table column names.
        Use this when your CSV headers don't match your table structure or when importing from systems with different naming conventions.

    .PARAMETER KeepOrdinalOrder
        Maps columns by position rather than by name matching. The first CSV column goes to the first table column, second to second, etc.
        Use this when column names don't match but the order is correct, or when dealing with files that have inconsistent header naming.

    .PARAMETER AutoCreateTable
        Creates the destination table automatically if it doesn't exist, using nvarchar(max) for all columns.
        Convenient for quick imports or testing, but for production use, create tables manually with appropriate data types, indexes, and constraints.

    .PARAMETER Truncate
        Removes all existing data from the destination table before importing. The truncate operation is part of the transaction.
        Use this for full data refreshes where you want to replace all existing data with the CSV contents.

    .PARAMETER NotifyAfter
        Sets how often progress notifications are displayed during the import, measured in rows. Defaults to 50,000.
        Lower values provide more frequent updates but may slow the import slightly, while higher values reduce overhead for very large files.

    .PARAMETER BatchSize
        Controls how many rows are sent to SQL Server in each batch during the bulk copy operation. Defaults to 50,000.
        Larger batches are generally more efficient but use more memory, while smaller batches provide better granular control and error isolation.

    .PARAMETER UseFileNameForSchema
        Extracts the schema name from the filename using the first period as a delimiter. For example, 'sales.customers.csv' imports to the 'sales' schema.
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
        Preserves identity column values from the CSV instead of generating new ones. By default, the destination assigns new identity values.
        Use this when migrating data and you need to maintain existing primary key values or referential integrity.

    .PARAMETER KeepNulls
        Preserves NULL values from the CSV instead of replacing them with column default values.
        Use this when your data intentionally contains NULLs that should be maintained, rather than having them replaced by table defaults.

    .PARAMETER NoProgress
        Disables the progress bar display during import to improve performance, especially for very large files.
        Use this in automated scripts or when maximum import speed is more important than visual progress feedback.

    .PARAMETER Quote
        Specifies the character used to quote fields containing delimiters or special characters. Defaults to double-quote (").
        Change this when your CSV uses different quoting conventions, such as single quotes from certain export tools.

    .PARAMETER Escape
        Specifies the character used to escape quote characters within quoted fields. Defaults to double-quote (").
        Modify this when dealing with CSV files that use different escaping conventions, such as backslash escaping.

    .PARAMETER Comment
        Specifies the character that marks comment lines to be ignored during import. Defaults to hashtag (#).
        Use this when your CSV files contain comment lines with metadata or instructions that should be skipped.

    .PARAMETER TrimmingOption
        Controls automatic whitespace removal from field values. Options are All, None, UnquotedOnly, or QuotedOnly.
        Use 'All' to clean up data with inconsistent spacing, or 'None' to preserve exact formatting when whitespace is significant.

    .PARAMETER BufferSize
        Sets the internal buffer size in bytes for reading the CSV file. Defaults to 4096 bytes.
        Increase this value for better performance with very large files, but it will use more memory during the import process.

    .PARAMETER ParseErrorAction
        Determines how to handle malformed rows during import. 'ThrowException' stops the import, 'AdvanceToNextLine' skips bad rows.
        Use 'AdvanceToNextLine' for importing data with known quality issues where you want to load as much valid data as possible.

    .PARAMETER Encoding
        Specifies the text encoding of the CSV file. Defaults to UTF-8.
        Change this when dealing with files from legacy systems that use different encodings like ASCII or when dealing with international character sets.

    .PARAMETER NullValue
        Specifies which text value in the CSV should be treated as SQL NULL. Common values include 'NULL', 'null', or empty strings.
        Use this when your source system exports NULL values as specific text strings that need to be converted to database NULLs.

    .PARAMETER MaxQuotedFieldLength
        Sets the maximum allowed length in bytes for quoted fields to prevent memory issues with malformed data.
        Increase this when working with legitimate large text fields, or decrease it to catch data quality issues early.

    .PARAMETER SkipEmptyLine
        Ignores completely empty lines in the CSV file during import.
        Use this when your source files contain blank lines for formatting that should not create empty rows in your table.

    .PARAMETER SupportsMultiline
        Allows field values to span multiple lines when properly quoted, such as addresses or comments with embedded line breaks.
        Enable this when your CSV contains multi-line text data that should be preserved as single field values.

    .PARAMETER UseColumnDefault
        Applies table column default values when CSV fields are missing or empty.
        Use this when your CSV doesn't include all table columns and you want defaults applied rather than NULLs or import failures.

    .PARAMETER NoTransaction
        Disables the automatic transaction wrapper, allowing partial imports to remain committed even if the operation fails.
        Use this for very large imports where you want to commit data in batches, but be aware that failed imports may leave partial data.

    .PARAMETER MaxDecompressedSize
        Maximum size in bytes for decompressed data when reading compressed CSV files (.gz, .br, .deflate, .zlib).
        This protects against decompression bomb attacks. Default is 10GB (10737418240 bytes).
        Set to 0 for unlimited (not recommended for untrusted files).

    .PARAMETER SkipRows
        Number of rows to skip at the beginning of the file before reading headers or data.
        Useful for files with metadata rows before the actual CSV content.

    .PARAMETER QuoteMode
        Controls how quoted fields are parsed.
        - Strict: RFC 4180 compliant parsing (default)
        - Lenient: More forgiving parsing for malformed CSV files with embedded quotes

    .PARAMETER DuplicateHeaderBehavior
        Controls how duplicate column headers are handled.
        - ThrowException: Throw an error (default)
        - Rename: Rename duplicates (Name_2, Name_3, etc.)
        - UseFirstOccurrence: Keep first, ignore duplicates
        - UseLastOccurrence: Keep last, rename earlier occurrences

    .PARAMETER MismatchedFieldAction
        Controls what happens when a row has more or fewer fields than expected.
        - ThrowException: Throw an error (default)
        - PadWithNulls: Pad missing fields with null
        - TruncateExtra: Remove extra fields
        - PadOrTruncate: Both pad and truncate as needed

    .PARAMETER DistinguishEmptyFromNull
        When specified, treats empty quoted fields ("") as empty strings and
        unquoted empty fields (,,) as null values.

    .PARAMETER NormalizeQuotes
        When specified, converts smart/curly quotes (' ' " ") to standard ASCII quotes before parsing.
        Useful when importing data exported from Microsoft Word or Excel.

    .PARAMETER CollectParseErrors
        When specified, collects parse errors instead of throwing immediately.
        Use with -MaxParseErrors to limit the number of errors collected.
        Errors can be retrieved from the reader after import completes.

    .PARAMETER MaxParseErrors
        Maximum number of parse errors to collect before stopping.
        Only applies when -CollectParseErrors is specified. Default is 1000.

    .PARAMETER StaticColumns
        A hashtable of static column names and values to add to every row.
        Useful for tagging imported data with metadata like source filename or import timestamp.
        Keys are column names, values are the static values to insert.
        Example: @{ SourceFile = "data.csv"; ImportDate = (Get-Date) }

    .PARAMETER DateTimeFormats
        An array of custom date/time format strings for parsing date columns.
        Useful when importing data with non-standard date formats (e.g., Oracle's dd-MMM-yyyy).
        Example: @("dd-MMM-yyyy", "yyyy/MM/dd", "MM-dd-yyyy")

    .PARAMETER Culture
        The culture name to use for parsing numbers and dates (e.g., "de-DE", "fr-FR", "en-US").
        Useful when importing CSV files with locale-specific number formats (e.g., comma as decimal separator).
        Default is InvariantCulture.

    .PARAMETER SampleRows
        Enables smart type detection by sampling the first N rows of the CSV file.
        When specified, the command analyzes the sample to infer optimal SQL Server column types
        instead of using nvarchar(MAX) for all columns.

        This is faster than -DetectColumnTypes but has a small risk if data patterns change
        after the sampled rows (e.g., row 10001 has a longer string than any in the sample).

        Implies -AutoCreateTable behavior for type detection.

        Example: -SampleRows 10000 samples the first 10,000 rows to determine types like
        int, bigint, decimal(p,s), datetime2, bit, uniqueidentifier, or varchar(n)/nvarchar(n)
        with appropriate lengths.

    .PARAMETER DetectColumnTypes
        Enables smart type detection by scanning the entire CSV file before import.
        This guarantees no import failures due to type mismatches but requires reading
        the file twice (once for analysis, once for import).

        A separate progress bar is displayed during the type detection phase.
        The final output (Elapsed, RowsPerSecond) reflects only the import time,
        not the detection overhead.

        Implies -AutoCreateTable behavior for type detection.

        Detected types include: int, bigint, decimal(p,s), datetime2, bit,
        uniqueidentifier, varchar(n), and nvarchar(n) when Unicode is detected.

    .PARAMETER Parallel
        Enables parallel processing for improved performance on large files.
        When enabled, line reading, parsing, and type conversion are performed in parallel
        using a producer-consumer pipeline. This can provide 2-4x performance improvement
        on multi-core systems.

        Note: Parallel processing is most beneficial for large files (>100K rows) with
        complex type conversions. For small files, sequential processing may be faster
        due to lower overhead.

        When Parallel is used, the progress bar is disabled because the progress callback
        cannot run in background threads.

    .PARAMETER ThrottleLimit
        Sets the maximum number of worker threads for parallel processing.
        Default is 0, which uses the number of logical processors on the system.
        Set to 1 to effectively disable parallelism while still using the pipeline architecture.
        Only used when Parallel is specified.

    .PARAMETER ParallelBatchSize
        Sets the number of records to batch before yielding to the consumer during parallel processing.
        Larger batches reduce synchronization overhead but increase memory usage and latency.
        Default is 100. Minimum is 1.
        Only used when Parallel is specified.

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

    .EXAMPLE
        PS C:\> Import-DbaCsv -Path C:\temp\data.csv -SqlInstance sql001 -Database tempdb -Table MyTable -Delimiter "::" -AutoCreateTable

        Imports a CSV file that uses a multi-character delimiter (::). The new CSV reader supports delimiters of any length,
        not just single characters.

    .EXAMPLE
        PS C:\> Import-DbaCsv -Path C:\temp\data.csv.gz -SqlInstance sql001 -Database tempdb -Table MyTable -AutoCreateTable

        Imports a gzip-compressed CSV file. Compression is automatically detected from the .gz extension and the file
        is decompressed on-the-fly during import without extracting to disk.

    .EXAMPLE
        PS C:\> Import-DbaCsv -Path C:\temp\export.csv -SqlInstance sql001 -Database tempdb -Table MyTable -SkipRows 3 -AutoCreateTable

        Skips the first 3 rows of the file before reading headers and data. Useful for files that have metadata rows,
        comments, or report headers before the actual CSV content begins.

    .EXAMPLE
        PS C:\> Import-DbaCsv -Path C:\temp\data.csv -SqlInstance sql001 -Database tempdb -Table MyTable -DuplicateHeaderBehavior Rename -AutoCreateTable

        Handles CSV files with duplicate column headers by automatically renaming them (e.g., Name, Name_2, Name_3).
        Without this, duplicate headers would cause an error.

    .EXAMPLE
        PS C:\> Import-DbaCsv -Path C:\temp\messy.csv -SqlInstance sql001 -Database tempdb -Table MyTable -MismatchedFieldAction PadWithNulls -AutoCreateTable

        Imports a CSV where some rows have fewer fields than the header row. Missing fields are padded with NULL values
        instead of throwing an error. Useful for importing data from systems that omit trailing empty fields.

    .EXAMPLE
        PS C:\> Import-DbaCsv -Path C:\temp\data.csv -SqlInstance sql001 -Database tempdb -Table MyTable -QuoteMode Lenient -AutoCreateTable

        Uses lenient quote parsing for CSV files with improperly escaped quotes. This is useful when importing data
        from systems that don't follow RFC 4180 strictly, such as files with embedded quotes that aren't doubled.

    .EXAMPLE
        PS C:\> # Import CSV with proper type conversion to a pre-created table
        PS C:\> $query = "CREATE TABLE TypedData (id INT, amount DECIMAL(10,2), active BIT, created DATETIME)"
        PS C:\> Invoke-DbaQuery -SqlInstance sql001 -Database tempdb -Query $query
        PS C:\> Import-DbaCsv -Path C:\temp\typed.csv -SqlInstance sql001 -Database tempdb -Table TypedData

        Imports CSV data into a table with specific column types. The CSV reader automatically converts string values
        to the appropriate SQL Server types (INT, DECIMAL, BIT, DATETIME, etc.) during import.

    .EXAMPLE
        PS C:\> Import-DbaCsv -Path C:\temp\large.csv -SqlInstance sql001 -Database tempdb -Table BigData -AutoCreateTable -Parallel

        Imports a large CSV file using parallel processing for improved performance. The -Parallel switch enables
        concurrent line reading, parsing, and type conversion, which can provide 2-4x speedup on multi-core systems
        for files with 100K+ rows.

    .EXAMPLE
        PS C:\> Import-DbaCsv -Path C:\temp\huge.csv -SqlInstance sql001 -Database tempdb -Table HugeData -AutoCreateTable -Parallel -ThrottleLimit 4

        Imports a large CSV with parallel processing limited to 4 worker threads. Use -ThrottleLimit to control
        resource usage on shared systems or when you want to limit CPU consumption during the import.

    .EXAMPLE
        PS C:\> Import-DbaCsv -Path C:\temp\massive.csv -SqlInstance sql001 -Database tempdb -Table MassiveData -AutoCreateTable -Parallel -ParallelBatchSize 500

        Imports a very large CSV with parallel processing using larger batch sizes. Increase -ParallelBatchSize
        for very large files (millions of rows) to reduce synchronization overhead. The default is 100.

    .EXAMPLE
        PS C:\> Import-DbaCsv -Path C:\temp\refresh.csv -SqlInstance sql001 -Database tempdb -Table LookupData -Truncate

        Performs a full data refresh by truncating the existing table before importing. The truncate and import
        operations are wrapped in a transaction, so if the import fails, the original data is preserved.

    .EXAMPLE
        PS C:\> $static = @{ SourceFile = "sales_2024.csv"; ImportDate = (Get-Date); Region = "EMEA" }
        PS C:\> Import-DbaCsv -Path C:\temp\sales.csv -SqlInstance sql001 -Database sales -Table SalesData -StaticColumns $static -AutoCreateTable

        Imports CSV data and adds three static columns (SourceFile, ImportDate, Region) to every row.
        This is useful for tracking data lineage and tagging imported records with metadata.

    .EXAMPLE
        PS C:\> Import-DbaCsv -Path C:\temp\oracle_export.csv -SqlInstance sql001 -Database tempdb -Table OracleData -DateTimeFormats @("dd-MMM-yyyy", "dd-MMM-yyyy HH:mm:ss") -AutoCreateTable

        Imports a CSV with Oracle-style date formats (e.g., "15-Jan-2024"). The -DateTimeFormats parameter
        specifies custom format strings to parse non-standard date columns correctly.

    .EXAMPLE
        PS C:\> Import-DbaCsv -Path C:\temp\german_data.csv -SqlInstance sql001 -Database tempdb -Table GermanData -Culture "de-DE" -AutoCreateTable

        Imports a CSV with German number formatting where comma is the decimal separator (e.g., "1.234,56").
        The -Culture parameter ensures numbers are parsed correctly according to the specified locale.

    .EXAMPLE
        PS C:\> Import-DbaCsv -Path C:\temp\sales.csv -SqlInstance sql001 -Database sales -Table SalesData -AutoCreateTable -SampleRows 10000

        Imports sales.csv and creates the table with optimal column types inferred from the first 10,000 rows.
        Instead of nvarchar(MAX) for all columns, the table will have appropriate types like int, decimal(10,2),
        datetime2, bit, or varchar(50) based on the actual data patterns detected.

        This is fast but has a small risk if data patterns change after the sampled rows.

    .EXAMPLE
        PS C:\> Import-DbaCsv -Path C:\temp\large_dataset.csv -SqlInstance sql001 -Database warehouse -Table FactSales -AutoCreateTable -DetectColumnTypes

        Imports large_dataset.csv with guaranteed optimal column types by scanning the entire file first.
        A separate progress bar shows "Analyzing column types..." during the detection phase.
        The final output (Elapsed, RowsPerSecond) reflects only the import time, not the detection overhead.

        This is slower (reads file twice) but guarantees no import failures due to type mismatches.

    .EXAMPLE
        PS C:\> Import-DbaCsv -Path C:\temp\products.csv -SqlInstance sql001 -Database inventory -Table Products -AutoCreateTable -SampleRows 5000 -DateTimeFormats @("dd-MMM-yyyy", "yyyy/MM/dd")

        Imports products.csv with type detection from 5,000 rows, using custom date formats for parsing.
        Columns containing dates in formats like "15-Jan-2024" or "2024/01/15" will be detected as datetime2.

    .EXAMPLE
        PS C:\> Import-DbaCsv -Path C:\temp\quickload.csv -SqlInstance sql001 -Database tempdb -Table QuickData -AutoCreateTable

        Imports quickload.csv with AutoCreateTable. After import completes, column sizes are automatically
        optimized by querying actual max lengths and altering columns from nvarchar(MAX) to appropriate sizes.
        This "just works" approach imports first, then optimizes - no risk of import failures.
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
        [ValidateNotNullOrEmpty()]
        [Alias("DelimiterChar")]
        [string]$Delimiter = ",",
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
        [long]$MaxDecompressedSize = 10737418240,
        [int]$SkipRows = 0,
        [ValidateSet('Strict', 'Lenient')]
        [string]$QuoteMode = 'Strict',
        [ValidateSet('ThrowException', 'Rename', 'UseFirstOccurrence', 'UseLastOccurrence')]
        [string]$DuplicateHeaderBehavior = 'ThrowException',
        [ValidateSet('ThrowException', 'PadWithNulls', 'TruncateExtra', 'PadOrTruncate')]
        [string]$MismatchedFieldAction = 'ThrowException',
        [switch]$DistinguishEmptyFromNull,
        [switch]$NormalizeQuotes,
        [switch]$CollectParseErrors,
        [int]$MaxParseErrors = 1000,
        [hashtable]$StaticColumns,
        [string[]]$DateTimeFormats,
        [string]$Culture,
        [int]$SampleRows,
        [switch]$DetectColumnTypes,
        [switch]$Parallel,
        [int]$ThrottleLimit = 0,
        [int]$ParallelBatchSize = 100,
        [switch]$EnableException
    )
    begin {
        $FirstRowHeader = $NoHeaderRow -eq $false
        $scriptelapsed = [System.Diagnostics.Stopwatch]::StartNew()

        if ($PSBoundParameters.UseFileNameForSchema -and $PSBoundParameters.Schema) {
            Write-Message -Level Warning -Message "Schema and UseFileNameForSchema parameters both specified. UseSchemaInFileName will be ignored."
        }

        # Type detection implies AutoCreateTable behavior
        $useTypeDetection = $PSBoundParameters.SampleRows -or $DetectColumnTypes
        if ($useTypeDetection -and -not $AutoCreateTable) {
            Write-Message -Level Verbose -Message "Type detection enabled - AutoCreateTable behavior will be used for table creation."
        }

        if ($PSBoundParameters.SampleRows -and $DetectColumnTypes) {
            Write-Message -Level Warning -Message "Both SampleRows and DetectColumnTypes specified. DetectColumnTypes (full scan) takes precedence for zero-risk type detection."
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
                [Microsoft.Data.SqlClient.SqlTransaction]$transaction
            )

            $options = New-Object Dataplat.Dbatools.Csv.Reader.CsvReaderOptions
            $options.HasHeaderRow = $FirstRowHeader
            $options.Delimiter = $Delimiter
            $options.Quote = $Quote
            $options.Escape = $Escape
            $options.Comment = $Comment
            $options.TrimmingOptions = [Dataplat.Dbatools.Csv.ValueTrimmingOptions]::$TrimmingOption
            $options.BufferSize = $BufferSize
            $options.Encoding = [System.Text.Encoding]::$Encoding
            if ($NullValue) { $options.NullValue = $NullValue }
            $options.MaxDecompressedSize = $MaxDecompressedSize
            $options.SkipRows = $SkipRows
            $options.DuplicateHeaderBehavior = [Dataplat.Dbatools.Csv.Reader.DuplicateHeaderBehavior]::$DuplicateHeaderBehavior

            try {
                $reader = [Dataplat.Dbatools.Csv.Reader.CsvDataReader]::new($Path, $options)
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

        function New-SqlTableWithInferredSchema {
            <#
                .SYNOPSIS
                    Creates new Table using inferred column types from CSV analysis.

                .DESCRIPTION
                    Uses CsvSchemaInference to analyze CSV data and create a table with optimal
                    SQL Server column types instead of nvarchar(MAX) for everything.

                .EXAMPLE
                    New-SqlTableWithInferredSchema -Path $Path -InferredColumns $columns -SqlConn $sqlconn -Transaction $transaction
            #>
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseShouldProcessForStateChangingFunctions", "")]
            param (
                [Parameter(Mandatory)]
                [string]$Path,
                [Parameter(Mandatory)]
                [object[]]$InferredColumns,
                [Microsoft.Data.SqlClient.SqlConnection]$sqlconn,
                [Microsoft.Data.SqlClient.SqlTransaction]$transaction
            )

            # Convert PowerShell array back to List<InferredColumn> for C# interop
            # PowerShell unwraps List<T> to Object[] when passing through functions
            $columnList = New-Object 'System.Collections.Generic.List[Dataplat.Dbatools.Csv.Reader.InferredColumn]'
            foreach ($col in $InferredColumns) {
                $columnList.Add($col)
            }

            $sql = [Dataplat.Dbatools.Csv.Reader.CsvSchemaInference]::GenerateCreateTableStatement($columnList, $table, $schema)

            Write-Message -Level Debug -Message $sql

            $sqlcmd = New-Object Microsoft.Data.SqlClient.SqlCommand($sql, $sqlconn, $transaction)

            try {
                $null = $sqlcmd.ExecuteNonQuery()
            } catch {
                $errormessage = $_.Exception.Message.ToString()
                Stop-Function -Continue -Message "Failed to execute $sql. `nDid you specify the proper delimiter? `n$errormessage"
            }

            $typeList = ($InferredColumns | ForEach-Object { "[$($_.ColumnName)] $($_.SqlDataType) $(if ($_.IsNullable) { 'NULL' } else { 'NOT NULL' })" }) -join "`n  "
            Write-Message -Level Verbose -Message "Successfully created table $schema.$table with inferred column types:`n  $typeList"
        }

        function Get-InferredSchema {
            <#
                .SYNOPSIS
                    Infers SQL Server column types from CSV file.

                .DESCRIPTION
                    Uses CsvSchemaInference to analyze CSV data and return optimal column definitions.
            #>
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseShouldProcessForStateChangingFunctions", "")]
            param (
                [Parameter(Mandatory)]
                [string]$Path,
                [object]$CsvOptions,
                [int]$SampleRows,
                [switch]$FullScan
            )

            if ($FullScan) {
                # Full scan with progress callback
                [Action[double]]$progressCallback = {
                    param($progress)
                    $percent = [int]($progress * 100)
                    Write-Progress -Id 2 -Activity "Analyzing column types" -Status "$percent% complete" -PercentComplete $percent
                }

                $inferredColumns = [Dataplat.Dbatools.Csv.Reader.CsvSchemaInference]::InferSchema($Path, $CsvOptions, $progressCallback)

                Write-Progress -Id 2 -Activity "Analyzing column types" -Status "Complete" -Completed
            } else {
                # Sample-based inference
                Write-Message -Level Verbose -Message "Sampling first $SampleRows rows for type inference..."
                $inferredColumns = [Dataplat.Dbatools.Csv.Reader.CsvSchemaInference]::InferSchemaFromSample($Path, $CsvOptions, $SampleRows)
            }

            return $inferredColumns
        }

        function Optimize-ColumnSize {
            <#
                .SYNOPSIS
                    Optimizes nvarchar(MAX) columns to appropriate sizes after import.

                .DESCRIPTION
                    Queries MAX(LEN()) for each column and ALTERs to appropriate varchar/nvarchar sizes.
                    This is called automatically when AutoCreateTable is used without type detection.

                .NOTES
                    Requires SQL Server 2005 or higher. This is not a limitation since nvarchar(MAX)
                    was introduced in SQL Server 2005 - the feature this optimizes cannot exist on SQL 2000.
            #>
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseShouldProcessForStateChangingFunctions", "")]
            param (
                [Microsoft.Data.SqlClient.SqlConnection]$SqlConn,
                [string]$Schema,
                [string]$Table
            )

            Write-Message -Level Verbose -Message "Optimizing column sizes for $Schema.$Table..."

            # Get column names from the table
            $getColumnsSql = @"
SELECT c.name AS ColumnName
FROM sys.columns c
INNER JOIN sys.types t ON c.user_type_id = t.user_type_id
WHERE c.object_id = OBJECT_ID(@tableName)
  AND t.name IN ('nvarchar', 'varchar')
  AND c.max_length = -1
"@
            $sqlcmd = New-Object Microsoft.Data.SqlClient.SqlCommand($getColumnsSql, $SqlConn)
            $null = $sqlcmd.Parameters.AddWithValue('tableName', "[$Schema].[$Table]")

            $columns = @()
            $reader = $sqlcmd.ExecuteReader()
            while ($reader.Read()) {
                $columns += $reader["ColumnName"]
            }
            $reader.Close()

            if ($columns.Count -eq 0) {
                Write-Message -Level Verbose -Message "No nvarchar(MAX)/varchar(MAX) columns to optimize."
                return
            }

            # Build MAX(LEN()) query for all columns
            $maxLenSelects = $columns | ForEach-Object { "MAX(LEN([$_])) AS [$_]" }
            $maxLenSql = "SELECT $($maxLenSelects -join ', ') FROM [$Schema].[$Table]"

            $sqlcmd = New-Object Microsoft.Data.SqlClient.SqlCommand($maxLenSql, $SqlConn)
            $reader = $sqlcmd.ExecuteReader()

            $maxLengths = @{}
            if ($reader.Read()) {
                foreach ($col in $columns) {
                    $val = $reader[$col]
                    if ($val -is [DBNull] -or $null -eq $val) {
                        $maxLengths[$col] = 1
                    } else {
                        $maxLengths[$col] = [int]$val
                    }
                }
            }
            $reader.Close()

            # ALTER each column to appropriate size
            foreach ($col in $columns) {
                $maxLen = $maxLengths[$col]
                if ($maxLen -eq 0) { $maxLen = 1 }

                # Check if it needs nvarchar (unicode) or varchar
                # Detect Unicode by checking if round-tripping through VARCHAR loses data
                # If CAST(CAST(col AS VARCHAR) AS NVARCHAR) <> col, then Unicode chars would be lost
                $checkUnicodeSql = "SELECT TOP 1 1 FROM [$Schema].[$Table] WHERE CAST(CAST([$col] AS VARCHAR(MAX)) AS NVARCHAR(MAX)) <> [$col] AND [$col] IS NOT NULL"
                $sqlcmd = New-Object Microsoft.Data.SqlClient.SqlCommand($checkUnicodeSql, $SqlConn)
                $hasUnicode = $null -ne $sqlcmd.ExecuteScalar()

                $baseType = if ($hasUnicode) { "nvarchar" } else { "varchar" }
                $maxAllowed = if ($hasUnicode) { 4000 } else { 8000 }

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
                # SQL Server 2008 R2 and earlier require NULL/NOT NULL in ALTER COLUMN
                # Original columns were nvarchar(MAX) NULL, so we preserve NULL
                $alterSql = "ALTER TABLE [$Schema].[$Table] ALTER COLUMN [$col] $newType NULL"

                Write-Message -Level Verbose -Message "Optimizing [$col]: nvarchar(MAX) -> $newType (max data length: $maxLen, padded to: $paddedLen)"

                try {
                    $sqlcmd = New-Object Microsoft.Data.SqlClient.SqlCommand($alterSql, $SqlConn)
                    $null = $sqlcmd.ExecuteNonQuery()
                } catch {
                    Write-Message -Level Warning -Message "Failed to optimize column [$col]: $($_.Exception.Message)"
                }
            }

            Write-Message -Level Verbose -Message "Column size optimization complete."
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
                # Does the data section contain the specified delimiter?
                # Account for SkipRows when checking
                try {
                    $linesToRead = $SkipRows + 2
                    $firstlines = Get-Content -Path $file -TotalCount $linesToRead -ErrorAction Stop
                    # Get only the lines after SkipRows for delimiter check
                    if ($SkipRows -gt 0 -and $firstlines.Count -gt $SkipRows) {
                        $firstlines = $firstlines[$SkipRows..($firstlines.Count - 1)]
                    }
                } catch {
                    Stop-Function -Continue -Message "Failure reading $file" -ErrorRecord $_
                }
                if (-not $SingleColumn) {
                    if ($firstlines -notmatch [regex]::Escape($Delimiter)) {
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

                # Determine if we should auto-create (type detection also implies auto-create)
                $shouldAutoCreate = $AutoCreateTable -or $useTypeDetection

                # Ensure Schema exists
                $sql = "SELECT COUNT(*) FROM sys.schemas WHERE name = @schema"
                $sqlcmd = New-Object Microsoft.Data.SqlClient.SqlCommand($sql, $sqlconn, $transaction)
                $null = $sqlcmd.Parameters.AddWithValue('schema', $schema)
                # If Schema doesn't exist create it
                # Defaulting to dbo.
                if (($sqlcmd.ExecuteScalar()) -eq 0) {
                    if (-not $shouldAutoCreate) {
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
                $null = $sqlcmd.Parameters.AddWithValue('schema', $schema)
                $null = $sqlcmd.Parameters.AddWithValue('table', $table)

                $sql2 = "SELECT COUNT(*) FROM sys.views WHERE name = @table AND schema_id=schema_id(@schema)"
                $sqlcmd2 = New-Object Microsoft.Data.SqlClient.SqlCommand($sql2, $sqlconn, $transaction)
                $null = $sqlcmd2.Parameters.AddWithValue('schema', $schema)
                $null = $sqlcmd2.Parameters.AddWithValue('table', $table)

                # this variable enables the machinery that needs to build a precise mapping from the table definition
                # to the type of the columns BulkCopy needs. Lumen has support for it, but since it's a tad bit expensive
                # we opt-in only if the table already exists but not when we create the default table (which is basic, and it's all nvarchar(max)s columns)
                $shouldMapCorrectTypes = $false

                # Store inferred columns for later use with CsvDataReader type mapping
                $inferredColumns = $null

                # Track if we created a "fat" table (nvarchar(MAX) for all columns) that needs post-import optimization
                $createdFatTable = $false

                # Create the table if required. Remember, this will occur within a transaction, so if the script fails, the
                # new table will no longer exist.
                if (($sqlcmd.ExecuteScalar()) -eq 0 -and ($sqlcmd2.ExecuteScalar()) -eq 0) {
                    if (-not $shouldAutoCreate) {
                        Stop-Function -Continue -Message "Table or view $table does not exist and AutoCreateTable was not specified"
                    }
                    Write-Message -Level Verbose -Message "Table does not exist"

                    if ($useTypeDetection) {
                        # Build CsvReaderOptions for schema inference
                        $inferOptions = New-Object Dataplat.Dbatools.Csv.Reader.CsvReaderOptions
                        $inferOptions.HasHeaderRow = $FirstRowHeader
                        $inferOptions.Delimiter = $Delimiter
                        $inferOptions.Quote = $Quote
                        $inferOptions.Escape = $Escape
                        $inferOptions.Comment = $Comment
                        $inferOptions.Encoding = [System.Text.Encoding]::$Encoding
                        if ($PSBoundParameters.DateTimeFormats) {
                            $inferOptions.DateTimeFormats = $DateTimeFormats
                        }
                        if ($PSBoundParameters.Culture) {
                            $inferOptions.Culture = New-Object System.Globalization.CultureInfo($Culture)
                        }

                        # Infer schema (this happens before the import timer starts)
                        $splatInfer = @{
                            Path       = $file
                            CsvOptions = $inferOptions
                        }

                        if ($DetectColumnTypes) {
                            # Full scan - guarantees zero risk
                            $splatInfer.FullScan = $true
                            Write-Message -Level Verbose -Message "Performing full file scan for type detection (zero risk)..."
                        } else {
                            # Sample-based
                            $splatInfer.SampleRows = $SampleRows
                            Write-Message -Level Verbose -Message "Sampling $SampleRows rows for type detection..."
                        }

                        $inferredColumns = Get-InferredSchema @splatInfer

                        if ($PSCmdlet.ShouldProcess($instance, "Creating table $table with inferred column types")) {
                            try {
                                New-SqlTableWithInferredSchema -Path $file -InferredColumns $inferredColumns -SqlConn $sqlconn -Transaction $transaction
                                # With inferred types, we want to use type conversion during import
                                $shouldMapCorrectTypes = $true
                            } catch {
                                Stop-Function -Continue -Message "Failure creating table with inferred types" -ErrorRecord $_
                            }
                        }
                    } else {
                        # Original behavior - nvarchar(MAX) for all columns, then optimize after import
                        if ($PSCmdlet.ShouldProcess($instance, "Creating table $table")) {
                            try {
                                New-SqlTable -Path $file -Delimiter $Delimiter -FirstRowHeader $FirstRowHeader -SqlConn $sqlconn -Transaction $transaction
                                $createdFatTable = $true
                            } catch {
                                Stop-Function -Continue -Message "Failure" -ErrorRecord $_
                            }
                        }
                    }
                } else {
                    $shouldMapCorrectTypes = $true
                    Write-Message -Level Verbose -Message "Table exists"
                }

                # Reset the elapsed timer if we did type detection, so output reflects import time only
                if ($useTypeDetection -and $inferredColumns) {
                    $elapsed.Restart()
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
                                    $isFirst = $true
                                    $firstline -split "$Delimiter", 0, "SimpleMatch" | ForEach-Object {
                                        $trimmed = $PSItem.Trim('"')
                                        # Remove UTF-8 BOM from first column if present (U+FEFF)
                                        if ($isFirst) {
                                            $trimmed = $trimmed.TrimStart([char]0xFEFF)
                                            $isFirst = $false
                                        }
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

                        # Add static column mappings for metadata tagging (issue #6676)
                        if ($PSBoundParameters.StaticColumns) {
                            foreach ($key in $StaticColumns.Keys) {
                                $null = $bulkcopy.ColumnMappings.Add($key, $key)
                            }
                        }

                    } catch {
                        Stop-Function -Continue -Message "Failure" -ErrorRecord $_
                    }

                    # Write to server :D
                    try {

                        $stream = [System.IO.File]::OpenRead($File)

                        # ProgressStream callback doesn't work with parallel processing
                        # (background threads can't access PowerShell runspace)
                        if (-not $Parallel) {
                            [Action[double]] $progressCallback = {
                                param($progress)

                                if (-not $NoProgress) {
                                    $timetaken = [math]::Round($elapsed.Elapsed.TotalSeconds, 2)
                                    $percent = [int]($progress * 100)
                                    Write-ProgressHelper -StepNumber $percent -TotalSteps 100 -Activity "Importing from $file" -Message ([System.String]::Format("Progress: {0} rows {1}% in {2} seconds", $script:totalRowsCopied, $percent, $timetaken))
                                }
                            }
                            $stream = New-Object Dataplat.Dbatools.IO.ProgressStream($stream, $progressCallback, 0.05)
                        }

                        # Build CsvReaderOptions with all configuration
                        $csvOptions = New-Object Dataplat.Dbatools.Csv.Reader.CsvReaderOptions
                        $csvOptions.HasHeaderRow = $FirstRowHeader
                        $csvOptions.Delimiter = $Delimiter
                        $csvOptions.Quote = $Quote
                        $csvOptions.Escape = $Escape
                        $csvOptions.Comment = $Comment
                        $csvOptions.TrimmingOptions = [Dataplat.Dbatools.Csv.ValueTrimmingOptions]::$TrimmingOption
                        $csvOptions.BufferSize = $BufferSize
                        $csvOptions.Encoding = [System.Text.Encoding]::$Encoding
                        if ($NullValue) { $csvOptions.NullValue = $NullValue }
                        $csvOptions.MaxDecompressedSize = $MaxDecompressedSize
                        $csvOptions.SkipRows = $SkipRows
                        $csvOptions.QuoteMode = [Dataplat.Dbatools.Csv.Reader.QuoteMode]::$QuoteMode
                        $csvOptions.DuplicateHeaderBehavior = [Dataplat.Dbatools.Csv.Reader.DuplicateHeaderBehavior]::$DuplicateHeaderBehavior
                        $csvOptions.MismatchedFieldAction = [Dataplat.Dbatools.Csv.Reader.MismatchedFieldAction]::$MismatchedFieldAction
                        $csvOptions.DistinguishEmptyFromNull = $DistinguishEmptyFromNull.IsPresent
                        $csvOptions.NormalizeQuotes = $NormalizeQuotes.IsPresent
                        $csvOptions.CollectParseErrors = $CollectParseErrors.IsPresent
                        $csvOptions.MaxParseErrors = $MaxParseErrors
                        $csvOptions.SkipEmptyLines = $SkipEmptyLine.IsPresent
                        $csvOptions.AllowMultilineFields = $SupportsMultiline.IsPresent
                        $csvOptions.UseColumnDefaults = $UseColumnDefault.IsPresent
                        if ($PSBoundParameters.MaxQuotedFieldLength) {
                            $csvOptions.MaxQuotedFieldLength = $MaxQuotedFieldLength
                        }
                        $csvOptions.ParseErrorAction = [Dataplat.Dbatools.Csv.CsvParseErrorAction]::$ParseErrorAction
                        if ($PSBoundParameters.DateTimeFormats) {
                            $csvOptions.DateTimeFormats = $DateTimeFormats
                        }
                        if ($PSBoundParameters.Culture) {
                            $csvOptions.Culture = New-Object System.Globalization.CultureInfo($Culture)
                        }
                        if ($PSBoundParameters.StaticColumns) {
                            $staticColumnsList = New-Object "System.Collections.Generic.List[Dataplat.Dbatools.Csv.Reader.StaticColumn]"
                            foreach ($key in $StaticColumns.Keys) {
                                $staticCol = New-Object Dataplat.Dbatools.Csv.Reader.StaticColumn($key, $StaticColumns[$key])
                                $staticColumnsList.Add($staticCol)
                            }
                            $csvOptions.StaticColumns = $staticColumnsList
                        }
                        $csvOptions.EnableParallelProcessing = $Parallel.IsPresent
                        if ($PSBoundParameters.ThrottleLimit) {
                            $csvOptions.MaxDegreeOfParallelism = $ThrottleLimit
                        }
                        if ($PSBoundParameters.ParallelBatchSize) {
                            $csvOptions.ParallelBatchSize = $ParallelBatchSize
                        }

                        $reader = [Dataplat.Dbatools.Csv.Reader.CsvDataReader]::new($stream, $csvOptions)

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
                                            # and now we assign the type to the CsvDataReader column
                                            $reader.SetColumnType($colNameFromCsv, $colTypeCSharp)
                                            Write-Message -Level Verbose -Message "Mapped $colNameFromCsv --> $colNameFromSql ($colTypeCSharp --> $colTypeFromSql)"
                                            break
                                        }
                                    }
                                }
                            } else {
                                # For no-header scenarios, we need to set up column types based on table definition
                                # We cannot call Read() here as that would consume the first data row
                                $tableDef = Get-TableDefinitionFromInfoSchema -table $table -schema $schema -sqlconn $sqlconn
                                if ($tableDef.Length -eq 0) {
                                    Stop-Function -Message "Could not fetch table definition for table $table in schema $schema"
                                }
                                if ($bulkcopy.ColumnMappings.Count -eq 0) {
                                    # if we land here, we aren't forcing any mappings, but we need them for later
                                    foreach ($dataRow in $tableDef) {
                                        $null = $bulkcopy.ColumnMappings.Add($dataRow.Index, $dataRow.Index)
                                    }
                                }
                                # For no-header mode, column names are auto-generated as "Column0", "Column1", etc.
                                # Set up types by ordinal using the table definition
                                foreach ($sqlCol in $tableDef) {
                                    $colTypeCSharp = ConvertTo-DotnetType -DataType $sqlCol.DataType
                                    $colName = "Column$($sqlCol.Index)"
                                    $reader.SetColumnType($colName, $colTypeCSharp)
                                    Write-Message -Level Verbose -Message "Mapped $colName --> $($sqlCol.Name) ($colTypeCSharp)"
                                }
                            }
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

                                # Optimize column sizes after commit if we created a fat table
                                if ($createdFatTable) {
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
                        } elseif ($completed -and $createdFatTable) {
                            # NoTransaction mode - still optimize if we created a fat table
                            try {
                                Optimize-ColumnSize -SqlConn $sqlconn -Schema $schema -Table $table
                            } catch {
                                Write-Message -Level Warning -Message "Column size optimization failed: $($_.Exception.Message)"
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