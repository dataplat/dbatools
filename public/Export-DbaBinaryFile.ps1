function Export-DbaBinaryFile {
    <#
    .SYNOPSIS
        Extracts binary data from SQL Server tables and writes it to physical files.

    .DESCRIPTION
        Retrieves binary data stored in SQL Server tables and writes it as files to the filesystem. This is useful for extracting documents, images, or other files that have been stored in database columns using binary, varbinary, or image datatypes.

        The function automatically detects filename and binary data columns based on column names and datatypes, but you can specify custom columns if needed. It supports streaming large files efficiently and can process multiple tables or databases in a single operation.

        If specific filename and binary columns aren't specified, the command will guess based on the datatype (binary/image) for the binary column and a match for "name" as the filename column.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies which databases to scan for tables containing binary data. Accepts wildcards for pattern matching.
        Use this to limit the export scope when you only need files from specific databases instead of scanning the entire instance.

    .PARAMETER Table
        Specifies the table(s) containing binary data to export. Supports three-part naming (database.schema.table) and wildcards.
        Use this when you know exactly which tables contain your stored files, such as document management or attachment tables.
        Wrap table names with special characters in square brackets, like [Documents.Archive] for tables with periods in the name.

    .PARAMETER Schema
        Limits the search to tables within specific schemas. Useful in databases with multiple schemas for organizing different application areas.
        Common schemas include dbo, app, archive, or custom business schemas where file storage tables are organized.

    .PARAMETER Path
        Sets the target directory where exported files will be saved using their original filenames from the database.
        The directory will be created if it doesn't exist. Use this when exporting multiple files and want to preserve their original names.

    .PARAMETER FilePath
        Specifies the exact path and filename for a single exported file, overriding the stored filename.
        Use this when exporting one specific file or when you need to rename the output file to a standardized naming convention.

    .PARAMETER FileNameColumn
        Identifies which column contains the original filename or file identifier for the stored binary data.
        The function auto-detects columns with 'name' in the column name, but specify this when your filename column has a different naming pattern like 'DocumentName' or 'FileID'.

    .PARAMETER BinaryColumn
        Identifies which column contains the actual binary file data to export.
        The function auto-detects binary, varbinary, and image columns, but specify this when you have multiple binary columns or non-standard column names like 'DocumentData' or 'FileContent'.

    .PARAMETER Query
        Provides a custom SQL query to retrieve specific files based on complex criteria or joins.
        Use this when you need to filter files by metadata, join with other tables, or when the auto-detection doesn't work with your table structure.
        Your query must return exactly two columns: filename and binary data in that order.

    .PARAMETER InputObject
        Accepts table objects from the pipeline, typically from Get-DbaDbTable or Get-DbaBinaryFileTable.
        Use this for advanced scenarios where you need to pre-filter or analyze tables before exporting their binary content.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .OUTPUTS
        System.IO.FileInfo

        Returns one FileInfo object for each binary file successfully exported to the filesystem.

        Properties:
        - FullName: The complete path to the exported file
        - Name: The filename of the exported file (without path)
        - DirectoryName: The directory path where the file was exported
        - Directory: DirectoryInfo object for the parent directory
        - Extension: The file extension (e.g., .jpg, .pdf)
        - Length: Size of the file in bytes
        - CreationTime: When the file was created on disk
        - LastWriteTime: When the file was last written
        - Attributes: File attributes (Archive, ReadOnly, etc.)

        Files are written with the original filename from the FileNameColumn if using -Path, or with the specified filename if using -FilePath. Only successfully exported files are returned.

    .NOTES
        Tags: Migration, Backup, Export
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2022 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Export-DbaBinaryFile

    .EXAMPLE
        PS C:\> Export-DbaBinaryFile -SqlInstance sqlcs -Database test -Path C:\temp\exports

        Exports all binary files from the test database on sqlcs to C:\temp\exports. Guesses the columns based on datatype and column name.

    .EXAMPLE
        PS C:\> Export-DbaBinaryFile -SqlInstance sqlcs -Database employees -Table photos  -Path C:\temp\exports

        Exports all binary files from the photos table in the employees database on sqlcs to C:\temp\exports. Guesses the columns based on datatype and column name.

    .EXAMPLE
        PS C:\> Export-DbaBinaryFile -SqlInstance sqlcs -Database employees -Table photos -FileNameColumn fname -BinaryColumn data -Path C:\temp\exports

        Exports all binary files from the photos table in the employees database on sqlcs to C:\temp\exports. Uses the fname and data columns for the filename and binary data.

    .EXAMPLE
        PS C:\> Export-DbaBinaryFile -SqlInstance sqlcs -Database employees -Table photos -Query "SELECT [FileName], [Data] FROM [employees].[dbo].[photos] WHERE FirstName = 'Potato' and LastName = 'Qualitee'" -FilePath C:\temp\PotatoQualitee.jpg

        Exports the binary file from the photos table in the employees database on sqlcs to C:\temp\PotatoQualitee.jpg. Uses the query to determine the filename and binary data.

    .EXAMPLE
        PS C:\> Get-DbaBinaryFileTable -SqlInstance sqlcs -Database test | Out-GridView -Passthru | Export-DbaBinaryFile -Path C:\temp

        Allows you to pick tables with columns to be exported by Export-DbaBinaryFile

    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [string[]]$Table,
        [string[]]$Schema,
        [string]$FileNameColumn,
        [string]$BinaryColumn,
        [string]$Path,
        [string]$Query,
        [Alias("OutFile", "FileName")]
        [string]$FilePath,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Table[]]$InputObject,
        [switch]$EnableException
    )
    begin {
        if ($Path -and $FilePath) {
            Stop-Function -Message "You cannot specify both -Path and -FilePath"
        }

        if (-not $Path -and -not $FilePath) {
            Stop-Function -Message "You must specify either -Path or -FilePath"
        }
        if ($Path) {
            if (-not (Test-Path -Path $Path -PathType Container)) {
                Write-Message -Level Verbose -Message "Creating path $Path"
                $null = New-Item -Path $Path -ItemType Directory -Force
            }
        }
    }
    process {
        if (Test-FunctionInterrupt) { return }
        if (-not $InputObject) {
            try {
                $InputObject = Get-DbaDbTable -SqlInstance $SqlInstance -Database $Database -Table $Table -Schema $Schema -SqlCredential $SqlCredential -EnableException
            } catch {
                Stop-Function -Message "Failed to get tables" -ErrorRecord $PSItem
                return
            }
        }

        Write-Message -Level Verbose -Message "Found $($InputObject.count) tables"
        foreach ($tbl in $InputObject) {
            # auto detect column that is binary
            # if none or multiple, make them specify the binary column
            # auto detect column that is a name
            # if none or multiple, make them specify the filename column or extension
            $server = $tbl.Parent.Parent
            $db = $tbl.Parent

            if (-not $PSBoundParameters.Query) {
                if (-not $PSBoundParameters.FileNameColumn) {
                    $FileNameColumn = ($tbl.Columns | Where-Object Name -Match Name).Name
                    if ($FileNameColumn.Count -gt 1) {
                        Stop-Function -Message "Multiple column names match the phrase 'name' in $($tbl.Name) in $($tbl.Parent.Name) on $($server.Name). Please specify the column to use with -FileNameColumn" -Continue
                    }
                    if ($FileNameColumn.Count -eq 0) {
                        Stop-Function -Message "No column names match the phrase 'name' in $($tbl.Name) in $($tbl.Parent.Name) on $($server.Name). Please specify the column to use with -FileNameColumn" -Continue
                    }
                }

                if (-not $PSBoundParameters.BinaryColumn) {
                    $BinaryColumn = ($tbl.Columns | Where-Object { $PSItem.DataType.Name -match "binary" -or $PSItem.DataType.Name -eq "image" }).Name
                    if ($BinaryColumn.Count -gt 1) {
                        Stop-Function -Message "Multiple columns have a binary datatype in $($tbl.Name) in $($tbl.Parent.Name) on $($server.Name). Please specify the column to use with -BinaryColumn" -Continue
                    }
                    if ($BinaryColumn.Count -eq 0) {
                        Stop-Function -Message "No columns have a binary datatype in $($tbl.Name) in $($tbl.Parent.Name) on $($server.Name). Please specify the column to use with -BinaryColumn" -Continue
                    }
                }
            }

            # Stream buffer size in bytes.
            $bufferSize = 8192
            if (-not $PSBoundParameters.Query) {
                $Query = "SELECT [$FileNameColumn], [$BinaryColumn] FROM $db.$tbl"
            }
            <#
                INSERT INTO [test].[dbo].[MyTable] ([FileName], TheFile)
                SELECT 'BackupCert.cer', * FROM OPENROWSET(BULK N'C:\temp\BackupCert.cer', SINGLE_BLOB) rs
            #>
            try {
                Write-Message -Level Verbose -Message "Query: $Query"
                $reader = $server.ConnectionContext.ExecuteReader($Query)

                # Create a byte array for the stream.
                $out = [array]::CreateInstance('Byte', $bufferSize)

                # Looping through records
                while ($reader.Read()) {
                    if (-not $PSBoundParameters.FilePath -and $Path) {
                        $FilePath = Join-Path -Path $Path -ChildPath (Split-Path -Path $reader.GetString(0) -Leaf)
                    }

                    if ($Pscmdlet.ShouldProcess($env:computername, "Exporting $FilePath from $($tbl.Name) in $($tbl.Parent.Name) on $($server.Name)")) {
                        # New BinaryWriter
                        $filestream = New-Object System.IO.FileStream $FilePath, Create, Write
                        $binarywriter = New-Object System.IO.BinaryWriter $filestream

                        $start = 0
                        # Read first byte stream
                        $received = $reader.GetBytes(1, $start, $out, 0, $bufferSize - 1)
                        while ($received -gt 0) {
                            $binarywriter.Write($out, 0, $received)
                            $binarywriter.Flush()
                            $start += $received
                            # Read next byte stream
                            $received = $reader.GetBytes(1, $start, $out, 0, $bufferSize - 1)
                        }

                        $filestream.Close()
                        $filestream.Dispose()
                        $binarywriter.Close()
                        $binarywriter.Dispose()

                        Get-ChildItem -Path $FilePath
                    }
                }
                $reader.Close()
            } catch {
                Stop-Function -Message "Failed to export binary file from $($tbl.Name) in $($tbl.Parent.Name) on $($server.Name)" -ErrorRecord $PSItem -Continue
            } finally {
                if (-not $reader.IsClosed ) {
                    $reader.Close()
                }
                if ($filestream.CanRead) {
                    $filestream.Close()
                    $filestream.Dispose()
                }
                if ($binarywriter) {
                    $binarywriter.Close()
                    $binarywriter.Dispose()
                }
            }
        }
    }
}