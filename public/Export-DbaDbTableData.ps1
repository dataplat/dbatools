function Export-DbaDbTableData {
    <#
    .SYNOPSIS
        Generates INSERT statements from table data for migration and deployment scripts

    .DESCRIPTION
        Creates executable INSERT statements from existing table data, making it easy to move data between SQL Server instances or environments. This is particularly useful for migrating reference tables, lookup data, or configuration tables where you need the actual data values rather than just the table structure. By default the generated scripts start with a USE statement for the database of each table. They can be saved to files or piped to other commands for further processing.

        Tables piped into one call that write to the same file all end up in that file, even without -Append.

    .PARAMETER InputObject
        Accepts table objects from Get-DbaDbTable through the pipeline.
        Use this to process specific tables you've already identified rather than specifying table names again.

    .PARAMETER ScriptingOptionsObject
        Accepts an SMO ScriptingOptions object created with New-DbaScriptingOption to control script generation.
        Without it, the command scripts the data only (ScriptData = $true, ScriptSchema = $false) and includes the USE statement (IncludeDatabaseContext = $true).
        An object you pass is used exactly as given, so set ScriptData = $true yourself. Set IncludeDatabaseContext = $false to omit the USE statement, or keep ScriptSchema = $true to script the table definition as well.

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
        Adds a batch separator (like GO) after every statement in the output file.
        Defaults to the Formatting.BatchSeparator configuration value, which is GO. Pass an empty string to write the statements without a separator.
        With -Passthru, a separator is only added when the ScriptingOptionsObject has ScriptBatchTerminator set to $true.

    .PARAMETER NoPrefix
        Excludes the comment header with the creator, timestamp, and dbatools version from the generated script.
        This does not remove the USE statement. To omit it, pass a ScriptingOptionsObject with IncludeDatabaseContext set to $false.

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

    .OUTPUTS
        System.IO.FileInfo

        When used without -Passthru, returns file information objects for the created SQL script files.

        Properties:
        - Name: The filename of the generated SQL script
        - FullName: The complete file path to the generated script
        - Directory: The directory containing the script file
        - Length: The size of the file in bytes
        - LastWriteTime: When the file was last modified
        - CreationTime: When the file was created

        System.String (when -Passthru is specified)

        Returns the generated INSERT statements as string output. Multiple strings are returned for table data scripts, one per INSERT statement or batch. A batch separator is only added when the ScriptingOptionsObject has ScriptBatchTerminator set to $true.

    .EXAMPLE
        PS C:\> Get-DbaDbTable -SqlInstance sql2017 -Database AdventureWorks2014 -Table EmployeePayHistory | Export-DbaDbTableData

        Exports data from EmployeePayHistory in AdventureWorks2014 in sql2017

    .EXAMPLE
        PS C:\> Get-DbaDbTable -SqlInstance sql2017 -Database AdventureWorks2014 -Table EmployeePayHistory | Export-DbaDbTableData -FilePath C:\temp\export.sql -Append

        Exports data from EmployeePayHistory in AdventureWorks2014 in sql2017 using a trusted connection - Will append the output to the file C:\temp\export.sql if it already exists
        Every statement is followed by the batch separator from the Formatting.BatchSeparator configuration value, which is GO

    .EXAMPLE
        PS C:\> Get-DbaDbTable -SqlInstance sql2016 -Database MyDatabase -Table 'dbo.Table1', 'dbo.Table2' -SqlCredential sqladmin | Export-DbaDbTableData -FilePath C:\temp\export.sql -Append

        Exports only data from 'dbo.Table1' and 'dbo.Table2' in MyDatabase to C:\temp\export.sql and uses the SQL login "sqladmin" to login to sql2016

    .EXAMPLE
        PS C:\> $options = New-DbaScriptingOption
        PS C:\> $options.ScriptSchema = $false
        PS C:\> $options.ScriptData = $true
        PS C:\> $options.IncludeDatabaseContext = $false
        PS C:\> Get-DbaDbTable -SqlInstance sql2017 -Database MyDatabase -Table dbo.Table1, dbo.Table2 | Export-DbaDbTableData -FilePath C:\temp\export.sql -ScriptingOptionsObject $options -NoPrefix

        Exports the data of both tables to C:\temp\export.sql without the USE statement and without the comment header, so the script runs in whatever database it is executed in
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Table[]]$InputObject,
        [Alias("ScriptingOptionObject")]
        [Microsoft.SqlServer.Management.Smo.ScriptingOptions]$ScriptingOptionsObject,
        [string]$Path = (Get-DbatoolsConfigValue -FullName 'Path.DbatoolsExport'),
        [Alias("OutFile", "FileName")]
        [string]$FilePath,
        [ValidateSet('ASCII', 'BigEndianUnicode', 'Byte', 'String', 'Unicode', 'UTF7', 'UTF8', 'Unknown')]
        [string]$Encoding = 'UTF8',
        [string]$BatchSeparator = (Get-DbatoolsConfigValue -FullName "Formatting.BatchSeparator"),
        [switch]$NoPrefix,
        [switch]$Passthru,
        [switch]$NoClobber,
        [switch]$Append,
        [switch]$EnableException
    )

    begin {
        if (Test-Bound -Not -ParameterName ScriptingOptionsObject) {
            $ScriptingOptionsObject = New-DbaScriptingOption
            $ScriptingOptionsObject.ScriptSchema = $false
            $ScriptingOptionsObject.ScriptData = $true
            $ScriptingOptionsObject.IncludeDatabaseContext = $true
        }

        # All tables go through one Export-DbaScript pipeline, so the tables after the first are appended
        # to the file instead of overwriting it. Calling Export-DbaScript once per table restarted its file handling every time.
        $splatExport = @{ }
        foreach ($boundName in $PSBoundParameters.Keys) {
            if ($boundName -ne "InputObject") {
                $splatExport[$boundName] = $PSBoundParameters[$boundName]
            }
        }
        $splatExport["ScriptingOptionsObject"] = $ScriptingOptionsObject
        $splatExport["BatchSeparator"] = $BatchSeparator
        $exportPipeline = $null
    }

    process {
        if ($Pscmdlet.ShouldProcess($env:computername, "Exporting $InputObject")) {
            # Started on the first table, so -WhatIf never reaches Export-DbaScript
            if ($null -eq $exportPipeline) {
                $exportCommand = { Export-DbaScript @splatExport }
                # Begin($PSCmdlet) instead of Begin($true) connects the pipeline to this command, so the warnings of Export-DbaScript reach -WarningVariable
                $exportPipeline = $exportCommand.GetSteppablePipeline($MyInvocation.CommandOrigin)
                $exportPipeline.Begin($PSCmdlet)
            }
            foreach ($table in $InputObject) {
                $exportPipeline.Process($table)
            }
        }
    }

    end {
        if ($null -ne $exportPipeline) {
            $exportPipeline.End()
        }
    }
}