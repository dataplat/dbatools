function New-DbaDbMaskingConfig {
    <#
    .SYNOPSIS
        Generates a new data masking configuration file.

    .DESCRIPTION
        Generates a new data masking configuration file. This file is important to apply any data masking to the data in a database.

        Read more here:
        https://sachabarbs.wordpress.com/2018/06/11/bogus-simple-fake-data-tool/
        https://github.com/bchavez/Bogus

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

    .PARAMETER Credential
        Allows you to login to servers or folders
        To use:
        $scred = Get-Credential, then pass $scred object to the -Credential parameter.

    .PARAMETER Database
        Databases to process through

    .PARAMETER Table
        Tables to process. By default all the tables will be processed

    .PARAMETER Column
        Columns to process. By default all the columns will be processed

    .PARAMETER Path
        Path where to save the generated JSON files.
        Th naming conventio will be "databasename.tables.json"

    .PARAMETER Locale
        Set the local to enable certain settings in the masking

    .PARAMETER Force
        Forcefully execute commands when needed

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: DataMasking, Database
        Author: Sander Stad (@sqlstad, sqlstad.nl) | Chrissy LeMaire (@cl, netnerds.net)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/New-DbaDbMaskingConfig

    .EXAMPLE
        New-DbaDbMaskingConfig -SqlInstance SQLDB1 -Database DB1 -Path C:\Temp\clone

        Process all tables and columns for database DB1 on instance SQLDB1

    .EXAMPLE
        New-DbaDbMaskingConfig -SqlInstance SQLDB1 -Database DB1 -Table Customer -Path C:\Temp\clone

        Process only table Customer with all the columns

    .EXAMPLE
        New-DbaDbMaskingConfig -SqlInstance SQLDB1 -Database DB1 -Table Customer -Column City -Path C:\Temp\clone

        Process only table Customer and only the column named "City"

    #>
    [CmdLetBinding(SupportsShouldProcess)]
    param(
        [parameter(Mandatory)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [PSCredential]$Credential,
        [string[]]$Database,
        [string[]]$Table,
        [string[]]$Column,
        [parameter(Mandatory)]
        [string]$Path,
        [string]$Locale = 'en',
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
                $null = New-Item -Path $Path -ItemType Directory -Credential $Credential -Force:$Force
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
        if (Test-FunctionInterrupt) { return }

        if ($SqlInstance) {
            $InputObject += Get-DbaDatabase -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database
        }

        $results = @()
        foreach ($db in $InputObject) {
            $server = $db.Parent
            $tables = @()

            # Get the tables
            if ($Table) {
                $tablecollection = $db.Tables | Where-Object Name -in $Table
            } else {
                $tablecollection = $db.Tables
            }

            if ($tablecollection.Count -lt 1) {
                Stop-Function -Message "The database does not contain any tables" -Target $db -Continue
            }

            # Loop through the tables
            foreach ($tableobject in $tablecollection) {
                Write-Message -Message "Processing table $($tableobject.Name)" -Level Verbose

                $columns = @()

                # Get the columns
                if ($Column) {
                    [array]$columncollection = $tableobject.Columns | Where-Object Name -in $Column
                } else {
                    [array]$columncollection = $tableobject.Columns
                }

                foreach ($columnobject in $columncollection) {
                    # Skip identity columns
                    if ((-not $columnobject.Identity) -and (-not $columnobject.IsForeignKey)) {
                        $maskingType = $null

                        $columnLength = $columnobject.Properties['Length'].Value
                        $columnType = $columnobject.DataType.Name.ToLower()

                        # Get the masking type with the synonims
                        $maskingType = $columnTypes | Where-Object {$columnobject.Name -in $_.Synonim}

                        if ($maskingType) {
                            # Make it easier to get the type name
                            $maskingType = $maskingType | Select-Object TypeName -ExpandProperty TypeName

                            switch ($maskingType.ToLower()) {
                                "firstname" {
                                    $columns += [PSCustomObject]@{
                                        Name        = $columnobject.Name
                                        ColumnType  = $columnType
                                        MaxLength   = $columnLength
                                        MaskingType = "Name"
                                        SubType     = "Firstname"
                                    }
                                }
                                "lastname" {
                                    $columns += [PSCustomObject]@{
                                        Name        = $columnobject.Name
                                        ColumnType  = $columnType
                                        MaxLength   = $columnLength
                                        MaskingType = "Name"
                                        SubType     = "Lastname"
                                    }
                                }
                                "creditcard" {
                                    $columns += [PSCustomObject]@{
                                        Name        = $columnobject.Name
                                        ColumnType  = $columnType
                                        MaxLength   = $columnLength
                                        MaskingType = "Finance"
                                        SubType     = "CreditcardNumber"
                                    }
                                }
                                "address" {
                                    $columns += [PSCustomObject]@{
                                        Name        = $columnobject.Name
                                        ColumnType  = $columnType
                                        MaxLength   = $columnLength
                                        MaskingType = "Address"
                                        SubType     = "StreetAddress"
                                    }
                                }
                                "city" {
                                    $columns += [PSCustomObject]@{
                                        Name        = $columnobject.Name
                                        ColumnType  = $columnType
                                        MaxLength   = $columnLength
                                        MaskingType = "Address"
                                        SubType     = "City"
                                    }
                                }
                                "zipcode" {
                                    $columns += [PSCustomObject]@{
                                        Name        = $columnobject.Name
                                        ColumnType  = $columnType
                                        MaxLength   = $columnLength
                                        MaskingType = "Address"
                                        SubType     = "Zipcode"
                                    }
                                }
                            }
                        } else {
                            $type = "Random"

                            switch ($columnType) {
                                "bigint" {
                                    $subType = "Number"
                                    $maxLength = 9223372036854775807
                                }
                                "int" {
                                    $subType = "Number"
                                    $maxLength = 2147483647
                                }
                                "date" {
                                    $subType = "Date"
                                    $maxLength = $null
                                }
                                "datetime" {
                                    $subType = "Date"
                                    $maxLength = $null
                                }
                                "datetime2" {
                                    $subType = "Date"
                                    $maxLength = $null
                                }
                                "float" {
                                    $subType = "Float"
                                    $maxLength = $null
                                }
                                "smallint" {
                                    $subType = "Number"
                                    $maxLength = 32767
                                }
                                "smalldatetime" {
                                    $subType = "Date"
                                    $maxLength = $null
                                }
                                "tinyint" {
                                    $subType = "Number"
                                    $maxLength = 255
                                }
                                default {
                                    $subType = "String"
                                    $maxLength = $columnLength
                                }
                            }

                            $columns += [PSCustomObject]@{
                                Name        = $columnobject.Name
                                ColumnType  = $columnType
                                MaxLength   = $maxLength
                                MaskingType = $type
                                SubType     = $subType
                            }
                        }
                    }
                }

                # Check if something needs to be generated
                if ($columns) {
                    $tables += [PSCustomObject]@{
                        Name    = $tableobject.Name
                        Schema  = $tableobject.Schema
                        Columns = $columns
                    }
                } else {
                    Write-Message -Message "No columns match for masking in table $($tableobject.Name)" -Level Verbose
                }
            }

            # Check if something needs to be generated
            if ($tables) {
                $results += [PSCustomObject]@{
                    Name   = $db.Name
                    Tables = $tables
                }
            } else {
                Write-Message -Message "No columns match for masking in table $($tableobject.Name)" -Level Verbose
            }
        }

        # Write the data to the Path
        if ($results) {
            try {
                $temppath = "$Path\$($server.Name.Replace('\', '$')).$($db.Name).tables.json"
                if (-not $script:isWindows) {
                    $temppath = $temppath.Replace("\", "/")
                }
                Set-Content -Path $temppath -Credential $Credential -Value ($results | ConvertTo-Json -Depth 5)
                Get-ChildItem -Path $temppath
            } catch {
                Stop-Function -Message "Something went wrong writing the results to the Path" -Target $Path -Continue -ErrorRecord $_
            }
        } else {
            Write-Message -Message "No tables to save for database $($db.Name) on $($server.Name)" -Level Verbose
        }
    }
}