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
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

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

    .PARAMETER CharacterString
        The characters to use in string data. 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789' by default

    .PARAMETER SampleCount
        Amount of rows to sample to make an assessment. The default is 100

    .PARAMETER KnownNameFilePath
        Points to a file containing the custom known names

    .PARAMETER PatternFilePath
        Points to a file containing the custom patterns

    .PARAMETER ExcludeDefaultKnownName
        Excludes the default known names

    .PARAMETER ExcludeDefaultPattern
        Excludes the default patterns

    .PARAMETER Force
        Forcefully execute commands when needed

    .PARAMETER InputObject
        Used for piping the values from Invoke-DbaDbPiiScan

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Masking, DataMasking
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
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low")]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [string[]]$Table,
        [string[]]$Column,
        [parameter(Mandatory)]
        [string]$Path,
        [string]$Locale = 'en',
        [string]$CharacterString = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789',
        [int]$SampleCount = 100,
        [string]$KnownNameFilePath,
        [string]$PatternFilePath ,
        [switch]$ExcludeDefaultKnownName,
        [switch]$ExcludeDefaultPattern,
        [switch]$Force,
        [parameter(ValueFromPipeline = $true)]
        [object[]]$InputObject,
        [switch]$EnableException
    )
    begin {

        # Initialize the arrays
        $knownNames = @()
        $patterns = @()

        # Get the known names
        if (-not $ExcludeDefaultKnownName) {
            try {
                $knownNameFilePath = Resolve-Path -Path "$script:PSModuleRoot\bin\datamasking\pii-knownnames.json"
                $knownNames += Get-Content -Path $knownNameFilePath -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            } catch {
                Stop-Function -Message "Couldn't parse known names file" -ErrorRecord $_
                return
            }
        }

        # Get the patterns
        if (-not $ExcludeDefaultPattern) {
            try {
                $patternFilePath = Resolve-Path -Path "$script:PSModuleRoot\bin\datamasking\pii-patterns.json"
                $patterns = Get-Content -Path $patternFilePath -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            } catch {
                Stop-Function -Message "Couldn't parse pattern file" -ErrorRecord $_
                return
            }
        }

        # Get custom known names and patterns
        if ($KnownNameFilePath) {
            if (Test-Path -Path $KnownNameFilePath) {
                try {
                    $knownNames += Get-Content -Path $KnownNameFilePath -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
                } catch {
                    Stop-Function -Message "Couldn't parse known types file" -ErrorRecord $_ -Target $KnownNameFilePath
                    return
                }
            } else {
                Stop-Function -Message "Couldn't not find known names file" -Target $KnownNameFilePath
            }
        }

        if ($PatternFilePath ) {
            if (Test-Path -Path $PatternFilePath ) {
                try {
                    $patterns += Get-Content -Path $PatternFilePath  -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
                } catch {
                    Stop-Function -Message "Couldn't parse patterns file" -ErrorRecord $_ -Target $PatternFilePath
                    return
                }
            } else {
                Stop-Function -Message "Couldn't not find patterns file" -Target $PatternFilePath
            }
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

        $supportedDataTypes = @(
            'bit', 'bigint', 'bool',
            'char', 'date',
            'datetime', 'datetime2', 'decimal',
            'float',
            'int',
            'money',
            'nchar', 'ntext', 'nvarchar',
            'smalldatetime', 'smallint',
            'text', 'time', 'tinyint',
            'uniqueidentifier', 'userdefineddatatype',
            'varchar'
        )

        $maskingconfig = @()
    }
    process {
        if (Test-FunctionInterrupt) { return }

        if ($InputObject) {
            $searchArray = @()
            $searchArray += $InputObject | Select-Object ComputerName, InstanceName, SqlInstance, Database, Schema, Table, Column
        }

        if ($SqlInstance) {
            $databases += Get-DbaDatabase -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database
        }

        foreach ($db in $databases) {
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
                Write-Message -Message "Processing table [$($tableobject.Schema)].[$($tableobject.Name)]" -Level Verbose

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
                    $result = $minValue = $maxValue = $null

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

                    $searchObject = [pscustomobject]@{
                        ComputerName = $db.Parent.ComputerName
                        InstanceName = $db.Parent.ServiceName
                        SqlInstance  = $db.Parent.DomainInstanceName
                        Database     = $db.Name
                        Schema       = $tableobject.Schema
                        Table        = $tableobject.Name
                        Column       = $columnobject.Name
                    }

                    if ($columnobject.Datatype.Name -in 'date', 'datetime', 'datetime2', 'smalldatetime', 'time') {
                        $columnLength = $columnobject.Datatype.NumericScale
                    } else {
                        $columnLength = $columnobject.Datatype.MaximumLength
                    }

                    $columnType = $columnobject.DataType.Name

                    switch ($columnType) {
                        "bigint" {
                            $minValue = 1
                            $maxValue = 9223372036854775807
                        }
                        { $_ -in "char", "nchar", "nvarchar", "varchar" } {
                            if ($columnLength -eq -1) {
                                if ($_ -in "char", "varchar") {
                                    $minValue = 1
                                    $maxValue = 8000
                                } elseif ($_ -in "nchar", "nvarchar") {
                                    $minValue = 1
                                    $maxValue = 4000
                                }
                            } else {
                                $minValue = [int]($columnLength / 2)
                                $maxValue = $columnLength
                            }
                        }
                        "date" { $maxValue = $null }
                        "datetime" { $maxValue = $null }
                        "datetime2" { $maxValue = $null }
                        "decimal" {
                            $minValue = 1.1
                            $maxValue = $null
                        }
                        "float" {
                            $minValue = 1.1
                            $maxValue = $null
                        }
                        "int" {
                            $minValue = 1
                            $maxValue = 2147483647
                        }
                        "money" {
                            $minValue = 1.0
                            $maxValue = 922337203685477.5807
                        }
                        "smallint" {
                            $minValue = 1
                            $maxValue = 32767
                        }
                        "smalldatetime" {
                            $maxValue = $null
                        }
                        "text" {
                            $minValue = 10
                            $maxValue = 2147483647
                        }
                        "time" {
                            $maxValue = $null
                        }
                        "tinyint" {
                            $minValue = 1
                            $maxValue = 255
                        }
                        "varbinary" {
                            $maxValue = $columnLength
                        }
                        "userdefineddatatype" {
                            if ($columnLength -eq 1) {
                                $maxValue = $columnLength
                            } else {
                                $minValue = [int]($columnLength / 2)
                                $maxValue = $columnLength
                            }
                        }
                        default {
                            $minValue = [int]($columnLength / 2)
                            $maxValue = $columnLength
                        }
                    }

                    if ($searchArray -contains $searchObject) {
                        $result = $InputObject | Where-Object { $_.Database -eq $searchObject.Name -and $_.Schema -eq $searchObject.Schema -and $_.Table -eq $searchObject.Name -and $_.Column -eq $searchObject.Name }
                    } else {

                        if ($columnobject.InPrimaryKey -and $columnobject.DataType.SqlDataType.ToString().ToLowerInvariant() -notmatch 'date') {
                            $minValue = 2
                        }

                        if ($columnobject.DataType.Name -eq "geography") {
                            # Add the results
                            $result = [pscustomobject]@{
                                ComputerName   = $db.Parent.ComputerName
                                InstanceName   = $db.Parent.ServiceName
                                SqlInstance    = $db.Parent.DomainInstanceName
                                Database       = $db.Name
                                Schema         = $tableobject.Schema
                                Table          = $tableobject.Name
                                Column         = $columnobject.Name
                                "PII-Category" = "Location"
                                "PII-Name"     = "Geography"
                                FoundWith      = "DataType"
                                MaskingType    = "Random"
                                MaskingSubType = "Decimal"
                            }
                        } else {
                            if ($knownNames.Count -ge 1) {
                                # Go through the first check to see if any column is found with a known name
                                foreach ($knownName in $knownNames) {
                                    foreach ($pattern in $knownName.Pattern) {
                                        if ($null -eq $result -and $columnobject.Name -match $pattern ) {
                                            # Add the results
                                            $result = [pscustomobject]@{
                                                ComputerName   = $db.Parent.ComputerName
                                                InstanceName   = $db.Parent.ServiceName
                                                SqlInstance    = $db.Parent.DomainInstanceName
                                                Database       = $db.Name
                                                Schema         = $tableobject.Schema
                                                Table          = $tableobject.Name
                                                Column         = $columnobject.Name
                                                "PII-Category" = $knownName.Category
                                                "PII-Name"     = $knownName.Name
                                                FoundWith      = "KnownName"
                                                MaskingType    = $knownName.MaskingType
                                                MaskingSubType = $knownName.MaskingSubType
                                            }
                                        }
                                    }
                                }
                                $knownName = $null
                            } else {
                                Write-Message -Level Verbose -Message "No known names found to perform check on"
                            }

                            # Go through the second check to see if any column is found with a known type
                            if ($patterns.Count -ge 1) {
                                if ($null -eq $result) {
                                    # Setup the query
                                    $query = "SELECT TOP($SampleCount) [$($columnobject.Name)] FROM [$($tableobject.Schema)].[$($tableobject.Name)]"

                                    # Get the data
                                    $dataset = @()

                                    try {
                                        $dataset += Invoke-DbaQuery -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $db.Name -Query $query -EnableException
                                    } catch {
                                        $errormessage = $_.Exception.Message.ToString()
                                        Stop-Function -Message "Error executing query [$($tableobject.Schema)].[$($tableobject.Name)]: $errormessage" -Target $updatequery -Continue -ErrorRecord $_
                                    }

                                    # Check if there is any data
                                    if ($dataset.Count -ge 1) {

                                        # Loop through the patterns
                                        foreach ($patternobject in $patterns) {

                                            # If there is a result from the match
                                            if ($null -eq $result -and $dataset.$($columnobject.Name) -match $patternobject.Pattern) {
                                                # Add the results
                                                $result = [pscustomobject]@{
                                                    ComputerName   = $db.Parent.ComputerName
                                                    InstanceName   = $db.Parent.ServiceName
                                                    SqlInstance    = $db.Parent.DomainInstanceName
                                                    Database       = $db.Name
                                                    Schema         = $tableobject.Schema
                                                    Table          = $tableobject.Name
                                                    Column         = $columnobject.Name
                                                    "PII-Category" = $patternobject.Category
                                                    "PII-Name"     = $patternobject.Name
                                                    FoundWith      = "Pattern"
                                                    MaskingType    = $patternobject.MaskingType
                                                    MaskingSubType = $patternobject.MaskingSubType
                                                }
                                            }
                                            $patternobject = $null
                                        }
                                    } else {
                                        Write-Message -Message "Table $($tableobject.Name) does not contain any rows" -Level Verbose
                                    }
                                }
                            } else {
                                Write-Message -Level Verbose -Message "No patterns found to perform check on"
                            }
                        }
                    }

                    if ($result) {
                        $columns += [PSCustomObject]@{
                            Name            = $columnobject.Name
                            ColumnType      = $columnType
                            CharacterString = $( if ($result.MaskingType -in "String", "String2") { $CharacterString } else { $null } )
                            MinValue        = $minValue
                            MaxValue        = $maxValue
                            MaskingType     = $result.MaskingType
                            SubType         = $result.MaskingSubType
                            Format          = $null
                            Separator       = $null
                            Deterministic   = $false
                            Nullable        = $columnobject.Nullable
                            KeepNull        = $true
                            Composite       = $null
                            Action          = $null
                            StaticValue     = $null
                        }
                    } else {
                        $type = "Random"

                        switch ($columnType) {
                            { $_ -in "bit", "bool" } { $subType = "Bool" }
                            "bigint" { $subType = "Number" }
                            { $_ -in "char", "nchar", "nvarchar", "varchar" } { $subType = "String2" }
                            "date" {
                                $type = "Date"
                                $subType = "Past"
                            }
                            "datetime" {
                                $type = "Date"
                                $subType = "Past"
                            }
                            "datetime2" {
                                $type = "Date"
                                $subType = "Past"
                            }
                            "decimal" { $subType = "Decimal" }
                            "float" { $subType = "Float" }
                            "int" { $subType = "Number" }
                            "money" {
                                $type = "Commerce"
                                $subType = "Price"
                            }
                            "smallint" { $subType = "Number" }
                            "smalldatetime" { $subType = "Date" }
                            "text" { $subType = "String" }
                            "time" {
                                $type = "Date"
                                $subType = "Past"
                            }
                            "tinyint" { $subType = "Number" }
                            "varbinary" { $subType = "Byte" }
                            "userdefineddatatype" {
                                if ($columnLength -eq 1) {
                                    $subType = "Bool"
                                } else {
                                    $subType = "String2"
                                }
                            }
                            "uniqueidentifier" {
                                $subType = "Guid"
                            }
                            default {
                                $subType = "String2"
                            }
                        }

                        $columns += [PSCustomObject]@{
                            Name            = $columnobject.Name
                            ColumnType      = $columnType
                            CharacterString = $( if ($subType -in "String", "String2") { $CharacterString } else { $null } )
                            MinValue        = $minValue
                            MaxValue        = $maxValue
                            MaskingType     = $type
                            SubType         = $subType
                            Format          = $null
                            Separator       = $null
                            Deterministic   = $false
                            Nullable        = $columnobject.Nullable
                            KeepNull        = $true
                            Composite       = $null
                            Action          = $null
                            StaticValue     = $null
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
                        FilterQuery    = $null
                    }
                } else {
                    Write-Message -Message "No columns match for masking in table $($tableobject.Name)" -Level Verbose
                }
            }

            # Check if something needs to be generated
            if ($tables) {
                $maskingconfig += [PSCustomObject]@{
                    Name   = $db.Name
                    Type   = "DataMaskingConfiguration"
                    Tables = $tables
                }
            } else {
                Write-Message -Message "No columns match for masking in table $($tableobject.Name)" -Level Verbose
            }

            # Write the data to the Path
            if ($maskingconfig) {
                Write-Message -Message "Writing masking config" -Level Verbose
                try {
                    $filenamepart = $server.Name.Replace('\', '$').Replace('TCP:', '').Replace(',', '.')
                    $temppath = Join-Path -Path $Path -ChildPath "$($filenamepart).$($db.Name).DataMaskingConfig.json"

                    if (-not $script:isWindows) {
                        $temppath = $temppath.Replace("\", "/")
                    }

                    Set-Content -Path $temppath -Value ($maskingconfig | ConvertTo-Json -Depth 5)
                    Get-ChildItem -Path $temppath
                } catch {
                    Stop-Function -Message "Something went wrong writing the results to the '$Path'" -Target $Path -Continue -ErrorRecord $_
                }
            } else {
                Write-Message -Message "No tables to save for database $($db.Name) on $($server.Name)" -Level Verbose
            }
        }
    }
}