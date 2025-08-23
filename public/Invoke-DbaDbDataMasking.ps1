function Invoke-DbaDbDataMasking {
    <#
    .SYNOPSIS
        Replaces sensitive production data with randomized values using configurable masking rules

    .DESCRIPTION
        Replaces sensitive data in SQL Server databases with randomized values based on a JSON configuration file. This enables DBAs to create safe, non-production datasets for development, testing, and training environments without exposing real customer data.

        The function processes tables row-by-row, applying masking rules like generating fake names, addresses, phone numbers, or random strings while preserving data relationships and referential integrity. It supports deterministic masking to maintain consistency across related records and can handle unique constraints.

        Use New-DbaDbMaskingConfig to generate the required configuration file, which defines which columns to mask and what type of replacement data to generate. The masking process creates temporary tables and indexes to optimize performance during large data transformations.

        Note that the following column and data types are not currently supported:
        Identity
        ForeignKey
        Computed
        Hierarchyid
        Geography
        Geometry
        Xml

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

    .PARAMETER FilePath
        Configuration file that contains the which tables and columns need to be masked

    .PARAMETER Locale
        Set the local to enable certain settings in the masking

    .PARAMETER CharacterString
        The characters to use in string data. 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789' by default

    .PARAMETER ExcludeTable
        Exclude specific tables even if it's listed in the config file.

    .PARAMETER ExcludeColumn
        Exclude specific columns even if it's listed in the config file.

    .PARAMETER MaxValue
        Force a max length of strings instead of relying on datatype maxes. Note if a string datatype has a lower MaxValue, that will be used instead.

        Useful for adhoc updates and testing, otherwise, the config file should be used.

    .PARAMETER ModulusFactor
        Calculating the next nullable by using the remainder from the modulus. Default is every 10.

    .PARAMETER ExactLength
        Mask string values to the same length. So 'Tate' will be replaced with 4 random characters.

    .PARAMETER CommandTimeout
        Timeout for the database connection in seconds. Default is 300.

    .PARAMETER BatchSize
        Size of the batch to use to write the masked data back to the database

    .PARAMETER Retry
        The amount of retries to generate a unique row for a table. Default is 1000.

    .PARAMETER DictionaryFilePath
        Import the dictionary to be used in in the database masking

    .PARAMETER DictionaryExportPath
        Export the dictionary to the given path. Naming convention will be [computername]_[instancename]_[database]_Dictionary.csv

        Be careful with this feature, this export is the key to get the original values which is a security risk!

    .PARAMETER Force
        Forcefully execute commands when needed

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

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
        https://dbatools.io/Invoke-DbaDbDataMasking

    .EXAMPLE
        Invoke-DbaDbDataMasking -SqlInstance SQLDB2 -Database DB1 -FilePath C:\Temp\sqldb1.db1.tables.json

        Apply the data masking configuration from the file "sqldb1.db1.tables.json" to the db1 database on sqldb2. Prompt for confirmation for each table.

    .EXAMPLE
        Get-ChildItem -Path C:\Temp\sqldb1.db1.tables.json | Invoke-DbaDbDataMasking -SqlInstance SQLDB2 -Database DB1 -Confirm:$false

        Apply the data masking configuration from the file "sqldb1.db1.tables.json" to the db1 database on sqldb2. Do not prompt for confirmation.

    .EXAMPLE
        New-DbaDbMaskingConfig -SqlInstance SQLDB1 -Database DB1 -Path C:\Temp\clone -OutVariable file
        $file | Invoke-DbaDbDataMasking -SqlInstance SQLDB2 -Database DB1 -Confirm:$false

        Create the data masking configuration file "sqldb1.db1.tables.json", then use it to mask the db1 database on sqldb2. Do not prompt for confirmation.

    .EXAMPLE
        Get-ChildItem -Path C:\Temp\sqldb1.db1.tables.json | Invoke-DbaDbDataMasking -SqlInstance SQLDB2, sqldb3 -Database DB1 -Confirm:$false

        See what would happen if you the data masking configuration from the file "sqldb1.db1.tables.json" to the db1 database on sqldb2 and sqldb3. Do not prompt for confirmation.
    #>
    [CmdLetBinding(SupportsShouldProcess, ConfirmImpact = "High")]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [parameter(Mandatory, ValueFromPipeline)]
        [Alias('Path', 'FullName')]
        [object]$FilePath,
        [string]$Locale = 'en',
        [string]$CharacterString = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789',
        [string[]]$Table,
        [string[]]$Column,
        [string[]]$ExcludeTable,
        [string[]]$ExcludeColumn,
        [int]$MaxValue,
        [int]$ModulusFactor,
        [switch]$ExactLength,
        [int]$CommandTimeout,
        [int]$BatchSize,
        [int]$Retry,
        [string[]]$DictionaryFilePath,
        [string]$DictionaryExportPath,
        [switch]$EnableException
    )
    begin {
        if ($Force) { $ConfirmPreference = 'none' }

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

        $supportedFakerMaskingTypes = Get-DbaRandomizedType | Select-Object Type -ExpandProperty Type -Unique

        $supportedFakerSubTypes = Get-DbaRandomizedType | Select-Object Subtype -ExpandProperty Subtype -Unique

        $supportedFakerSubTypes += "Date"

        # Set defaults
        if (-not $ModulusFactor) {
            $ModulusFactor = 10
            Write-Message -Level Verbose -Message "Modulus factor set to $ModulusFactor"
        }

        if (-not $CommandTimeout) {
            $CommandTimeout = 300
            Write-Message -Level Verbose -Message "Command time-out set to $CommandTimeout"
        }

        if (-not $BatchSize) {
            $BatchSize = 1000
            Write-Message -Level Verbose -Message "Batch size set to $BatchSize"
        }

        if (-not $Retry) {
            $Retry = 1000
            Write-Message -Level Verbose -Message "Retry count set to $Retry"
        }
    }

    process {
        if (Test-FunctionInterrupt) {
            return
        }

        if ($FilePath.ToString().StartsWith('http')) {
            $tables = Invoke-RestMethod -Uri $FilePath
        } else {
            # Test the configuration file
            try {
                $configErrors = @()

                $configErrors += Test-DbaDbDataMaskingConfig -FilePath $FilePath -EnableException

                if ($configErrors.Count -ge 1) {
                    Stop-Function -Message "Errors found testing the configuration file." -Target $FilePath
                    return $configErrors
                }
            } catch {
                Stop-Function -Message "Something went wrong testing the configuration file" -ErrorRecord $_ -Target $FilePath
                return
            }

            # Get all the items that should be processed
            try {
                $tables = Get-Content -Path $FilePath -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            } catch {
                Stop-Function -Message "Could not parse masking config file" -ErrorRecord $_ -Target $FilePath
                return
            }
        }

        # Test the columns for data types
        foreach ($tabletest in $tables.Tables) {
            if ($Table -and $tabletest.Name -notin $Table) {
                continue
            }

            foreach ($columntest in $tabletest.Columns) {
                if ($columntest.ColumnType -in 'hierarchyid', 'geography', 'xml', 'geometry' -and $columntest.Name -notin $Column) {
                    Stop-Function -Message "$($columntest.ColumnType) is not supported, please remove the column $($columntest.Name) from the $($tabletest.Name) table" -Target $tables -Continue
                }
            }
        }

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            # Check if the deterministic values table is already present
            if ($server.Databases['tempdb'].Tables.Name -contains 'DeterministicValues') {
                Write-Message -Level Verbose -Message "Deterministic values table already exists. Dropping it...."
                $query = "DROP TABLE [dbo].[DeterministicValues];"
                $server.Databases['tempdb'].Query($query)
            }

            # Create the deterministic value table
            $query = "
                CREATE TABLE dbo.DeterministicValues
                (
                    [ValueKey] VARCHAR(900),
                    [NewValue] VARCHAR(900)
                )

                CREATE UNIQUE NONCLUSTERED INDEX UNX__DeterministicValues_ValueKey
                ON dbo.DeterministicValues ( ValueKey )
            "

            $null = $server.Databases['tempdb'].Query($query)

            # Import the dictionary files
            if ($DictionaryFilePath.Count -ge 1) {
                foreach ($file in $DictionaryFilePath) {
                    Write-Message -Level Verbose -Message "Importing dictionary file '$file'"
                    if (Test-Path -Path $file) {
                        try {
                            # Import the keys and values
                            Import-DbaCsv -Path $file -SqlInstance $server -Database tempdb -Schema dbo -Table DeterministicValues
                        } catch {
                            Stop-Function -Message "Could not import csv data from file '$file'" -ErrorRecord $_ -Target $file
                        }
                    } else {
                        Stop-Function -Message "Could not import dictionary file '$file'" -Target $file
                    }
                }
            }

            # Get the database name
            if (-not $Database) {
                $Database = $tables.Name
            }

            # Loop through the databases
            foreach ($dbName in $Database) {
                if ($server.VersionMajor -lt 9) {
                    Stop-Function -Message "SQL Server version must be 2005 or greater" -Continue
                }

                $db = $server.Databases[$($dbName)]

                $nullmod = 0

                #region for each table
                foreach ($tableobject in $tables.Tables) {
                    $elapsed = [System.Diagnostics.Stopwatch]::StartNew()

                    $uniqueDataTableName = $null
                    $uniqueValueColumns = @()
                    $stringBuilder = [System.Text.StringBuilder]''

                    if ($tableobject.Name -in $ExcludeTable) {
                        Write-Message -Level Verbose -Message "Skipping $($tableobject.Name) because it is explicitly excluded"
                        continue
                    }

                    if ($tableobject.Name -notin $db.Tables.Name) {
                        Stop-Function -Message "Table $($tableobject.Name) is not present in $db" -Target $db -Continue
                    }

                    $dbTable = $db.Tables | Where-Object { $_.Schema -eq $tableobject.Schema -and $_.Name -eq $tableobject.Name }

                    [bool]$cleanupIdentityColumn = $false

                    # Make sure there is an identity column present to speed things up
                    if (-not ($dbTable.Columns | Where-Object { $_.Identity -eq $true })) {
                        Write-Message -Level Verbose -Message "Adding identity column to table [$($dbTable.Schema)].[$($dbTable.Name)]"
                        $query = "ALTER TABLE [$($dbTable.Schema)].[$($dbTable.Name)] ADD MaskingID BIGINT IDENTITY(1, 1) NOT NULL;"

                        try {
                            Invoke-DbaQuery -SqlInstance $server -SqlCredential $SqlCredential -Database $db.Name -Query $query
                        } catch {
                            Stop-Function -Message "Could not alter the table to add the masking id" -Target $db -Continue
                        }

                        $cleanupIdentityColumn = $true

                        $identityColumn = "MaskingID"

                        $dbTable.Columns.Refresh()
                    } else {
                        $identityColumn = $dbTable.Columns | Where-Object { $_.Identity } | Select-Object -ExpandProperty Name
                    }

                    # Check if the index for the identity column is already present
                    $maskingIndexName = "NIX__$($dbTable.Schema)_$($dbTable.Name)_Masking"
                    try {
                        if ($dbTable.Indexes.Name -contains $maskingIndexName) {
                            Write-Message -Level Verbose -Message "Masking index already exists in table [$($dbTable.Schema)].[$($dbTable.Name)]. Dropping it..."
                            $dbTable.Indexes[$($maskingIndexName)].Drop()
                        }
                    } catch {
                        Stop-Function -Message "Could not remove identity index to table [$($dbTable.Schema)].[$($dbTable.Name)]" -Continue
                    }

                    # Create the index for the identity column
                    try {
                        Write-Message -Level Verbose -Message "Adding index on identity column [$($identityColumn)] in table [$($dbTable.Schema)].[$($dbTable.Name)]"

                        $query = "CREATE NONCLUSTERED INDEX [$($maskingIndexName)] ON [$($dbTable.Schema)].[$($dbTable.Name)]([$($identityColumn)])"

                        $queryParams = @{
                            SqlInstance   = $server
                            SqlCredential = $SqlCredential
                            Database      = $db.Name
                            Query         = $query
                            QueryTimeout  = $CommandTimeout
                        }

                        Invoke-DbaQuery @queryParams
                    } catch {
                        Stop-Function -Message "Could not add identity index to table [$($dbTable.Schema)].[$($dbTable.Name)]" -Continue
                    }

                    try {
                        if (-not $tableobject.FilterQuery) {
                            # Get all the columns from the table
                            $columnString = "[" + (($dbTable.Columns | Where-Object { $_.DataType -in $supportedDataTypes } | Select-Object Name -ExpandProperty Name) -join "],[") + "]"

                            # Add the identifier column
                            $columnString += ",[$($identityColumn)]"

                            # Put it all together
                            $query = "SELECT $($columnString) FROM [$($tableobject.Schema)].[$($tableobject.Name)]"
                        } else {
                            # Get the query from the table objects
                            $query = ($tableobject.FilterQuery).ToLower()

                            # Check if the query already contains the identifier column
                            if (-not ($query | Select-String -Pattern $identityColumn)) {
                                # Split up the query from the first "from"
                                $queryParts = $query -split "from", 2

                                # Put it all together again with the identifier
                                $query = "$($queryParts[0].Trim()), $($identityColumn) FROM $($queryParts[1].Trim())"
                            }
                        }

                        # Get the data
                        [array]$data = $db.Query($query)
                    } catch {
                        Stop-Function -Message "Failure retrieving the data from table [$($tableobject.Schema)].[$($tableobject.Name)]" -Target $Database -ErrorRecord $_ -Continue
                    }

                    #region unique indexes
                    # Check if the table contains unique indexes
                    if ($tableobject.HasUniqueIndex) {

                        # Loop through the rows and generate a unique value for each row
                        Write-Message -Level Verbose -Message "Generating unique values for [$($tableobject.Schema)].[$($tableobject.Name)]"

                        $params = @{
                            SqlInstance   = $server
                            SqlCredential = $SqlCredential
                            Database      = $db.name
                            Schema        = $tableobject.Schema
                            Table         = $tableobject.Name
                        }

                        $indexToTable = Convert-DbaIndexToTable @params

                        if ($indexToTable) {
                            # compare the index columns to the column in the json table object
                            $compareParams = @{
                                ReferenceObject  = $indexToTable.Columns
                                DifferenceObject = $tableobject.Columns.Name
                                IncludeEqual     = $true
                            }
                            $maskingColumnIndexCount = (Compare-Object @compareParams | Where-Object { $_.SideIndicator -eq "==" }).Count

                            # Check if there is any need to generate unique values
                            if ($maskingColumnIndexCount -ge 1) {

                                # Check if the temporary table already exists
                                $server.Databases['tempdb'].Tables.Refresh()
                                $uniqueDataTableName = $indexToTable.TempTableName

                                if ($server.Databases['tempdb'].Tables.Name -contains $indexToTable.TempTableName) {
                                    Write-Message -Level Verbose -Message "Table '$($indexToTable.TempTableName)' already exists. Dropping it.."
                                    try {
                                        $query = "DROP TABLE $($indexToTable.TempTableName)"
                                        Invoke-DbaQuery -SqlInstance $server -SqlCredential $SqlCredential -Database 'tempdb' -Query $query
                                    } catch {
                                        Stop-Function -Message "Could not drop temporary table"
                                    }
                                }

                                # Create the temporary table
                                try {
                                    Write-Message -Level Verbose -Message "Creating temporary table '$($indexToTable.TempTableName)'"
                                    Invoke-DbaQuery -SqlInstance $server -SqlCredential $SqlCredential -Database 'tempdb' -Query $indexToTable.CreateStatement
                                } catch {
                                    Stop-Function -Message "Could not create temporary table #[$($tableobject.Schema)].[$($tableobject.Name)]"
                                }

                                # Create the unique index table
                                try {
                                    Write-Message -Level Verbose -Message "Creating the unique index for temporary table '$($indexToTable.TempTableName)'"
                                    Invoke-DbaQuery -SqlInstance $server -SqlCredential $SqlCredential -Database 'tempdb' -Query $indexToTable.UniqueIndexStatement
                                } catch {
                                    Stop-Function -Message "Could not create temporary table #[$($tableobject.Schema)].[$($tableobject.Name)]"
                                }

                                # Create a unique row
                                $retryCount = 0
                                for ($i = 0; $i -lt $data.Count; $i++) {
                                    $insertQuery = "INSERT INTO [$($indexToTable.TempTableName)]([$($indexToTable.Columns -join '],[')]) VALUES("
                                    $insertFailed = $false
                                    $insertValues = @()

                                    foreach ($indexColumn in $indexToTable.Columns) {
                                        $columnMaskInfo = $tableobject.Columns | Where-Object { $_.Name -eq $indexColumn }

                                        if ($indexColumn -eq "RowNr") {
                                            $newValue = $i + 1
                                        } elseif ($columnMaskInfo) {
                                            # make sure min is good
                                            if ($columnMaskInfo.MinValue) {
                                                $min = $columnMaskInfo.MinValue
                                            } else {
                                                if ($columnMaskInfo.CharacterString) {
                                                    $min = 1
                                                } else {
                                                    $min = 0
                                                }
                                            }

                                            # make sure max is good
                                            if ($MaxValue) {
                                                if ($columnMaskInfo.MaxValue -le $MaxValue) {
                                                    $max = $columnMaskInfo.MaxValue
                                                } else {
                                                    $max = $MaxValue
                                                }
                                            } else {
                                                $max = $columnMaskInfo.MaxValue
                                            }

                                            if (-not $columnMaskInfo.MaxValue -and -not (Test-Bound -ParameterName MaxValue)) {
                                                $max = 10
                                            }

                                            if ((-not $columnMaskInfo.MinValue -or -not $columnMaskInfo.MaxValue) -and ($columnMaskInfo.ColumnType -match 'date')) {
                                                if (-not $columnMaskInfo.MinValue) {
                                                    $min = (Get-Date).AddDays(-365)
                                                }
                                                if (-not $columnMaskInfo.MaxValue) {
                                                    $max = (Get-Date).AddDays(365)
                                                }
                                            }

                                            if ($columnMaskInfo.CharacterString) {
                                                $charstring = $columnMaskInfo.CharacterString
                                            } else {
                                                $charstring = $CharacterString
                                            }

                                            # Generate a new value
                                            $newValue = $null

                                            $newValueParams = $null

                                            try {
                                                $newValueParams = $null
                                                if (-not $columnobject.SubType -and $columnobject.ColumnType -in $supportedDataTypes) {
                                                    $newValueParams = @{
                                                        DataType = $columnMaskInfo.SubType
                                                        Min      = $columnMaskInfo.MinValue
                                                        Max      = $columnMaskInfo.MaxValue
                                                        Locale   = $Locale
                                                    }
                                                } else {
                                                    $newValueParams = @{
                                                        RandomizerType    = $columnMaskInfo.MaskingType
                                                        RandomizerSubtype = $columnMaskInfo.SubType
                                                        Min               = $min
                                                        Max               = $max
                                                        CharacterString   = $charstring
                                                        Format            = $columnMaskInfo.Format
                                                        Separator         = $columnMaskInfo.Separator
                                                        Locale            = $Locale
                                                    }
                                                }

                                                $newValue = Get-DbaRandomizedValue @newValueParams
                                            } catch {
                                                Stop-Function -Message "Failure" -Target $columnMaskInfo -Continue -ErrorRecord $_
                                            }
                                        } else {
                                            $newValue = $null
                                        }

                                        if ($columnMaskInfo) {
                                            try {
                                                $insertValue = Convert-DbaMaskingValue -Value $newValue -DataType $columnMaskInfo.ColumnType -Nullable:$columnMaskInfo.Nullable -EnableException

                                                if ($convertedValue.ErrorMessage) {
                                                    $maskingErrorFlag = $true
                                                    Stop-Function "Could not convert the value. $($convertedValue.ErrorMessage)" -Target $convertedValue
                                                }
                                            } catch {
                                                Stop-Function -Message "Could not convert value" -ErrorRecord $_ -Target $newValue
                                            }

                                            $insertValues += $insertValue.NewValue
                                        } elseif ($indexColumn -eq "RowNr") {
                                            $insertValues += $newValue
                                        } else {
                                            $insertValues += "NULL"
                                        }

                                        $uniqueValueColumns += $columnMaskInfo.Name
                                    }

                                    # Join all the values to the insert query
                                    $insertQuery += "$($insertValues -join ','));"

                                    # Try inserting the value
                                    try {
                                        $null = $server.Databases['tempdb'].Query($insertQuery)
                                        $insertFailed = $false
                                    } catch {
                                        Write-Message -Level Verbose -Message "Could not insert value"
                                        $insertFailed = $true
                                    }

                                    # Try to insert the value as long it's failed
                                    while ($insertFailed) {
                                        if ($retryCount -eq $Retry) {
                                            Stop-Function -Message "Could not create a unique row after $retryCount tries. Stopping..."
                                            return
                                        }

                                        $insertQuery = "INSERT INTO [$($indexToTable.TempTableName)]([$($indexToTable.Columns -join '],[')]) VALUES("

                                        foreach ($indexColumn in $indexToTable.Columns) {
                                            $columnMaskInfo = $tableobject.Columns | Where-Object { $_.Name -eq $indexColumn }

                                            if ($indexColumn -eq "RowNr") {
                                                $newValue = $i + 1
                                            } elseif ($columnMaskInfo) {
                                                # make sure min is good
                                                if ($columnMaskInfo.MinValue) {
                                                    $min = $columnMaskInfo.MinValue
                                                } else {
                                                    if ($columnMaskInfo.CharacterString) {
                                                        $min = 1
                                                    } else {
                                                        $min = 0
                                                    }
                                                }

                                                # make sure max is good
                                                if ($MaxValue) {
                                                    if ($columnMaskInfo.MaxValue -le $MaxValue) {
                                                        $max = $columnMaskInfo.MaxValue
                                                    } else {
                                                        $max = $MaxValue
                                                    }
                                                } else {
                                                    $max = $columnMaskInfo.MaxValue
                                                }

                                                if (-not $columnMaskInfo.MaxValue -and -not (Test-Bound -ParameterName MaxValue)) {
                                                    $max = 10
                                                }

                                                if ((-not $columnMaskInfo.MinValue -or -not $columnMaskInfo.MaxValue) -and ($columnMaskInfo.ColumnType -match 'date')) {
                                                    if (-not $columnMaskInfo.MinValue) {
                                                        $min = (Get-Date).AddDays(-365)
                                                    }
                                                    if (-not $columnMaskInfo.MaxValue) {
                                                        $max = (Get-Date).AddDays(365)
                                                    }
                                                }

                                                if ($columnMaskInfo.CharacterString) {
                                                    $charstring = $columnMaskInfo.CharacterString
                                                } else {
                                                    $charstring = $CharacterString
                                                }

                                                # Generate a new value
                                                $newValue = $null

                                                $newValueParams = $null

                                                try {
                                                    $newValueParams = $null
                                                    if (-not $columnobject.SubType -and $columnobject.ColumnType -in $supportedDataTypes) {
                                                        $newValueParams = @{
                                                            DataType = $columnMaskInfo.SubType
                                                            Min      = $columnMaskInfo.MinValue
                                                            Max      = $columnMaskInfo.MaxValue
                                                            Locale   = $Locale
                                                        }
                                                    } else {
                                                        $newValueParams = @{
                                                            RandomizerType    = $columnMaskInfo.MaskingType
                                                            RandomizerSubtype = $columnMaskInfo.SubType
                                                            Min               = $min
                                                            Max               = $max
                                                            CharacterString   = $charstring
                                                            Format            = $columnMaskInfo.Format
                                                            Separator         = $columnMaskInfo.Separator
                                                            Locale            = $Locale
                                                        }
                                                    }

                                                    $newValue = Get-DbaRandomizedValue @newValueParams
                                                } catch {
                                                    Stop-Function -Message "Failure" -Target $columnMaskInfo -Continue -ErrorRecord $_
                                                }
                                            } else {
                                                $newValue = $null
                                            }

                                            if ($columnMaskInfo) {
                                                try {
                                                    $insertValue = Convert-DbaMaskingValue -Value $newValue -DataType $columnMaskInfo.ColumnType -Nullable:$columnMaskInfo.Nullable -EnableException

                                                    if ($convertedValue.ErrorMessage) {
                                                        $maskingErrorFlag = $true
                                                        Stop-Function "Could not convert the value. $($convertedValue.ErrorMessage)" -Target $convertedValue
                                                    }
                                                } catch {
                                                    Stop-Function -Message "Could not convert value" -ErrorRecord $_ -Target $newValue
                                                }

                                                $insertValues += $insertValue.NewValue
                                            } elseif ($indexColumn -eq "RowNr") {
                                                $insertValues += $newValue
                                            } else {
                                                $insertValues += "NULL"
                                            }
                                        }

                                        # Join all the values to the insert query
                                        $insertQuery += "$($insertValues -join ','));"

                                        # Try inserting the value
                                        try {
                                            $null = $server.Databases['tempdb'].Query($insertQuery)
                                            $insertFailed = $false
                                        } catch {
                                            Write-Message -Level Verbose -Message "Could not insert value"
                                            $insertFailed = $true
                                            $retryCount++
                                        }
                                    }
                                }

                                try {
                                    Write-Message -Level Verbose -Message "Creating masking index for [$($indexToTable.TempTableName)]"
                                    $query = "CREATE NONCLUSTERED INDEX [NIX_$($indexToTable.TempTableName)_MaskID] ON [$($indexToTable.TempTableName)]([RowNr])"
                                    $null = $server.Databases['tempdb'].Query($query)
                                } catch {
                                    Stop-Function -Message "Could not add masking index for [$($indexToTable.TempTableName)]" -ErrorRecord $_
                                }
                            } else {
                                Write-Message -Level Verbose -Message "Table [$($tableobject.Schema)].[$($tableobject.Name)] does not contain any masking index columns to process"
                            }
                        } else {
                            Stop-Function -Message "The table does not have any indexes"
                        }
                    }

                    #endregion unique indexes

                    $tablecolumns = $tableobject.Columns

                    if ($Column) {
                        $tablecolumns = $tablecolumns | Where-Object { $_.Name -in $Column }
                    }

                    if ($ExcludeColumn) {
                        if ([string]$uniqueIndex.Columns -match ($ExcludeColumn -join "|")) {
                            Stop-Function -Message "Column present in -ExcludeColumn cannot be excluded because it's part of an unique index" -Target $ExcludeColumn -Continue
                        }

                        $tablecolumns = $tablecolumns | Where-Object { $_.Name -notin $ExcludeColumn }
                    }

                    if (-not $tablecolumns) {
                        Write-Message -Level Verbose "No columns to process in [$($dbName)].[$($tableobject.Schema)].[$($tableobject.Name)], moving on"
                        continue
                    }

                    # Figure out if the columns has actions
                    $columnsWithActions = @()
                    $columnsWithActions += $tableobject.Columns | Where-Object { $null -ne $_.Action }

                    # Figure out if the columns has composites
                    $columnsWithComposites = @()
                    $columnsWithComposites += $tableobject.Columns | Where-Object { $null -ne $_.Composite }

                    # Check for both special actions
                    if (($columnsWithComposites.Count -ge 1) -and ($columnsWithActions.Count -ge 1)) {
                        Stop-Function -Message "You cannot use both composites and actions"
                    }

                    # Filter out columns with actions or composites for separate processing
                    $standardColumns = $tablecolumns | Where-Object {
                        ($_.Name -notin $columnsWithActions.Name) -and
                        ($_.Name -notin $columnsWithComposites.Name)
                    }

                    if ($Pscmdlet.ShouldProcess($instance, "Masking $($data.Count) row(s) for column [$($tablecolumns.Name -join ', ')] in $($dbName).$($tableobject.Schema).$($tableobject.Name)")) {
                        $totalBatches = [System.Math]::Ceiling($data.Count / $BatchSize)
                        [bool]$maskingErrorFlag = $false

                        # OPTIMIZED SECTION: Process rows in batches, updating all columns for each row at once
                        $batchNr = 0
                        $batchRowNr = 0
                        $rowNumber = 0

                        # Process rows in batches
                        for ($rowIndex = 0; $rowIndex -lt $data.Count; $rowIndex++) {
                            $row = $data[$rowIndex]
                            $rowNumber++
                            $batchRowNr++

                            if ((($batchRowNr - 1) % 100) -eq 0) {
                                $progressParams = @{
                                    StepNumber = $batchNr
                                    TotalSteps = $totalBatches
                                    Activity   = "Masking $($data.Count) rows in $($tableobject.Schema).$($tableobject.Name) in $($dbName) on $instance"
                                    Message    = "Generating Updates"
                                }

                                Write-ProgressHelper @progressParams
                            }

                            # Create array to hold all column updates for this row
                            $updates = @()

                            # Process all standard columns for this row
                            foreach ($columnobject in $standardColumns) {
                                $newValue = $null

                                # Handle static values
                                if ($columnobject.StaticValue) {
                                    $newValue = $columnobject.StaticValue

                                    if ($null -eq $newValue -and -not $columnobject.Nullable) {
                                        Write-Message -Message "Column '$($columnobject.Name)' static value cannot be null when column is set not to be nullable." -Level Warning
                                        continue
                                    }
                                }
                                # Check for various conditions to determine the new value
                                elseif ($columnobject.KeepNull -and $columnobject.Nullable -and
                                    (($row.($columnobject.Name)).GetType().Name -eq 'DBNull') -or
                                    ($row.($columnobject.Name) -eq '')) {
                                    $newValue = $null
                                } elseif (-not $columnobject.KeepNull -and $columnobject.Nullable -and
                                    (($nullmod++) % $ModulusFactor -eq 0)) {
                                    $newValue = $null
                                } elseif ($tableobject.HasUniqueIndex -and $columnobject.Name -in $uniqueValueColumns) {
                                    # Get value from unique data table
                                    $query = "SELECT $($columnobject.Name) FROM $($uniqueDataTableName) WHERE [RowNr] = $rowNumber"

                                    try {
                                        $uniqueData = Invoke-DbaQuery -SqlInstance $server -SqlCredential $SqlCredential -Database tempdb -Query $query
                                    } catch {
                                        Stop-Function -Message "Something went wrong getting the unique data" -Target $query -ErrorRecord $_ -continue
                                    }

                                    if ($null -eq $uniqueData) {
                                        Stop-Function -Message "Could not find any unique values" -Target $tableobject
                                        return
                                    }

                                    $newValue = $uniqueData.$($columnobject.Name)
                                } elseif ($columnobject.Deterministic) {
                                    # Check for deterministic value
                                    if (($null -ne $row.($columnobject.Name)) -and ($row.($columnobject.Name) -ne '')) {
                                        try {
                                            $lookupValue = Convert-DbaMaskingValue -Value $row.($columnobject.Name) -DataType varchar -Nullable:$columnobject.Nullable -EnableException

                                            if ($convertedValue.ErrorMessage) {
                                                $maskingErrorFlag = $true
                                                Stop-Function "Could not convert the value. $($convertedValue.ErrorMessage)" -Target $convertedValue -continue
                                            }
                                        } catch {
                                            Stop-Function -Message "Could not convert value" -ErrorRecord $_ -Target $row.($columnobject.Name) -continue
                                        }

                                        $query = "SELECT [NewValue] FROM dbo.DeterministicValues WHERE [ValueKey] = $($lookupValue.NewValue)"

                                        try {
                                            $lookupResult = $null
                                            $lookupResult = $server.Databases['tempdb'].Query($query)

                                            if ($lookupResult.NewValue) {
                                                $newValue = $lookupResult.NewValue
                                                # Skip further processing for this column
                                                continue
                                            }
                                        } catch {
                                            Stop-Function -Message "Something went wrong retrieving the deterministic values" -Target $query -ErrorRecord $_ -continue
                                        }
                                    }
                                }

                                # If we haven't determined a value yet, generate one
                                if ($null -eq $newValue -and -not $columnobject.StaticValue) {
                                    # make sure min is good
                                    if ($columnobject.MinValue) {
                                        $min = $columnobject.MinValue
                                    } else {
                                        if ($columnobject.CharacterString) {
                                            $min = 1
                                        } else {
                                            $min = 0
                                        }
                                    }

                                    # make sure max is good
                                    if ($MaxValue) {
                                        if ($columnobject.MaxValue -le $MaxValue) {
                                            $max = $columnobject.MaxValue
                                        } else {
                                            $max = $MaxValue
                                        }
                                    } else {
                                        $max = $columnobject.MaxValue
                                    }

                                    if (-not $columnobject.MaxValue -and -not (Test-Bound -ParameterName MaxValue)) {
                                        $max = 10
                                    }

                                    if ((-not $columnobject.MinValue -or -not $columnobject.MaxValue) -and ($columnobject.ColumnType -match 'date')) {
                                        if (-not $columnobject.MinValue) {
                                            $min = (Get-Date).AddDays(-365)
                                        }
                                        if (-not $columnobject.MaxValue) {
                                            $max = (Get-Date).AddDays(365)
                                        }
                                    }

                                    if ($columnobject.CharacterString) {
                                        $charstring = $columnobject.CharacterString
                                    } else {
                                        $charstring = $CharacterString
                                    }

                                    # Setup the new value parameters
                                    $newValueParams = $null

                                    if ($null -eq $columnobject.SubType) {
                                        $newValueParams = @{
                                            DataType        = $columnobject.ColumnType
                                            Min             = $min
                                            Max             = $max
                                            CharacterString = $charstring
                                            Format          = $columnobject.Format
                                            Locale          = $Locale
                                        }
                                    } elseif ($columnobject.SubType.ToLowerInvariant() -in 'shuffle', 'string2', 'string') {
                                        if ($columnobject.ColumnType -in 'bigint', 'char', 'int', 'nchar', 'nvarchar', 'smallint', 'tinyint', 'varchar') {
                                            $newValueParams = @{
                                                RandomizerType    = "Random"
                                                RandomizerSubtype = "Shuffle"
                                                Value             = ($row.$($columnobject.Name))
                                                Locale            = $Locale
                                            }
                                        } elseif ($columnobject.ColumnType -in 'decimal', 'numeric', 'float', 'money', 'smallmoney', 'real') {
                                            $newValueParams = @{
                                                RandomizerType    = "Random"
                                                RandomizerSubtype = "Shuffle"
                                                Value             = ($row.$($columnobject.Name))
                                                Locale            = $Locale
                                            }
                                        }
                                    } else {
                                        $newValueParams = @{
                                            RandomizerType    = $columnobject.MaskingType
                                            RandomizerSubtype = $columnobject.SubType
                                            Min               = $min
                                            Max               = $max
                                            CharacterString   = $charstring
                                            Format            = $columnobject.Format
                                            Separator         = $columnobject.Separator
                                            Locale            = $Locale
                                        }
                                    }

                                    # Generate the new value
                                    try {
                                        $newValue = Get-DbaRandomizedValue @newValueParams
                                    } catch {
                                        $maskingErrorFlag = $true
                                        Stop-Function -Message "Failure" -Target $columnobject -Continue -ErrorRecord $_
                                    }
                                }

                                # Convert the value for SQL
                                try {
                                    if ($row.($columnobject.Name) -eq '' -and $columnobject.ColumnType -in 'decimal') {
                                        $newvalue = "0.00"
                                    }
                                    $convertedValue = Convert-DbaMaskingValue -Value $newValue -DataType $columnobject.ColumnType -Nullable:$columnobject.Nullable -EnableException

                                    if ($convertedValue.ErrorMessage) {
                                        $maskingErrorFlag = $true
                                        Stop-Function "Could not convert the value. $($convertedValue.ErrorMessage)" -Target $convertedValue -continue
                                    }
                                } catch {
                                    Stop-Function -Message "Could not convert value" -ErrorRecord $_ -Target $newValue -continue
                                }

                                # Add to the updates
                                $updates += "[$($columnobject.Name)] = $($convertedValue.NewValue)"

                                # Handle deterministic values storage
                                if ($columnobject.Deterministic -and ($null -ne $row.($columnobject.Name)) -and
                                    ($row.($columnobject.Name) -ne '') -and ($null -eq $lookupResult.NewValue)) {
                                    try {
                                        $previous = Convert-DbaMaskingValue -Value $row.($columnobject.Name) -DataType $columnobject.ColumnType -Nullable:$columnobject.Nullable -EnableException

                                        if ($convertedValue.ErrorMessage) {
                                            $maskingErrorFlag = $true
                                            Stop-Function "Could not convert the value. $($convertedValue.ErrorMessage)" -Target $convertedValue
                                            continue
                                        }

                                        $query = "INSERT INTO dbo.DeterministicValues (ValueKey, NewValue) VALUES ($($previous.NewValue), $($convertedValue.NewValue));"
                                        $null = $server.Databases['tempdb'].Query($query)
                                    } catch {
                                        Stop-Function -Message "Could not save deterministic value.`n$_" -Target $query -ErrorRecord $_
                                        continue
                                    }
                                }
                            }

                            # Only create an update if we have columns to update
                            if ($updates.Count -gt 0) {
                                # Create one UPDATE statement for all columns in this row
                                $updateQuery = "UPDATE [$($tableobject.Schema)].[$($tableobject.Name)] SET $($updates -join ', ') WHERE [$($identityColumn)] = $($row.$($identityColumn)); "
                                $null = $stringBuilder.AppendLine($updateQuery)
                            }

                            # If we've reached the batch size or this is the last row, execute the batch
                            if ($batchRowNr -eq $BatchSize -or $rowIndex -eq ($data.Count - 1)) {
                                # Increase the batch counter
                                $batchNr++

                                # Execute the batch if we have updates
                                if ($stringBuilder.Length -gt 0) {
                                    try {
                                        $progressParams = @{
                                            StepNumber = $batchNr
                                            TotalSteps = $totalBatches
                                            Activity   = "Masking $($data.Count) rows in $($tableobject.Schema).$($tableobject.Name) in $($dbName) on $instance"
                                            Message    = "Executing Batch $batchNr/$totalBatches"
                                        }

                                        Write-ProgressHelper @progressParams

                                        Write-Message -Level Verbose -Message "Executing batch $batchNr/$totalBatches"

                                        $queryParams = @{
                                            SqlInstance     = $instance
                                            SqlCredential   = $SqlCredential
                                            Database        = $db.Name
                                            Query           = $stringBuilder.ToString()
                                            EnableException = $EnableException
                                            QueryTimeout    = $CommandTimeout
                                        }

                                        Invoke-DbaQuery @queryParams
                                    } catch {
                                        $maskingErrorFlag = $true
                                        Stop-Function -Message "Error updating $($tableobject.Schema).$($tableobject.Name): $_ `n$($stringBuilder.ToString())" -Target $stringBuilder.ToString() -Continue -ErrorRecord $_
                                    }

                                    # Clear the string builder for the next batch
                                    $null = $stringBuilder.Clear()
                                }

                                # Reset batch row counter
                                $batchRowNr = 0
                            }
                        }

                        # Process Actions separately
                        if ($columnsWithActions.Count -ge 1) {
                            foreach ($columnObject in $columnsWithActions) {
                                Write-Message -Level Verbose -Message "Processing action for [$($columnObject.Name)]"

                                [bool]$validAction = $true
                                $columnAction = $columnobject.Action
                                $query = "UPDATE [$($tableobject.Schema)].[$($tableobject.Name)] SET [$($columnObject.Name)] = "



                                if ($columnAction.Category -eq 'DateTime') {
                                    switch ($columnAction.Type) {
                                        "Add" {
                                            $query += "DATEADD($($columnAction.SubCategory), $($columnAction.Value), [$($columnObject.Name)]);"
                                        }
                                        "Subtract" {
                                            $query += "DATEADD($($columnAction.SubCategory), - $($columnAction.Value), [$($columnObject.Name)]);"
                                        }
                                        default {
                                            $validAction = $false
                                        }
                                    }
                                } elseif ($columnAction.Category -eq 'Number') {
                                    switch ($columnAction.Type) {
                                        "Add" {
                                            $query += "[$($columnObject.Name)] + $($columnAction.Value);"
                                        }
                                        "Divide" {
                                            $query += "[$($columnObject.Name)] / $($columnAction.Value);"
                                        }
                                        "Multiply" {
                                            $query += "[$($columnObject.Name)] * $($columnAction.Value);"
                                        }
                                        "Subtract" {
                                            $query += "[$($columnObject.Name)] - $($columnAction.Value);"
                                        }
                                        default {
                                            $validAction = $false
                                        }
                                    }
                                } elseif ($columnAction.Category -eq 'Column') {
                                    switch ($columnAction.Type) {
                                        "Set" {
                                            if ($columnobject.ColumnType -like '*int*' -or $columnobject.ColumnType -in 'bit', 'bool', 'decimal', 'numeric', 'float', 'money', 'smallmoney', 'real') {
                                                $query += "$($columnAction.Value)"
                                            } elseif ($columnobject.ColumnType -in '*date*', 'time', 'uniqueidentifier') {
                                                $query += "'$($columnAction.Value)'"
                                            } else {
                                                $query += "'$($columnAction.Value)'"
                                            }
                                        }
                                        "Nullify" {
                                            if ($columnobject.Nullable) {
                                                $query += "NULL"
                                            } else {
                                                $validAction = $false
                                            }
                                        }
                                        default {
                                            $validAction = $false
                                        }
                                    }
                                }
                                # Add the query to the rest
                                if ($validAction) {
                                    $null = $stringBuilder.AppendLine($query)
                                }
                            }

                            try {
                                if ($stringBuilder.Length -ge 1) {
                                    Invoke-DbaQuery -SqlInstance $instance -SqlCredential $SqlCredential -Database $db.Name -Query $stringBuilder.ToString() -EnableException
                                }
                            } catch {
                                $stringBuilder.ToString()
                                Stop-Function -Message "Error updating $($tableobject.Schema).$($tableobject.Name): $_" -Target $stringBuilder -Continue -ErrorRecord $_
                            }

                            $null = $stringBuilder.Clear()
                        }

                        # Process Composites separately
                        if ($columnsWithComposites.Count -ge 1) {
                            foreach ($columnObject in $columnsWithComposites) {
                                Write-Message -Level Verbose -Message "Processing composite for [$($columnObject.Name)]"

                                $compositeItems = @()

                                foreach ($columnComposite in $columnObject.Composite) {
                                    if ($columnComposite.Type -eq 'Column') {
                                        $compositeItems += "[$($columnComposite.Value)]"
                                    } elseif ($columnComposite.Type -eq 'Static') {
                                        $compositeItems += "'$($columnComposite.Value)'"
                                    } elseif ($columnComposite.Type -in $supportedFakerMaskingTypes) {
                                        try {
                                            $newValue = $null

                                            if ($columnobject.SubType -in $supportedDataTypes) {
                                                $newValueParams = @{
                                                    DataType        = $columnobject.SubType
                                                    CharacterString = $charstring
                                                    Min             = $columnComposite.Min
                                                    Max             = $columnComposite.Max
                                                    Locale          = $Locale
                                                }

                                                $newValue = Get-DbaRandomizedValue @newValueParams
                                            } else {
                                                $newValueParams = @{
                                                    RandomizerType    = $columnobject.MaskingType
                                                    RandomizerSubtype = $columnobject.SubType
                                                    Min               = $min
                                                    Max               = $max
                                                    CharacterString   = $charstring
                                                    Format            = $columnobject.Format
                                                    Separator         = $columnobject.Separator
                                                    Locale            = $Locale
                                                }

                                                $newValue = Get-DbaRandomizedValue @newValueParams
                                            }
                                        } catch {
                                            Stop-Function -Message "Failure" -Target $faker -Continue -ErrorRecord $_
                                        }

                                        if ($columnobject.ColumnType -match 'int') {
                                            $compositeItems += " $newValue"
                                        } elseif ($columnobject.ColumnType -in 'bit', 'bool') {
                                            if ($columnValue) {
                                                $compositeItems += "1"
                                            } else {
                                                $compositeItems += "0"
                                            }
                                        } else {
                                            $newValue = ($newValue).Tostring().Replace("'", "''")
                                            $compositeItems += "'$newValue'"
                                        }
                                    } else {
                                        $compositeItems += ""
                                    }
                                }

                                $compositeItemsUpdated = $compositeItems | ForEach-Object { $_ = "ISNULL($($_), '')"; $_ }

                                $null = $stringBuilder.AppendLine("UPDATE [$($tableobject.Schema)].[$($tableobject.Name)] SET [$($columnObject.Name)] = $($compositeItemsUpdated -join ' + ')")
                            }

                            try {
                                $stringBuilder.ToString()
                                Invoke-DbaQuery -SqlInstance $instance -SqlCredential $SqlCredential -Database $db.Name -Query $stringBuilder.ToString() -EnableException
                            } catch {
                                Stop-Function -Message "Error updating $($tableobject.Schema).$($tableobject.Name): $_" -Target $stringBuilder -Continue -ErrorRecord $_
                            }

                            $null = $stringBuilder.Clear()
                        }

                        # Clean up the masking index
                        try {
                            # Refresh the indexes to make sure to have the latest list
                            $dbTable.Indexes.Refresh()

                            # Check if the index is there
                            if ($dbTable.Indexes.Name -contains $maskingIndexName) {
                                Write-Message -Level verbose -Message "Removing identity index from table [$($dbTable.Schema)].[$($dbTable.Name)]"
                                $dbTable.Indexes[$($maskingIndexName)].Drop()
                            }
                        } catch {
                            Stop-Function -Message "Could not remove identity index from table [$($dbTable.Schema)].[$($dbTable.Name)]" -Continue
                        }

                        # Clean up the identity column
                        if ($cleanupIdentityColumn) {
                            try {
                                Write-Message -Level Verbose -Message "Removing identity column [$($identityColumn)] from table [$($dbTable.Schema)].[$($dbTable.Name)]"

                                $query = "ALTER TABLE [$($dbTable.Schema)].[$($dbTable.Name)] DROP COLUMN [$($identityColumn)]"

                                Invoke-DbaQuery -SqlInstance $instance -SqlCredential $SqlCredential -Database $db.Name -Query $query -EnableException
                            } catch {
                                Stop-Function -Message "Could not remove identity column from table [$($dbTable.Schema)].[$($dbTable.Name)]" -Continue
                            }
                        }

                        # Return the masking results
                        if ($maskingErrorFlag) {
                            $maskingStatus = "Failed"
                        } else {
                            $maskingStatus = "Successful"
                        }

                        [PSCustomObject]@{
                            ComputerName = $db.Parent.ComputerName
                            InstanceName = $db.Parent.ServiceName
                            SqlInstance  = $db.Parent.DomainInstanceName
                            Database     = $dbName
                            Schema       = $tableobject.Schema
                            Table        = $tableobject.Name
                            Columns      = $tableobject.Columns.Name
                            Rows         = $($data.Count)
                            Elapsed      = [prettytimespan]$elapsed.Elapsed
                            Status       = $maskingStatus
                        }


                        # Reset time
                        $null = $elapsed.Reset()
                    }

                    # Cleanup
                    if ($uniqueDataTableName) {
                        Write-Message -Message "Cleaning up unique temporary table '$uniqueDataTableName'" -Level verbose
                        $query = "DROP TABLE [$($uniqueDataTableName)];"
                        try {
                            $null = Invoke-DbaQuery -SqlInstance $server -SqlCredential $SqlCredential -Database 'tempdb' -Query $query -EnableException
                        } catch {
                            Stop-Function -Message "Could not clean up unique values table '$uniqueDataTableName'" -Target $uniqueDataTableName -ErrorRecord $_
                        }
                    }
                }
                #endregion for each table

                # Export the dictionary when needed
                if ($DictionaryExportPath) {
                    try {
                        # Handle dictionary
                        $query = "SELECT [ValueKey], [NewValue] FROM dbo.DeterministicValues"
                        [array]$dictResult = $server.Databases['tempdb'].Query($query)

                        if ($dictResult.Count -ge 1) {
                            Write-Message -Message "Writing dictionary for $($db.Name)" -Level Verbose

                            # Check if the output directory already exists
                            if (-not (Test-Path -Path $DictionaryExportPath)) {
                                $null = New-Item -Path $DictionaryExportPath -ItemType Directory
                            }

                            # Of course with Linux we need to change the slashes
                            if (-not $script:isWindows) {
                                $dictionaryFileName = $dictionaryFileName.Replace("\", "/")
                            }

                            # Setup the file paths
                            $filenamepart = $server.Name.Replace('\', '$').Replace('TCP:', '').Replace(',', '.')
                            $dictionaryFileName = "$DictionaryExportPath\$($filenamepart).$($db.Name).Dictionary.csv"

                            # Export dictionary
                            $null = $dictResult | Export-Csv -Path $dictionaryFileName -NoTypeInformation

                            Get-ChildItem -Path $dictionaryFileName
                        } else {
                            Write-Message -Level Verbose -Message "No values to export as a dictionary"
                        }
                    } catch {
                        Stop-Function -Message "Something went wrong writing the dictionary to the $DictionaryExportPath" -Target $DictionaryExportPath -Continue -ErrorRecord $_
                    }
                }
            } # End foreach database

            # Do some cleanup
            $null = $server.Databases['tempdb'].Tables.Refresh()

            if ($server.Databases['tempdb'].Tables.Name -contains 'DeterministicValues') {
                $query = "DROP TABLE dbo.DeterministicValues"

                try {
                    Write-Message -Level Verbose -Message "Cleaning up deterministic values table"
                    $null = $server.Databases['tempdb'].Query($query)
                } catch {
                    Stop-Function -Message "Could not remove deterministic value table" -ErrorRecord $_
                }
            }

        } # End foreach instance
    } # End process block
} # End