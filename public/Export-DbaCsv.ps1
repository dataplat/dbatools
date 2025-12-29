function Export-DbaCsv {
    <#
    .SYNOPSIS
        Exports SQL Server query results or table data to CSV files with optional compression.

    .DESCRIPTION
        Export-DbaCsv provides high-performance CSV export capabilities with support for multiple compression formats
        including GZip, Deflate, Brotli, and ZLib. The function can export data from SQL queries, tables, or piped
        objects to CSV files with configurable formatting options.

        Supports various output formats including custom delimiters, quoting behaviors, date formatting, and encoding options.
        Compression can significantly reduce file sizes for large exports, making it ideal for archiving, data transfer,
        or storage-constrained environments.

        Perfect for ETL processes, data exports, reporting, and creating portable data files from SQL Server.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies the database to query. Required when using -Query or -Table parameters.

    .PARAMETER Query
        The T-SQL query to execute. Results will be exported to CSV.

    .PARAMETER Table
        The name of the table to export. Can include schema (e.g., "dbo.Customers").

    .PARAMETER InputObject
        Accepts piped objects to export. Can be used with results from other dbatools commands or any PowerShell objects.

    .PARAMETER Path
        The output file path for the CSV. If the path ends with .gz, .br, .deflate, or .zlib,
        the appropriate compression will be applied automatically unless -CompressionType is specified.

    .PARAMETER Delimiter
        Sets the field separator for the CSV output. Defaults to comma.
        Common values include comma (,), tab (`t), pipe (|), or semicolon (;).
        Multi-character delimiters are supported (e.g., "::", "||").

    .PARAMETER NoHeader
        Suppresses the header row in the output. Use this when appending to existing files
        or when the consuming application doesn't expect headers.

    .PARAMETER Quote
        Specifies the character used to quote fields. Defaults to double-quote (").

    .PARAMETER QuotingBehavior
        Controls when field values are quoted.
        - AsNeeded: Quote only when necessary (contains delimiter, quote, or newline). This is the default.
        - Always: Always quote all fields.
        - Never: Never quote fields (may produce invalid CSV with some data).
        - NonNumeric: Quote only non-numeric fields.

    .PARAMETER Encoding
        The text encoding for the output file. Defaults to UTF8.
        Valid values: ASCII, BigEndianUnicode, Unicode, UTF7, UTF8, UTF32.

    .PARAMETER NullValue
        The string to use for NULL values in the output. Defaults to empty string.

    .PARAMETER DateTimeFormat
        The format string for DateTime values. Defaults to ISO 8601 format (yyyy-MM-dd HH:mm:ss.fff).

    .PARAMETER UseUtc
        Converts DateTime values to UTC before formatting.

    .PARAMETER CompressionType
        The type of compression to apply to the output file.
        - None: No compression (default)
        - GZip: GZip compression (.gz)
        - Deflate: Deflate compression
        - Brotli: Brotli compression (.br) - .NET 8+ only
        - ZLib: ZLib compression - .NET 8+ only

    .PARAMETER CompressionLevel
        The compression level to use. Defaults to Optimal.
        - Fastest: Compress as fast as possible, even if the resulting file is not optimally compressed.
        - Optimal: Balance between compression speed and file size.
        - SmallestSize: Compress as much as possible, even if it takes longer.
        - NoCompression: No compression.

    .PARAMETER Append
        Appends to an existing file instead of overwriting. Headers are automatically suppressed when appending.

    .PARAMETER NoClobber
        Prevents overwriting an existing file. Returns an error if the file already exists.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Export, CSV, Data, Compression
        Author: the dbatools team + Claude

        Website: https://dbatools.io
        Copyright: (c) 2025 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        Addresses GitHub issue #8646 for Export-DbaCsv with compression options.

    .OUTPUTS
        PSCustomObject

        Returns a single object containing export summary information only when rows are successfully exported. If no rows are exported, no output is returned.

        Properties:
        - Path: The full file system path where the CSV file was written (string)
        - RowsExported: The total number of rows written to the CSV file (int)
        - FileSizeBytes: The size of the output file in bytes (long)
        - FileSizeMB: The size of the output file in megabytes, rounded to 2 decimal places (double)
        - CompressionType: The compression format applied to the file - None, GZip, Deflate, Brotli, or ZLib (string)
        - Elapsed: A TimeSpan object representing the total time taken to export all data (TimeSpan)
        - RowsPerSecond: The average export throughput calculated as rows written per second (double)

    .LINK
        https://dbatools.io/Export-DbaCsv

    .EXAMPLE
        PS C:\> Export-DbaCsv -SqlInstance sql001 -Database Northwind -Query "SELECT * FROM Customers" -Path C:\temp\customers.csv

        Exports all customers from the Northwind database to a CSV file.

    .EXAMPLE
        PS C:\> Export-DbaCsv -SqlInstance sql001 -Database Northwind -Table "dbo.Orders" -Path C:\temp\orders.csv.gz -CompressionType GZip

        Exports the Orders table to a GZip-compressed CSV file.

    .EXAMPLE
        PS C:\> Get-DbaDbTable -SqlInstance sql001 -Database tempdb -Table "#MyTempTable" | Export-DbaCsv -Path C:\temp\data.csv

        Pipes table data from Get-DbaDbTable to export as CSV.

    .EXAMPLE
        PS C:\> Export-DbaCsv -SqlInstance sql001 -Database Sales -Query "SELECT * FROM BigTable" -Path C:\archive\data.csv.gz -CompressionType GZip -CompressionLevel SmallestSize

        Exports query results with maximum GZip compression for archival purposes.

    .EXAMPLE
        PS C:\> Export-DbaCsv -SqlInstance sql001 -Database HR -Table Employees -Path C:\temp\employees.csv -Delimiter "`t" -QuotingBehavior Always

        Exports to a tab-delimited file with all fields quoted.

    .EXAMPLE
        PS C:\> $results = Invoke-DbaQuery -SqlInstance sql001 -Database master -Query "SELECT * FROM sys.databases"
        PS C:\> $results | Export-DbaCsv -Path C:\temp\databases.csv -DateTimeFormat "yyyy-MM-dd"

        Exports query results with custom date formatting.

    .EXAMPLE
        PS C:\> Export-DbaCsv -SqlInstance sql001 -Database Sales -Query "SELECT * FROM Orders WHERE Region = 'EMEA'" -Path C:\temp\emea.csv -Encoding Unicode

        Exports with Unicode encoding for international character support.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string]$Database,
        [string]$Query,
        [string]$Table,
        [Parameter(ValueFromPipeline)]
        [object[]]$InputObject,
        [Parameter(Mandatory)]
        [string]$Path,
        [string]$Delimiter = ",",
        [switch]$NoHeader,
        [char]$Quote = '"',
        [ValidateSet("AsNeeded", "Always", "Never", "NonNumeric")]
        [string]$QuotingBehavior = "AsNeeded",
        [ValidateSet("ASCII", "BigEndianUnicode", "Unicode", "UTF7", "UTF8", "UTF32")]
        [string]$Encoding = "UTF8",
        [string]$NullValue = "",
        [string]$DateTimeFormat = "yyyy-MM-dd HH:mm:ss.fff",
        [switch]$UseUtc,
        [ValidateSet("None", "GZip", "Deflate", "Brotli", "ZLib")]
        [string]$CompressionType = "None",
        [ValidateSet("Fastest", "Optimal", "SmallestSize", "NoCompression")]
        [string]$CompressionLevel = "Optimal",
        [switch]$Append,
        [switch]$NoClobber,
        [switch]$EnableException
    )

    begin {
        # Validate parameter combinations
        if (Test-Bound -ParameterName SqlInstance) {
            if (-not (Test-Bound -ParameterName Query) -and -not (Test-Bound -ParameterName Table)) {
                Stop-Function -Message "When using -SqlInstance, you must specify either -Query or -Table to define what data to export"
                return
            }
            if ((Test-Bound -ParameterName Query) -and (Test-Bound -ParameterName Table)) {
                Stop-Function -Message "You cannot specify both -Query and -Table. Please use one or the other"
                return
            }
            if (-not (Test-Bound -ParameterName Database)) {
                Stop-Function -Message "When using -SqlInstance with -Query or -Table, you must specify -Database"
                return
            }
        }

        # Auto-detect compression from file extension if not specified
        if ($CompressionType -eq "None") {
            $extension = [System.IO.Path]::GetExtension($Path).ToLower()
            switch ($extension) {
                ".gz" { $CompressionType = "GZip" }
                ".br" { $CompressionType = "Brotli" }
                ".deflate" { $CompressionType = "Deflate" }
                ".zlib" { $CompressionType = "ZLib" }
            }
        }

        # Check for file existence
        if ($NoClobber -and (Test-Path -Path $Path) -and -not $Append) {
            Stop-Function -Message "File '$Path' already exists and -NoClobber was specified"
            return
        }

        # Build writer options
        $writerOptions = New-Object Dataplat.Dbatools.Csv.Writer.CsvWriterOptions
        $writerOptions.Delimiter = $Delimiter
        $writerOptions.Quote = $Quote
        $writerOptions.WriteHeader = -not $NoHeader.IsPresent
        $writerOptions.NullValue = $NullValue
        $writerOptions.DateTimeFormat = $DateTimeFormat
        $writerOptions.UseUtc = $UseUtc.IsPresent
        $writerOptions.QuotingBehavior = [Dataplat.Dbatools.Csv.Writer.CsvQuotingBehavior]::$QuotingBehavior
        $writerOptions.CompressionType = [Dataplat.Dbatools.Csv.Compression.CompressionType]::$CompressionType
        # SmallestSize was added in .NET 6 - map to Optimal on .NET Framework
        $effectiveCompressionLevel = $CompressionLevel
        if ($CompressionLevel -eq "SmallestSize" -and $PSVersionTable.PSEdition -ne "Core") {
            Write-Message -Level Warning -Message "CompressionLevel 'SmallestSize' is not available in Windows PowerShell. Using 'Optimal' instead."
            $effectiveCompressionLevel = "Optimal"
        }
        $writerOptions.CompressionLevel = [System.IO.Compression.CompressionLevel]::$effectiveCompressionLevel

        # Set encoding
        switch ($Encoding) {
            "ASCII" { $writerOptions.Encoding = [System.Text.Encoding]::ASCII }
            "BigEndianUnicode" { $writerOptions.Encoding = [System.Text.Encoding]::BigEndianUnicode }
            "Unicode" { $writerOptions.Encoding = [System.Text.Encoding]::Unicode }
            "UTF7" { $writerOptions.Encoding = [System.Text.Encoding]::UTF7 }
            "UTF8" { $writerOptions.Encoding = New-Object System.Text.UTF8Encoding($false) }
            "UTF32" { $writerOptions.Encoding = [System.Text.Encoding]::UTF32 }
        }

        # Suppress header when appending
        if ($Append -and (Test-Path -Path $Path)) {
            $writerOptions.WriteHeader = $false
        }

        $writer = $null
        $rowsWritten = 0
        $inputObjects = New-Object System.Collections.ArrayList
        $elapsed = [System.Diagnostics.Stopwatch]::StartNew()
    }

    process {
        if (Test-FunctionInterrupt) { return }

        # Collect input objects for pipeline processing
        if ($PSBoundParameters.InputObject) {
            foreach ($obj in $InputObject) {
                $null = $inputObjects.Add($obj)
            }
            return
        }

        # Process SQL queries
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -Database $Database
            } catch {
                Stop-Function -Message "Failed to connect to $instance" -ErrorRecord $_ -Target $instance -Continue
            }

            $sqlToExecute = $null

            if ($PSBoundParameters.Query) {
                $sqlToExecute = $Query
            } elseif ($PSBoundParameters.Table) {
                # Parse table name for schema
                if ($Table -match "^(.+)\.(.+)$") {
                    $schemaName = $Matches[1]
                    $tableName = $Matches[2]
                } else {
                    $schemaName = "dbo"
                    $tableName = $Table
                }
                $sqlToExecute = "SELECT * FROM [$schemaName].[$tableName]"
            }


            if ($PSCmdlet.ShouldProcess($instance, "Exporting data to $Path")) {
                try {
                    Write-Message -Level Verbose -Message "Executing query on $instance"

                    # Execute query and get data reader
                    $cmd = $server.ConnectionContext.SqlConnectionObject.CreateCommand()
                    $cmd.CommandText = $sqlToExecute
                    $cmd.CommandTimeout = 0

                    if ($server.ConnectionContext.SqlConnectionObject.State -ne "Open") {
                        $server.ConnectionContext.SqlConnectionObject.Open()
                    }

                    $reader = $cmd.ExecuteReader()

                    # Create writer if not already created
                    if ($null -eq $writer) {
                        $writer = New-Object Dataplat.Dbatools.Csv.Writer.CsvWriter($Path, $writerOptions)
                    }

                    # Write data from reader
                    $rowsWritten += $writer.WriteFromReader($reader)

                    $reader.Close()
                    $reader.Dispose()

                } catch {
                    Stop-Function -Message "Failed to export data from $instance" -ErrorRecord $_ -Target $instance -Continue
                }
            }
        }
    }

    end {
        if (Test-FunctionInterrupt) { return }

        # Process collected input objects
        if ($inputObjects.Count -gt 0) {
            if ($PSCmdlet.ShouldProcess("InputObject", "Exporting $($inputObjects.Count) objects to $Path")) {
                try {
                    # Create writer if not already created
                    if ($null -eq $writer) {
                        $writer = New-Object Dataplat.Dbatools.Csv.Writer.CsvWriter($Path, $writerOptions)
                    }

                    # Get properties from first object for header
                    $firstObject = $inputObjects[0]
                    $properties = $firstObject.PSObject.Properties | Where-Object MemberType -eq "NoteProperty" | Select-Object -ExpandProperty Name

                    if ($properties.Count -eq 0) {
                        # Try getting all properties if NoteProperty didn't work
                        $properties = $firstObject.PSObject.Properties | Select-Object -ExpandProperty Name
                    }

                    # Write header
                    if ($writerOptions.WriteHeader) {
                        $writer.WriteHeader($properties)
                    }

                    # Write each object
                    foreach ($obj in $inputObjects) {
                        $values = foreach ($prop in $properties) {
                            $obj.$prop
                        }
                        $writer.WriteRow($values)
                        $rowsWritten++
                    }

                } catch {
                    Stop-Function -Message "Failed to export input objects" -ErrorRecord $_
                }
            }
        }

        # Dispose writer
        if ($null -ne $writer) {
            try {
                $writer.Dispose()
            } catch {
                Write-Message -Level Verbose -Message "Error disposing CSV writer: $_"
            }
        }

        $elapsed.Stop()

        # Return result object
        if ($rowsWritten -gt 0) {
            $fileInfo = Get-Item -Path $Path -ErrorAction SilentlyContinue

            [PSCustomObject]@{
                Path            = $Path
                RowsExported    = $rowsWritten
                FileSizeBytes   = if ($fileInfo) { $fileInfo.Length } else { 0 }
                FileSizeMB      = if ($fileInfo) { [math]::Round($fileInfo.Length / 1MB, 2) } else { 0 }
                CompressionType = $CompressionType
                Elapsed         = $elapsed.Elapsed
                RowsPerSecond   = [math]::Round($rowsWritten / $elapsed.Elapsed.TotalSeconds, 1)
            }
        }
    }
}
