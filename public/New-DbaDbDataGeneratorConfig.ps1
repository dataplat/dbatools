function New-DbaDbDataGeneratorConfig {
    <#
    .SYNOPSIS
        Creates JSON configuration files for generating realistic test data in SQL Server database tables

    .DESCRIPTION
        Analyzes database table structures and generates JSON configuration files that define how to populate each column with realistic fake data. The function examines column names, data types, constraints, and relationships to intelligently map appropriate data generation rules using the Bogus library. Column names matching common patterns (like "Address", "Email", "Phone") automatically get contextually appropriate fake data types, while other columns get sensible defaults based on their SQL data types.

        These configuration files serve as the blueprint for Invoke-DbaDbDataGenerator, allowing DBAs to create development databases with realistic test data instead of using production data. Perfect for building demo environments, testing applications with meaningful datasets, or creating training databases that mirror production schemas but contain no sensitive information.

        The function handles identity columns, foreign key relationships, unique indexes, and nullable constraints while skipping unsupported column types like computed columns, spatial data types, and XML. Configuration files are saved with the naming convention "servername.databasename.DataGeneratorConfig.json" for easy identification and reuse.

        Read more here:
        https://sachabarbs.wordpress.com/2018/06/11/bogus-simple-fake-data-tool/
        https://github.com/bchavez/Bogus

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies which databases to analyze for data generation configuration creation. Accepts multiple database names.
        Use this when you need to create test data configs for specific databases instead of all databases on the instance.

    .PARAMETER Table
        Specifies which tables to include in the data generation configuration. Accepts multiple table names and supports wildcards.
        Use this when you only need test data for specific tables rather than analyzing the entire database schema.

    .PARAMETER ResetIdentity
        Controls whether identity columns should reset to their seed values when generating test data. When enabled, identity values start from the original seed.
        Use this when you need predictable, consistent identity values across test data generation runs instead of continuing from existing maximum values.

    .PARAMETER TruncateTable
        Enables table truncation before inserting generated test data. When specified, existing data is removed before populating with fake data.
        Use this when you need clean test environments or want to replace all existing data rather than appending to current table contents.

    .PARAMETER Rows
        Sets the number of test data rows to generate for each table in the configuration. Defaults to 1000 rows per table.
        Adjust this based on your testing needs - use smaller values for development environments or larger values for performance testing scenarios.

    .PARAMETER Path
        Specifies the directory where JSON configuration files will be saved. Files are named using the pattern "servername.databasename.DataGeneratorConfig.json".
        Choose a location accessible to your development team since these config files will be used by Invoke-DbaDbDataGenerator to create the actual test data.

    .PARAMETER Force
        Allows the function to create the specified Path directory if it doesn't exist. Without this switch, the function will fail if the target directory is missing.
        Use this when setting up new test data workflows where the output directory structure hasn't been established yet.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: DataGeneration, Database
        Author: Sander Stad (@sqlstad, sqlstad.nl)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/New-DbaDbDataGeneratorConfig

    .OUTPUTS
        System.IO.FileInfo

        Returns file information for each JSON configuration file that was successfully written to disk.

        Properties:
        - Name: The filename of the generated configuration file (format: servername.databasename.DataGeneratorConfig.json)
        - FullName: The complete file path where the configuration was saved
        - Length: The size of the JSON file in bytes
        - CreationTime: The datetime when the file was created
        - LastWriteTime: The datetime when the file was last written
        - DirectoryName: The directory path containing the configuration file

        The output object allows you to verify which configuration files were created and their locations for use with Invoke-DbaDbDataGenerator.

    .EXAMPLE
        New-DbaDbDataGeneratorConfig -SqlInstance SQLDB1 -Database DB1 -Path C:\Temp\clone

        Process all tables and columns for database DB1 on instance SQLDB1

    .EXAMPLE
        New-DbaDbDataGeneratorConfig -SqlInstance SQLDB1 -Database DB1 -Table Customer -Path C:\Temp\clone

        Process only table Customer with all the columns

    #>
    [CmdLetBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param (
        [parameter(Mandatory)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [string[]]$Table,
        [switch]$ResetIdentity,
        [switch]$TruncateTable,
        [int]$Rows = 1000,
        [parameter(Mandatory)]
        [string]$Path,
        [switch]$Force,
        [switch]$EnableException
    )

    begin {

        # Get all the different column types
        try {
            $columnTypes = Get-Content -Path "$script:PSModuleRoot\bin\datamasking\columntypes.json" | ConvertFrom-Json
        } catch {
            Stop-Function -Message "Something went wrong importing the column types" -Continue
        }

        # Check if the Path is accessible
        if (-not (Test-Path -Path $Path)) {
            try {
                $null = New-Item -Path $Path -ItemType Directory -Force:$Force
            } catch {
                Stop-Function -Message "Could not create Path directory" -ErrorRecord $_ -Target $Path
            }
        } else {
            if ((Get-Item $path) -isnot [System.IO.DirectoryInfo]) {
                Stop-Function -Message "$Path is not a directory"
            }
        }
    }

    process {
        if (Test-FunctionInterrupt) {
            return
        }

        if ($SqlInstance) {
            $InputObject += Get-DbaDatabase -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database
        }

        $results = @()

        if ($InputObject.Count -lt 1) {
            Stop-Function -Message "No databases found" -Target $Database
            return
        }

        foreach ($db in $InputObject) {
            $server = $db.Parent
            $tables = @()

            # Get the tables
            if ($Table) {
                $tablecollection = $db | Get-DbaDbTable -Table $Table
            } else {
                $tablecollection = $db.Tables
            }

            if ($tablecollection.Count -lt 1) {
                Stop-Function -Message "The database does not contain any tables" -Target $db -Continue
            }

            # Loop through the tables
            foreach ($tableobject in $tablecollection) {
                Write-Message -Message "Processing table $($tableobject.Name)" -Level Verbose

                $hasUniqueIndex = $false

                if ($tableobject.Indexes.IsUnique) {
                    $hasUniqueIndex = $true
                }

                $columns = @()

                # Get the columns
                [array]$columncollection = $tableobject.Columns

                foreach ($columnobject in $columncollection) {
                    if ($columnobject.Computed) {
                        Write-Message -Level Verbose -Message "Skipping $columnobject because it is a computed column"
                        continue
                    }
                    if ($columnobject.DataType.Name -eq 'hierarchyid') {
                        Write-Message -Level Verbose -Message "Skipping $columnobject because it is a hierarchyid column"
                        continue
                    }
                    if ($columnobject.DataType.Name -eq 'geography') {
                        Write-Message -Level Verbose -Message "Skipping $columnobject because it is a geography column"
                        continue
                    }
                    if ($columnobject.DataType.Name -eq 'geometry') {
                        Write-Message -Level Verbose -Message "Skipping $columnobject because it is a geometry column"
                        continue
                    }
                    if ($columnobject.DataType.SqlDataType.ToString().ToLowerInvariant() -eq 'xml') {
                        Write-Message -Level Verbose -Message "Skipping $columnobject because it is a xml column"
                        continue
                    }

                    $dataGenType = $min = $null
                    $columnLength = $columnobject.Datatype.MaximumLength
                    $columnType = $columnobject.DataType.SqlDataType.ToString().ToLowerInvariant()

                    if (-not $columnType) {
                        $columnType = $columnobject.DataType.Name.ToLowerInvariant()
                    }

                    # Get the masking type with the synonym
                    $dataGenType = $columnTypes | Where-Object {
                        $columnobject.Name -in $_.Synonym
                    }

                    if ($dataGenType) {
                        $columns += [PSCustomObject]@{
                            Name            = $columnobject.Name
                            ColumnType      = $columnType
                            CharacterString = $null
                            MinValue        = $min
                            MaxValue        = $columnLength
                            MaskingType     = $dataGenType.MaskingType
                            SubType         = $dataGenType.SubType
                            Identity        = $columnobject.Identity
                            ForeignKey      = $columnobject.IsForeignKey
                            Composite       = $false
                            Nullable        = $columnobject.Nullable
                        }

                    } else {
                        $type = "Random"

                        switch ($columnType) {
                            { $_ -in "bit", "bool" } {
                                $subType = "Bool"
                                $MaxValue = $null
                            }
                            "bigint" {
                                $subType = "Number"
                                $MaxValue = 9223372036854775807
                            }
                            "int" {
                                $subType = "Number"
                                $MaxValue = 2147483647
                            }
                            "date" {
                                $type = "Date"
                                $subType = "Past"
                                $MaxValue = $null
                            }
                            "datetime" {
                                $type = "Date"
                                $subType = "Past"
                                $MaxValue = $null
                            }
                            "datetime2" {
                                $type = "Date"
                                $subType = "Past"
                                $MaxValue = $null
                            }
                            "float" {
                                $subType = "Float"
                                $MaxValue = $null
                            }
                            "smallint" {
                                $subType = "Number"
                                $MaxValue = 32767
                            }
                            "smalldatetime" {
                                $subType = "Date"
                                $MaxValue = $null
                            }
                            "tinyint" {
                                $subType = "Number"
                                $MaxValue = 255
                            }
                            "varbinary" {
                                $subType = "Byte"
                                $MaxValue = $columnLength
                            }
                            "varbinary" {
                                $subType = "Byte"
                                $MaxValue = $columnLength
                            }
                            "userdefineddatatype" {
                                if ($columnLength -eq 1) {
                                    $subType = "Bool"
                                    $MaxValue = $columnLength
                                } else {
                                    $subType = "String"
                                    $MaxValue = $columnLength
                                }
                            }
                            default {
                                $subType = "String"
                                $MaxValue = $columnLength
                            }
                        }

                        $columns += [PSCustomObject]@{
                            Name            = $columnobject.Name
                            ColumnType      = $columnType
                            CharacterString = $null
                            MinValue        = $min
                            MaxValue        = $MaxValue
                            MaskingType     = $type
                            SubType         = $subType
                            Identity        = $columnobject.Identity
                            ForeignKey      = $columnobject.IsForeignKey
                            Composite       = $false
                            Nullable        = $columnobject.Nullable
                        }
                    }
                }


                # Check if something needs to be generated
                if ($columns) {
                    $tables += [PSCustomObject]@{
                        Name           = $tableobject.Name
                        Schema         = $tableobject.Schema
                        Columns        = $columns
                        ResetIdentity  = [bool]$ResetIdentity
                        TruncateTable  = [bool]$TruncateTable
                        HasUniqueIndex = [bool]$hasUniqueIndex
                        Rows           = $Rows
                    }
                } else {
                    Write-Message -Message "No columns match for data generation in table $($tableobject.Name)" -Level Verbose
                }
            }

            # Check if something needs to be generated
            if ($tables) {
                $results += [PSCustomObject]@{
                    Name   = $db.Name
                    Type   = "DataGenerationConfiguration"
                    Tables = $tables
                }
            } else {
                Write-Message -Message "No columns match for data generation in table $($tableobject.Name)" -Level Verbose
            }
        }

        # Write the data to the Path
        if ($results) {
            try {
                $temppath = "$Path\$($server.Name.Replace('\', '$')).$($db.Name).DataGeneratorConfig.json"
                if (-not $script:isWindows) {
                    $temppath = $temppath.Replace("\", "/")
                }
                if ($Pscmdlet.ShouldProcess("$temppath", "Saving results to json")) {
                    Set-Content -Path $temppath -Value ($results | ConvertTo-Json -Depth 5)
                    Get-ChildItem -Path $temppath
                }
            } catch {
                Stop-Function -Message "Something went wrong writing the results to the Path" -Target $Path -Continue -ErrorRecord $_
            }
        } else {
            Write-Message -Message "No tables to save for database $($db.Name) on $($server.Name)" -Level Verbose
        }
    }
}