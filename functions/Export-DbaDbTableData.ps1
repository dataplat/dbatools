function Export-DbaDbTableData {
    <#
    .SYNOPSIS
        Exports data from tables

    .DESCRIPTION
        Exports data from tables

    .PARAMETER InputObject
        Pipeline input from Get-DbaDbTable

    .PARAMETER Path
        Specifies the directory where the file or files will be exported.

    .PARAMETER FilePath
        Specifies the full file path of the output file.

    .PARAMETER Encoding
        Specifies the file encoding. The default is UTF8.

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
        Output script to console

    .PARAMETER BatchSeparator
        Specifies the Batch Separator to use. Default is None

    .PARAMETER NoPrefix
        Do not include a Prefix

    .PARAMETER NoClobber
        Do not overwrite file

    .PARAMETER Append
        Append to file

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
        PS C:\> Get-DbaDbTable -SqlInstance sql2017 -Database AdventureWorks2014 -Table EmployeePayHistory | Export-DbaDbTableData -Path C:\temp\export.sql -Append

        Exports data from EmployeePayHistory in AdventureWorks2014 in sql2017 using a trusted connection - Will append the output to the file C:\temp\export.sql if it already exists
        Script does not include Batch Separator and will not compile

    .EXAMPLE
        PS C:\> Get-DbaDbTable -SqlInstance sql2016 -Database MyDatabase -Table 'dbo.Table1', 'dbo.Table2' -SqlCredential sqladmin | Export-DbaDbTableData -Path C:\temp\export.sql

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