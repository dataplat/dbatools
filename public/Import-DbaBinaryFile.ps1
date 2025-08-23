function Import-DbaBinaryFile {
    <#
    .SYNOPSIS
        Loads binary files from the filesystem into SQL Server database tables

    .DESCRIPTION
        Reads binary files from disk and stores them in SQL Server tables with binary, varbinary, or image columns. This is useful for storing documents, images, executables, or any file type directly in the database for archival, content management, or application integration scenarios.

        The command automatically detects the appropriate columns for storing file data - it looks for binary-type columns (binary, varbinary, image) for the file contents and columns containing "name" for the filename. You can also specify exact column names or provide a custom INSERT statement for more complex scenarios.

        Files can be imported individually, from directories (with recursion), or piped in from Get-ChildItem. Each file is read as a byte array and inserted using parameterized queries to safely handle binary data of any size within SQL Server's limits.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies the target database where the binary files will be imported. Required when not using InputObject.
        Use this to identify which database contains the table for storing your binary files.

    .PARAMETER Table
        Specifies the target table where binary files will be stored. Must contain at least one binary-type column (binary, varbinary, image).
        Use this when importing files into a specific table designed for file storage. Supports three-part naming (db.schema.table).
        If the object has special characters please wrap them in square brackets [ ].
        Using dbo.First.Table will try to find table named 'Table' on schema 'First' and database 'dbo'.
        The correct way to find table named 'First.Table' on schema 'dbo' is by passing dbo.[First.Table]
        Any actual usage of the ] must be escaped by duplicating the ] character.
        The correct way to find a table Name] in schema Schema.Name is by passing [Schema.Name].[Name]]]

    .PARAMETER Schema
        Specifies the schema containing the target table. Defaults to the user's default schema if not specified.
        Use this when your table exists in a non-default schema or when you need to be explicit about schema ownership.

    .PARAMETER FilePath
        Specifies one or more individual files to import into the database table. Accepts pipeline input from Get-ChildItem.
        Use this when importing specific files rather than entire directories. Cannot be used with Path parameter.

    .PARAMETER Path
        Specifies a directory containing files to import. Recursively processes all files within the directory and subdirectories.
        Use this when bulk importing multiple files from a folder structure. Cannot be used with FilePath parameter.

    .PARAMETER Statement
        Provides a custom INSERT statement for complex import scenarios. Must include @FileContents parameter for binary data.
        Use this when automatic column detection fails or when you need custom INSERT logic with joins, triggers, or computed columns.
        Example: INSERT INTO db.tbl ([FileNameColumn], [bBinaryColumn]) VALUES (@FileName, @FileContents)
        The @FileContents parameter is required. Include @FileName parameter if storing filenames.

    .PARAMETER FileNameColumn
        Specifies which column will store the original filename. Auto-detects columns containing 'name' if not specified.
        Use this when your table has multiple name-related columns or when auto-detection fails to identify the correct column.

    .PARAMETER BinaryColumn
        Specifies which column will store the binary file data. Auto-detects binary, varbinary, or image columns if not specified.
        Use this when your table has multiple binary columns or when auto-detection fails to identify the correct storage column.

    .PARAMETER NoFileNameColumn
        Indicates that the target table does not have a column for storing filenames. Only the binary data will be imported.
        Use this when your table design only stores file content without filename metadata for blob storage scenarios.

    .PARAMETER InputObject
        Accepts table objects from Get-DbaDbTable for pipeline-based imports. Alternative to specifying Database and Table parameters.
        Use this when working with multiple tables or when integrating with other dbatools commands that return table objects.

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
        https://dbatools.io/Import-DbaBinaryFile

    .EXAMPLE
        PS C:\> Get-ChildItem C:\photos | Import-DbaBinaryFile -SqlInstance sqlcs -Database employees -Table photos

        Imports all photos from C:\photos into the photos table in the employees database on sqlcs. Automatically guesses the column names for the image and filename columns.

    .EXAMPLE
        PS C:\> Import-DbaBinaryFile -SqlInstance sqlcs -Database tempdb -Table BunchOFiles -FilePath C:\azure\adalsql.msi

        Imports the file adalsql.msi into the BunchOFiles table in the tempdb database on sqlcs. Automatically guesses the column names for the image and filename columns.

    .EXAMPLE
        PS C:\> Import-DbaBinaryFile -SqlInstance sqlcs -Database tempdb -Table BunchOFiles -FilePath C:\azure\adalsql.msi -FileNameColumn fname -BinaryColumn data

        Imports the file adalsql.msi into the BunchOFiles table in the tempdb database on sqlcs. Uses the fname and data columns for the filename and binary data.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string]$Database,
        [string]$Table,
        [string]$Schema,
        [string]$Statement,
        [string]$FileNameColumn,
        [string]$BinaryColumn,
        [switch]$NoFileNameColumn,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Table[]]$InputObject,
        [parameter(ValueFromPipelineByPropertyName)]
        [Alias("FullName")]
        [System.IO.FileInfo[]]$FilePath,
        [System.IO.FileInfo[]]$Path,
        [switch]$EnableException
    )
    process {
        # can't be in begin because it's piped in
        if ((-not $Database -or -not $Table) -and -not $InputObject) {
            Stop-Function -Message "You must specify either Database and Table or pipe in a table"
            return
        }

        if ($Path -and $FilePath) {
            Stop-Function -Message "You cannot specify both -Path and -FilePath"
            return
        }
        if (-not $Path -and -not $FilePath) {
            Stop-Function -Message "You cannot specify either -Path or -FilePath"
            return
        }
        if ($Path) {
            if (-not (Test-Path -Path $Path -PathType Container)) {
                Stop-Function -Message "Path $Path does not exist"
                return
            }
        }

        if ($FilePath) {
            if (-not (Test-Path $FilePath)) {
                Stop-Function -Message "File $FilePath does not exist" -Continue
            }

            if ((Get-Item -Path $FilePath).PSIsContainer) {
                Stop-Function -Message "FilePath must be one or more files, not a directory. For directories, use Path" -Continue
            }
        }

        if ($Path) {
            $FilePath = Get-ChildItem -Path $Path -Recurse -File
        }

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

            if (-not $Statement) {
                if (-not $PSBoundParameters.FileNameColumn -and -not $NoFileNameColumn) {
                    $FileNameColumn = ($tbl.Columns | Where-Object Name -match Name).Name
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

            foreach ($file in $FilePath) {
                $file = $file.FullName
                $filename = Split-Path -Path $file -Leaf
                if ($Pscmdlet.ShouldProcess($env:computername, "Importing $file to $($tbl.Name) in $($tbl.Parent.Name) on $($server.Name)")) {
                    try {
                        $filestream = New-Object System.IO.FileStream $file, Open
                        Write-Message -Level Verbose -Message "Importing $filename"

                        $binaryreader = New-Object System.IO.BinaryReader $filestream
                        $fileBytes = $binaryreader.ReadBytes($filestream.Length)

                        if (-not $Statement) {
                            if ($NoFileNameColumn) {
                                $Statement = "INSERT INTO $db.$tbl ([$BinaryColumn]) VALUES (@FileContents)"
                            } else {
                                $Statement = "INSERT INTO $db.$tbl ([$FileNameColumn], [$BinaryColumn]) VALUES (@FileName, @FileContents)"
                            }
                        }

                        Write-Message -Level Verbose -Message "Statement: $Statement"
                        $cmd = $server.ConnectionContext.SqlConnectionObject.CreateCommand()
                        $cmd.CommandText = $Statement
                        $cmd.Connection.Open()

                        $datatype = ($tbl.Columns | Where-Object Name -eq $BinaryColumn).DataType
                        Write-Message -Level Verbose -Message "Binary column datatype is $datatype"
                        if (-not $NoFileNameColumn) {
                            $null = $cmd.Parameters.AddWithValue("@FileName", $filename)
                        }
                        $null = $cmd.Parameters.AddWithValue("@FileContents", $datatype).Value = $fileBytes
                        $null = $cmd.ExecuteScalar()

                        try {
                            $cmd.Connection.Close()
                            $cmd.Dispose()
                            $filestream.Close()
                            $filestream.Dispose()
                            $binaryreader.Close()
                            $binaryreader.Dispose()
                        } catch {
                            Write-Message -Level Verbose -Message "Something went wrong: $PSItem"
                        }

                        [PSCustomObject]@{
                            ComputerName = $tbl.ComputerName
                            InstanceName = $tbl.InstanceName
                            SqlInstance  = $tbl.SqlInstance
                            Database     = $db.Name
                            Table        = $tbl.Name
                            FilePath     = $file
                            Status       = "Success"
                        }
                    } catch {
                        Stop-Function -Message "Failed to import $file" -ErrorRecord $PSItem -Continue
                    } finally {
                        if ($filestream.CanRead) {
                            $filestream.Close()
                            $filestream.Dispose()
                        }
                        if ($binaryreader) {
                            $binaryreader.Close()
                            $binaryreader.Dispose()
                        }
                        $null = $server | Disconnect-DbaInstance
                    }
                }
            }
        }
    }
}