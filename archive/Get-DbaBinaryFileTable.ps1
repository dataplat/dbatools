function Get-DbaBinaryFileTable {
    <#
    .SYNOPSIS
        Identifies tables containing binary columns and their associated filename columns for file extraction operations.

    .DESCRIPTION
        Scans database tables to find those containing binary data columns (binary, varbinary, image) and automatically identifies potential filename columns for file extraction workflows. This function is essential when you need to extract files that have been stored as BLOBs in SQL Server tables but aren't sure which tables contain binary data or how the filenames are stored.

        The function enhances table objects by adding BinaryColumn and FileNameColumn properties, making it easy to pipe results directly to Export-DbaBinaryFile for automated file extraction. This is particularly useful for legacy applications where files were stored in the database rather than the file system, or when you need to audit what binary content exists across your databases.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies which databases to scan for tables containing binary columns. Accepts wildcards for pattern matching.
        Use this to limit the search scope when you know which databases might contain file storage tables, reducing scan time on large instances.

    .PARAMETER Table
        Targets specific tables to analyze for binary columns instead of scanning all tables in the database. Supports three-part naming (database.schema.table) and wildcards.
        Use this when you already know which tables contain binary data, such as document storage tables or attachment tables in applications.
        Wrap table names with special characters in square brackets, and escape actual ] characters by doubling them.

    .PARAMETER Schema
        Restricts the search to tables within specific database schemas. Accepts multiple schema names and wildcards.
        Useful for focusing on application-specific schemas that typically contain file storage tables, such as 'Documents' or 'Attachments' schemas.

    .PARAMETER InputObject
        Accepts table objects piped directly from Get-DbaDbTable, allowing you to pre-filter tables before binary column analysis.
        Use this approach when you want to combine complex table filtering with binary column detection in a pipeline workflow.

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
        https://dbatools.io/Get-DbaBinaryFileTable

    .OUTPUTS
        Microsoft.SqlServer.Management.Smo.Table

        Returns one Table object for each table found containing binary columns (binary, varbinary, or image data types).

        Default display properties (via Select-DefaultView):
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - Database: The database name containing the table
        - Schema: The schema name containing the table
        - Name: The table name
        - BinaryColumn: The name(s) of the column(s) containing binary data; multiple values if multiple binary columns exist
        - FileNameColumn: The name of the column identified as containing filenames for extraction; empty if no column matches the pattern or multiple matches were found

        Additional properties available from the base SMO Table object include:
        - IndexSpaceUsed: Space consumed by indexes on the table (bytes)
        - DataSpaceUsed: Space consumed by table data (bytes)
        - RowCount: Number of rows in the table
        - HasClusteredIndex: Boolean indicating if the table has a clustered index
        - IsPartitioned: Boolean indicating if the table uses partitioning (SQL Server 2005+)
        - ChangeTrackingEnabled: Boolean indicating if change tracking is enabled (SQL Server 2008+)
        - IsFileTable: Boolean indicating if the table is a FileTable (SQL Server 2012+)
        - IsMemoryOptimized: Boolean indicating if the table is memory-optimized (SQL Server 2014+)
        - IsNode: Boolean indicating if the table is a node table (SQL Server 2017+)
        - IsEdge: Boolean indicating if the table is an edge table (SQL Server 2017+)
        - FullTextIndex: Full-text index configuration for the table if present

        All properties from the SMO Table object are accessible using Select-Object *.

    .EXAMPLE
        PS C:\> Get-DbaBinaryFileTable -SqlInstance sqlcs -Database test

        Returns a table with binary columns which can be used with Export-DbaBinaryFile and Import-DbaBinaryFile.

    .EXAMPLE
        PS C:\> Get-DbaBinaryFileTable -SqlInstance sqlcs -Database test | Out-GridView -Passthru | Export-DbaBinaryFile -Path C:\temp

        Allows you to pick tables with columns to be exported by Export-DbaBinaryFile
    #>
    [CmdletBinding()]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [string[]]$Table,
        [string[]]$Schema,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Table[]]$InputObject,
        [switch]$EnableException
    )
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
            $server = $tbl.Parent.Parent
            $BinaryColumn = ($tbl.Columns | Where-Object { $PSItem.DataType.Name -match "binary" -or $PSItem.DataType.Name -eq "image" }).Name
            $FileNameColumn = ($tbl.Columns | Where-Object Name -Match Name).Name
            if ($FileNameColumn.Count -gt 1) {
                Write-Message -Level Verbose -Message "Multiple column names match the phrase 'name' in $($tbl.Name) in $($tbl.Parent.Name) on $($server.Name). Please specify the column to use with -FileNameColumn"
            }
            if ($BinaryColumn.Count -gt 1) {
                Write-Message -Level Verbose -Message "Multiple columns have a binary datatype in $($tbl.Name) in $($tbl.Parent.Name) on $($server.Name)."
            }
            if ($BinaryColumn) {
                $tbl | Add-Member -NotePropertyName BinaryColumn -NotePropertyValue $BinaryColumn
                $tbl | Add-Member -NotePropertyName FileNameColumn -NotePropertyValue $FileNameColumn -PassThru | Select-DefaultView -Property "ComputerName", "InstanceName", "SqlInstance", "Database", "Schema", "Name", "BinaryColumn", "FileNameColumn"
            }
        }
    }
}