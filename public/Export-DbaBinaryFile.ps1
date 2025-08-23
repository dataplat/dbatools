function Export-DbaBinaryFile {
    <#
    .SYNOPSIS
        Extracts binary data from SQL Server tables and writes it to physical files

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
        The database(s) to process - this list is auto-populated from the server. If unspecified, all databases will be processed.

    .PARAMETER Table
        Define a specific table you would like to query. You can specify up to three-part name like db.sch.tbl.

        If the object has special characters please wrap them in square brackets [ ].
        Using dbo.First.Table will try to find table named 'Table' on schema 'First' and database 'dbo'.
        The correct way to find table named 'First.Table' on schema 'dbo' is by passing dbo.[First.Table]
        Any actual usage of the ] must be escaped by duplicating the ] character.
        The correct way to find a table Name] in schema Schema.Name is by passing [Schema.Name].[Name]]]

    .PARAMETER Schema
        Only return tables from the specified schema

    .PARAMETER Path
        Specifies the directory where files will be exported.

    .PARAMETER FilePath
        The specific filename of the output file. If not specified, the filename will use the filename column to determine the filename.

    .PARAMETER FileNameColumn
        The column name that contains the filename. If not specified, we'll try out best to figure it out.

    .PARAMETER BinaryColumn
        The column name that contains the binary data. If not specified, we'll try out best to figure it out.

    .PARAMETER Query
        Allows you to specify a custom query to use to return the data. If not specified, we'll try out best to figure it out.

        Example query: "SELECT [fn], [data] FROM tempdb.dbo.files"

    .PARAMETER InputObject
        Table objects to be piped in from Get-DbaDbTable or Get-DbaBinaryFileTable

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

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