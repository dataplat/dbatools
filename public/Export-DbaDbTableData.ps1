function Export-DbaDbTableData {
    <#
    .SYNOPSIS
        Generates INSERT statements from table data for migration and deployment scripts

    .DESCRIPTION
        Creates executable INSERT statements from existing table data, making it easy to move data between SQL Server instances or environments. This is particularly useful for migrating reference tables, lookup data, or configuration tables where you need the actual data values rather than just the table structure. The generated scripts include proper USE database context and can be saved to files or piped to other commands for further processing.

    .PARAMETER InputObject
        Accepts table objects from Get-DbaDbTable through the pipeline.
        Use this to process specific tables you've already identified rather than specifying table names again.

    .PARAMETER Path
        Sets the directory where output files will be created when not using FilePath.
        Defaults to the dbatools export directory configured in module settings.

    .PARAMETER FilePath
        Specifies the complete path and filename for the output SQL script.
        Use this when you need the INSERT statements saved to a specific file location for deployment or version control.

    .PARAMETER Encoding
        Controls the character encoding of the exported SQL file. Defaults to UTF8.
        Use UTF8 for compatibility with most modern SQL tools, or ASCII for older systems that don't support Unicode.

        Valid values are:
          - ASCII: Uses the encoding for the ASCII (7-bit) character set.
          - BigEndianUnicode: Encodes in UTF-16 format using the big-endian byte order.
          - Byte: Encodes a set of characters into a sequence of bytes.
          - String: Uses the encoding type for a string.
          - Unicode: Encodes in UTF-16 format using the little-endian byte order.
          - UTF7: Encodes in UTF-7 format.
          - UTF8: Encodes in UTF-8 format.
          - Unknown: The encoding type is unknown or invalid. The data can be treated as binary.

    .PARAMETER Passthru
        Displays the generated INSERT statements in the PowerShell console in addition to file output.
        Useful for reviewing the script content before execution or when piping to other commands.

    .PARAMETER BatchSeparator
        Adds batch separators (like GO) between INSERT statements in the output script.
        Use this when creating deployment scripts that will be executed in SQL Server Management Studio or sqlcmd.

    .PARAMETER NoPrefix
        Excludes the USE database statement and other prefixes from the generated script.
        Use this when combining output with other scripts or when the database context is already established.

    .PARAMETER NoClobber
        Prevents overwriting existing files at the specified FilePath.
        Use this as a safety measure to avoid accidentally replacing important deployment scripts.

    .PARAMETER Append
        Adds the INSERT statements to the end of an existing file instead of creating a new one.
        Useful when building comprehensive deployment scripts from multiple table exports or combining with other SQL operations.

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
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Export-DbaDbTableData

    .EXAMPLE
        PS C:\> Get-DbaDbTable -SqlInstance sql2017 -Database AdventureWorks2014 -Table EmployeePayHistory | Export-DbaDbTableData

        Exports data from EmployeePayHistory in AdventureWorks2014 in sql2017

    .EXAMPLE
        PS C:\> Get-DbaDbTable -SqlInstance sql2017 -Database AdventureWorks2014 -Table EmployeePayHistory | Export-DbaDbTableData -FilePath C:\temp\export.sql -Append

        Exports data from EmployeePayHistory in AdventureWorks2014 in sql2017 using a trusted connection - Will append the output to the file C:\temp\export.sql if it already exists
        Script does not include Batch Separator and will not compile

    .EXAMPLE
        PS C:\> Get-DbaDbTable -SqlInstance sql2016 -Database MyDatabase -Table 'dbo.Table1', 'dbo.Table2' -SqlCredential sqladmin | Export-DbaDbTableData -FilePath C:\temp\export.sql -Append

        Exports only data from 'dbo.Table1' and 'dbo.Table2' in MyDatabase to C:\temp\export.sql and uses the SQL login "sqladmin" to login to sql2016
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Table[]]$InputObject,
        [string]$Path = (Get-DbatoolsConfigValue -FullName 'Path.DbatoolsExport'),
        [Alias("OutFile", "FileName")]
        [string]$FilePath,
        [ValidateSet('ASCII', 'BigEndianUnicode', 'Byte', 'String', 'Unicode', 'UTF7', 'UTF8', 'Unknown')]
        [string]$Encoding = 'UTF8',
        [string]$BatchSeparator = '',
        [switch]$NoPrefix,
        [switch]$Passthru,
        [switch]$NoClobber,
        [switch]$Append,
        [switch]$EnableException
    )

    begin {
        $ScriptingOptionsObject = New-DbaScriptingOption
        $ScriptingOptionsObject.ScriptSchema = $false
        $ScriptingOptionsObject.ScriptData = $true
        $ScriptingOptionsObject.IncludeDatabaseContext = $true
    }

    process {
        if ($Pscmdlet.ShouldProcess($env:computername, "Exporting $InputObject")) {
            Export-DbaScript @PSBoundParameters -ScriptingOptionsObject $ScriptingOptionsObject
        }
    }
}