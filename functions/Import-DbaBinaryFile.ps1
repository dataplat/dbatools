function Import-DbaBinaryFile {
    <#
    .SYNOPSIS
        Imports binary files into SQL Server

    .DESCRIPTION
        Imports binary files into SQL Server

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

    .PARAMETER FilePath
        Specifies the full file path of the output file. Accepts pipeline input from Get-ChildItem.

    .PARAMETER Statement
        Sup

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
        PS C:\> Get-ChildItem C:\github\appveyor-lab\azure | Import-DbaBinaryFile -SqlInstance sqlcs -Database tempdb -Table BunchOFiles

        XYZ

    .EXAMPLE
        PS C:\> Import-DbaBinaryFile -SqlInstance sqlcs -Database tempdb -Table BunchOFiles -FilePath C:\github\appveyor-lab\azure\adalsql.msi

        XYZ
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [parameter(Mandatory)]
        [string]$Database,
        [parameter(Mandatory)]
        [string]$Table,
        [string]$Schema,
        [string]$Statement,
        [parameter(Mandatory, ValueFromPipeline)]
        [System.IO.FileInfo[]]$FilePath,
        [switch]$EnableException
    )
    begin {
        if ($Path -and $FilePath) {
            Stop-Function -Message "You cannot specify both -Path and -FilePath"
        }
        if ($Path) {
            if (-not (Test-Path -Path $Path -PathType Container)) {
                Stop-Function -Message "Path $Path does not exist"
            }
        }
    }
    process {
        if (Test-FunctionInterrupt) { return }
        try {
            $tables = Get-DbaDbTable -SqlInstance $SqlInstance -Database $Database -Table $Table -Schema $Schema -SqlCredential $SqlCredential -EnableException
        } catch {
            Stop-Function -Message "Failed to get tables" -ErrorRecord $PSItem
            return
        }
        Write-Message -Level Verbose -Message "Found $($tables.count) tables"
        foreach ($tbl in $tables) {
            # auto detect column that is binary
            # if none or multiple, make them specify the binary column
            # auto detect column that is a name
            # if none or multiple, make them specify the filename column or extension
            $server = $tbl.Parent.Parent
            $db = $tbl.Parent
            $connection = $server.ConnectionContext.SqlConnectionObject

            if (-not $Statement) {
                if (-not $PSBoundParameters.FileNameColumn) {
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
                if ($Pscmdlet.ShouldProcess($env:computername, "Importing $file")) {
                    try {
                        $filestream = New-Object System.IO.FileStream $file, Open
                        Write-Message -Level Verbose -Message "Importing $filename"

                        $binaryreader = New-Object System.IO.BinaryReader $filestream
                        $fileBytes = $binaryreader.ReadBytes($filestream.Length)

                        if (-not $Statement) {
                            $Statement = "INSERT INTO $db.$tbl ([$FileNameColumn], [$BinaryColumn]) VALUES (@FileName, @FileContents)"
                        }

                        Write-Message -Level Verbose -Message "Statement: $Statement"
                        $cmd = $server.ConnectionContext.SqlConnectionObject.CreateCommand()
                        $cmd.CommandText = $Statement
                        $cmd.Connection.Open()

                        $datatype = ($tbl.Columns | Where-Object Name -eq $BinaryColumn).DataType
                        Write-Message -Level Verbose -Message "Binary column datatype is $datatype"

                        $null = $cmd.Parameters.Add("@FileContents", $datatype).Value = $fileBytes
                        $null = $cmd.Parameters.AddWithValue("@FileName", $filename)
                        $null = $cmd.ExecuteScalar()

                        $filestream.Close()
                        $filestream.Dispose()
                        $binaryreader.Close()
                        $binaryreader.Dispose()
                        [PSCustomObject]@{
                            ComputerName = $server.NetName
                            InstanceName = $server.ServiceName
                            SqlInstance  = $server.DomainInstanceName
                            Database     = $db.Name
                            Table        = $tbl.Name
                            FilePath     = $file
                            Status       = "Success"
                        }
                    } catch {
                        Stop-Function -Message "Failed to import $file" -ErrorRecord $PSItem -Continue
                    }
                }
            }
        }
    }
}