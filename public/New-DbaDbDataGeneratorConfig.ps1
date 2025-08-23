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
        Databases to process through

    .PARAMETER Table
        Tables to process. By default all the tables will be processed.

    .PARAMETER ResetIdentity
        Resets the identity column for a table to it's starting value. By default it will continue with the next identity.

    .PARAMETER TruncateTable
        Truncates the tabel befoe inserting the values.

    .PARAMETER Rows
        Amount of rows that need to be generated. The default is 1000.

    .PARAMETER Path
        Path where to save the generated JSON files.
        The naming convention will be "servername.databasename.tables.json".

    .PARAMETER Force
        Forcefully execute commands when needed.

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