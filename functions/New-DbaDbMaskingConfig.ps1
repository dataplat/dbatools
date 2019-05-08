function New-DbaDbMaskingConfig {
    <#
    .SYNOPSIS
        Generates a new data masking configuration file to be used with Invoke-DbaDbDataMasking

    .DESCRIPTION
        Generates a new data masking configuration file. This file is important to apply any data masking to the data in a database.

        Note that the following column and data types are not currently supported:
        Identity
        ForeignKey
        Computed
        Hierarchyid
        Geography
        Geometry
        Xml

        Read more here:
        https://sachabarbs.wordpress.com/2018/06/11/bogus-simple-fake-data-tool/
        https://github.com/bchavez/Bogus

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

    .PARAMETER Database
        Databases to process through

    .PARAMETER Table
        Tables to process. By default all the tables will be processed

    .PARAMETER Column
        Columns to process. By default all the columns will be processed

    .PARAMETER Path
        Path where to save the generated JSON files.
        Th naming convention will be "servername.databasename.tables.json"

    .PARAMETER Locale
        Set the local to enable certain settings in the masking

    .PARAMETER Force
        Forcefully execute commands when needed

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
    [CmdLetBinding()]
    param (
        [parameter(Mandatory)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
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
            Stop-Function -Message "Something went wrong importing the column types" -ErrorRecord $_ -Continue
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

        $supportedDataTypes = 'bit', 'bool', 'char', 'date', 'datetime', 'datetime2', 'decimal', 'int', 'money', 'nchar', 'ntext', 'nvarchar', 'smalldatetime', 'text', 'time', 'uniqueidentifier', 'userdefineddatatype', 'varchar'
    }

    process {
        if (Test-FunctionInterrupt) {
            return
        }

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

                $hasUniqueIndex = $false

                if ($tableobject.Indexes.IsUnique) {
                    $hasUniqueIndex = $true
                }

                $columns = @()

                # Get the columns
                if ($Column) {
                    [array]$columncollection = $tableobject.Columns | Where-Object Name -in $Column
                } else {
                    [array]$columncollection = $tableobject.Columns
                }

                foreach ($columnobject in $columncollection) {
                    # Skip incompatible columns
                    if ($columnobject.Identity) {
                        Write-Message -Level Verbose -Message "Skipping $columnobject because it is an identity column"
                        continue
                    }

                    if ($columnobject.IsForeignKey) {
                        Write-Message -Level Verbose -Message "Skipping $columnobject because it is a foreign key"
                        continue
                    }

                    if ($columnobject.Computed) {
                        Write-Message -Level Verbose -Message "Skipping $columnobject because it is a computed column"
                        continue
                    }

                    if ($server.VersionMajor -ge 13 -and $columnobject.GeneratedAlwaysType -ne 'None') {
                        Write-Message -Level Verbose -Message "Skipping $columnobject because it is a computed column for temporal tables"
                        continue
                    }

                    if ($columnobject.DataType.Name -notin $supportedDataTypes) {
                        Write-Message -Level Verbose -Message "Skipping $columnobject because it is not a supported data type"
                        continue
                    }

                    if ($columnobject.DataType.SqlDataType.ToString().ToLowerInvariant() -eq 'xml') {
                        Write-Message -Level Verbose -Message "Skipping $columnobject because it is a xml column"
                        continue
                    }

                    $maskingType = $columnType = $min = $null

                    if ($columnobject.Datatype.Name -in 'date', 'datetime', 'datetime2', 'smalldatetime', 'time') {
                        $columnLength = $columnobject.Datatype.NumericScale
                    } else {
                        $columnLength = $columnobject.Datatype.MaximumLength
                    }

                    if ($columnobject.InPrimaryKey -and $columnobject.DataType.SqlDataType.ToString().ToLowerInvariant() -notmatch 'date') {
                        $min = 2
                    }

                    if (-not $columnType) {
                        $columnType = $columnobject.DataType.Name.ToLowerInvariant()
                    }

                    # Get the masking type with the synonym
                    $maskingType = $columnTypes | Where-Object {
                        $columnobject.Name -in $_.Synonym
                    }

                    if ($maskingType) {
                        # Make it easier to get the type name
                        $maskingType = $maskingType | Select-Object TypeName -ExpandProperty TypeName

                        $type = $null
                        $subtype = $null

                        switch ($maskingType.ToLowerInvariant()) {
                            "address" {
                                $type = "Address"
                                $subtype = "StreetAddress"
                            }
                            "bic" {
                                $type = "Finance"
                                $subtype = "Bic"
                            }
                            "city" {
                                $type = "Address"
                                $subtype = "City"
                            }
                            "company" {
                                $type = "Company"
                                $subtype = "CompanyName"
                            }
                            "country" {
                                $type = "Address"
                                $subtype = "Country"
                            }
                            "countrycode" {
                                $type = "Address"
                                $subtype = "CountryCode"
                            }
                            "creditcard" {
                                $type = "Finance"
                                $subtype = "CreditcardNumber"
                            }
                            "creditcardcvv" {
                                $type = "Finance"
                                $subtype = "CreditCardCvv"
                            }
                            "email" {
                                $type = "Internet"
                                $subtype = "Email"
                            }
                            "ethereum" {
                                $type = "Finance"
                                $subtype = "EthereumAddress"
                            }
                            "firstname" {
                                $type = "Name"
                                $subtype = "Firstname"
                            }
                            "fullname" {
                                $type = "Name"
                                $subtype = "FullName"
                            }
                            "iban" {
                                $type = "Finance"
                                $subtype = "Iban"
                            }
                            "lastname" {
                                $type = "Name"
                                $subtype = "Lastname"
                            }
                            "latitude" {
                                $type = "Address"
                                $subtype = "Latitude"
                            }
                            "longitude" {
                                $type = "Address"
                                $subtype = "Longitude"
                            }
                            "phone" {
                                $type = "Phone"
                                $subtype = "PhoneNumber"
                            }
                            "state" {
                                $type = "Address"
                                $subtype = "State"
                            }
                            "stateabbr" {
                                $type = "Address"
                                $subtype = "StateAbbr"
                            }
                            "username" {
                                $type = "Internet"
                                $subtype = "UserName"
                            }
                            "zipcode" {
                                $type = "Address"
                                $subtype = "Zipcode"
                            }
                        }

                        $columns += [PSCustomObject]@{
                            Name            = $columnobject.Name
                            ColumnType      = $columnType
                            CharacterString = $null
                            MinValue        = $min
                            MaxValue        = $MaxValue
                            MaskingType     = $type
                            SubType         = $subtype
                            Format          = $null
                            Deterministic   = $false
                            Nullable        = $columnobject.Nullable
                            Composite       = $null
                        }

                    } else {
                        $type = "Random"

                        switch ($columnType) {
                            {
                                $_ -in "bit", "bool"
                            } {
                                $subType = "Bool"
                                $MaxValue = $null
                            }
                            "bigint" {
                                $subType = "Number"
                                $MaxValue = 9223372036854775807
                            }
                            {
                                $_ -in "char", "nchar", "nvarchar", "varchar"
                            } {
                                $subType = "String2"
                                $min = [int]($columnLength / 2)
                                $MaxValue = $columnLength
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
                            "decimal" {
                                $subType = "Decimal"
                                $MaxValue = $null
                            }
                            "float" {
                                $subType = "Float"
                                $MaxValue = $null
                            }
                            "money" {
                                $type = "Commerce"
                                $subType = "Price"
                                $min = -922337203685477.5808
                                $MaxValue = 922337203685477.5807
                            }
                            "smallint" {
                                $subType = "Number"
                                $MaxValue = 32767
                            }
                            "smalldatetime" {
                                $subType = "Date"
                                $MaxValue = $null
                            }
                            "text" {
                                $subType = "String"
                                $maxValue = 2147483647
                            }
                            "time" {
                                $type = "Date"
                                $subType = "Past"
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
                            "userdefineddatatype" {
                                if ($columnLength -eq 1) {
                                    $subType = "Bool"
                                    $MaxValue = $columnLength
                                } else {
                                    $subType = "String2"
                                    $min = [int]($columnLength / 2)
                                    $MaxValue = $columnLength
                                }
                            }
                            "uniqueidentifier" {
                                $subType = "Guid"
                            }
                            default {
                                $subType = "String2"
                                $min = [int]($columnLength / 2)
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
                            Format          = $null
                            Deterministic   = $false
                            Nullable        = $columnobject.Nullable
                            Composite       = $null
                        }
                    }
                }


                # Check if something needs to be generated
                if ($columns) {
                    $tables += [PSCustomObject]@{
                        Name           = $tableobject.Name
                        Schema         = $tableobject.Schema
                        Columns        = $columns
                        HasUniqueIndex = $hasUniqueIndex
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
                $filenamepart = $server.Name.Replace('\', '$').Replace('TCP:', '').Replace(',', '.')
                $temppath = "$Path\$($filenamepart).$($db.Name).tables.json"

                if (-not $script:isWindows) {
                    $temppath = $temppath.Replace("\", "/")
                }
                Set-Content -Path $temppath -Value ($results | ConvertTo-Json -Depth 5)
                Get-ChildItem -Path $temppath
            } catch {
                Stop-Function -Message "Something went wrong writing the results to the $Path" -Target $Path -Continue -ErrorRecord $_
            }
        } else {
            Write-Message -Message "No tables to save for database $($db.Name) on $($server.Name)" -Level Verbose
        }
    }
}