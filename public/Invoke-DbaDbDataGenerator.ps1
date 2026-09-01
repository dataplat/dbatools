function Invoke-DbaDbDataGenerator {
    <#
    .SYNOPSIS
        Generates realistic test data for SQL Server database tables using configuration-driven rules

    .DESCRIPTION
        Populates database tables with randomly generated but realistic test data based on JSON configuration files. Uses the Bogus library to create fake but believable data like names, addresses, phone numbers, and dates that respect column constraints and data types. Perfect for creating development environments, testing scenarios, or demo databases without using production data. Handles identity columns, unique indexes, nullable fields, and foreign key relationships while maintaining data integrity.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies which databases to generate data for. If not provided, uses database names from the configuration file.
        Use this to limit data generation to specific databases when your config file covers multiple databases.

    .PARAMETER Table
        Limits data generation to specific tables only, overriding the full table list in the configuration file.
        Useful when you need to populate just certain tables for testing or during incremental development work.

    .PARAMETER Column
        Restricts data generation to specific columns within the processed tables.
        Use this to generate data for only certain columns during testing or when troubleshooting specific column configurations.

    .PARAMETER FilePath
        Path to the JSON configuration file that defines data generation rules for tables and columns. Accepts local file paths or HTTP URLs.
        This file specifies which tables to populate, how many rows to generate, and the data generation rules for each column.

    .PARAMETER Locale
        Sets the locale for generating culture-specific fake data like names, addresses, and phone numbers. Defaults to 'en' for English.
        Change this when you need realistic data for specific regions, such as 'de' for German or 'fr' for French test data.

    .PARAMETER CharacterString
        Defines the character set used for generating random string values. Defaults to alphanumeric characters.
        Customize this when you need specific character patterns for testing, such as restricting to only uppercase letters or including special characters.

    .PARAMETER ExcludeTable
        Skips specific tables even if they're included in the configuration file.
        Use this to temporarily exclude problematic tables during testing or when you want to process most tables but skip a few.

    .PARAMETER ExcludeColumn
        Skips specific columns even if they're included in the configuration file.
        Helpful when troubleshooting column-specific issues or when you want to exclude sensitive columns temporarily.

    .PARAMETER MaxValue
        Overrides the maximum length for string columns, ignoring the data type's natural limits. Lower data type limits still take precedence.
        Useful for testing with shorter strings or when you need consistent string lengths across different environments.

    .PARAMETER ExactLength
        Forces generated strings to match the exact length of existing data in the column.
        Use this when you need to preserve string length patterns for testing applications that expect specific data formats.

    .PARAMETER ModulusFactor
        Controls how frequently nullable columns receive NULL values by using modulus calculation. Default is every 10th row gets NULL.
        Adjust this to increase or decrease NULL frequency in your test data to match realistic data distribution patterns.

    .PARAMETER Force
        Bypasses confirmation prompts and executes data generation without user interaction.
        Use this in automated scripts or when you're confident about the data generation configuration and want to run unattended.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.


    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: DataGeneration
        Author: Sander Stad (@sqlstad, sqlstad.nl)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Invoke-DbaDbDataGenerator

    .OUTPUTS
        PSCustomObject

        Returns one object per table that had data generated, providing a summary of the data generation operation.

        Properties:
        - ComputerName: The name of the computer hosting the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance format)
        - Database: The name of the database where data was generated
        - Schema: The schema name containing the table
        - Table: The name of the table that was populated with generated data
        - Columns: Array of column names that received generated data
        - Rows: Integer count of rows generated and inserted into the table
        - Elapsed: TimeSpan of the time taken to generate and insert data (formatted as prettytimespan for display)
        - Status: String indicating the result of the operation - "Done" for successful completion

    .EXAMPLE
        Invoke-DbaDbDataGenerator -SqlInstance sqldb2 -Database DB1 -FilePath C:\temp\sqldb1.db1.tables.json

        Apply the data generation configuration from the file "sqldb1.db1.tables.json" to the db1 database on sqldb2. Prompt for confirmation for each table.

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
        [switch]$ExactLength,
        [int]$ModulusFactor = 10,
        [switch]$EnableException
    )

    begin {
        if ($Force) { $ConfirmPreference = 'none' }

        # Create the faker objects
        try {
            $script:faker = New-Object Bogus.Faker($Locale)
        } catch {
            Stop-Function -Message "Could not load randomizer class" -Continue
        }

        # This list has to match the one in Test-DbaDbDataGeneratorConfig, because a configuration is
        # rejected up front on every finding reported there.
        $supportedDataTypes = "bigint", "bit", "bool", "char", "date", "datetime", "datetime2", "decimal", "int", "float", "guid", "money", "numeric", "nchar", "ntext", "nvarchar", "real", "smalldatetime", "smallint", "text", "time", "tinyint", "uniqueidentifier", "userdefineddatatype", "varchar"
        # This list decides which configurations we accept, so it has to predict what Get-DbaRandomizedValue
        # will accept further down. That command validates its input against the randomizer types, so we use
        # the same list here. Reflecting over a Bogus.Faker object instead offered subtypes that
        # Get-DbaRandomizedValue then rejected, hid every subtype that Bogus exposes as a property rather than
        # a method, like Person.DateOfBirth, and broke whenever a new property was added or was null, as
        # DateTimeReference is by design (see https://github.com/bchavez/Bogus/issues/612).
        # The whole combination is kept, not two separate lists of types and subtypes, because only the
        # combinations that appear together are valid.
        $supportedRandomizerTypes = Get-DbaRandomizedType
        #$foreignKeyQuery = Get-Content -Path "$script:PSModuleRoot\bin\datageneration\ForeignKeyHierarchy.sql"
    }

    process {
        if (Test-FunctionInterrupt) { return }

        if ($FilePath.ToString().StartsWith('http')) {
            $tables = Invoke-RestMethod -Uri $FilePath
        } else {
            # Check if the destination is accessible
            if (-not (Test-Path -Path $FilePath)) {
                Stop-Function -Message "Could not find data generation config file $FilePath" -Target $FilePath
                return
            }

            # Test the configuration
            try {
                $configErrors = @()

                # The findings are output objects, not exceptions, so they have to be collected and
                # acted on. Left unassigned they went to the output stream and the generation ran on
                # an invalid configuration.
                $configErrors += Test-DbaDbDataGeneratorConfig -FilePath $FilePath -EnableException

                if ($configErrors.Count -ge 1) {
                    Stop-Function -Message "Errors found testing the configuration file." -Target $FilePath
                    return $configErrors
                }
            } catch {
                Stop-Function -Message "Errors found testing the configuration file. `n$_" -ErrorRecord $_ -Target $FilePath
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

        foreach ($tabletest in $tables.Tables) {
            if ($Table -and $tabletest.Name -notin $Table) {
                continue
            }
            foreach ($columntest in $tabletest.Columns) {
                if ($columntest.ColumnType -in 'hierarchyid', 'geography', 'xml', 'geometry' -and $columntest.Name -notin $Column) {
                    Stop-Function -Message "$($columntest.ColumnType) is not supported, please remove the column $($columntest.Name) from the $($tabletest.Name) table" -Target $tables
                }
            }
        }

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if ($Database) {
                $dbs = Get-DbaDatabase -SqlInstance $server -Database $Database
            } else {
                $dbs = Get-DbaDatabase -SqlInstance $server -Database $tables.Name
            }

            $sqlconn = $server.ConnectionContext.SqlConnectionObject.PsObject.Copy()
            $sqlconn.Open()

            foreach ($db in $dbs) {
                $stepcounter = $nullmod = 0

                #$foreignKeys = Invoke-DbaQuery -SqlInstance $instance -SqlCredential $SqlCredential -Database $db -Query $foreignKeyQuery

                foreach ($tableobject in $tables.Tables) {

                    if ($tableobject.Name -in $ExcludeTable -or ($Table -and $tableobject.Name -notin $Table)) {
                        Write-Message -Level Verbose -Message "Skipping $($tableobject.Name) because it is explicitly excluded"
                        continue
                    }

                    if ($tableobject.Name -notin $db.Tables.Name) {
                        Stop-Function -Message "Table $($tableobject.Name) is not present in $db" -Target $db -Continue
                    }

                    $tablecolumns = $tableobject.Columns

                    if ($Column) {
                        $tablecolumns = $tablecolumns | Where-Object Name -in $Column
                    }

                    if ($ExcludeColumn) {
                        $tablecolumns = $tablecolumns | Where-Object Name -notin $ExcludeColumn
                    }

                    if (-not $tablecolumns) {
                        Write-Message -Level Verbose "No columns to process in $($db.Name).$($tableobject.Schema).$($tableobject.Name), moving on"
                        continue
                    }

                    # Everything about the columns is checked here, before a single value is generated. The
                    # insert statement names every column of the table, so skipping one further down left the
                    # statement with fewer values than columns and SQL Server answered with a syntax error that
                    # says nothing about the configuration behind it. The unique index values below are
                    # generated before that statement is built, so this has to come first or an unusable column
                    # is invoked anyway. The whole table is skipped, because half a row is not useful either.
                    $unsupportedColumns = @()
                    foreach ($columnobject in $tablecolumns) {
                        # The type and the subtype have to be a combination that exists. Checking them against
                        # two independent lists accepted Name/ZipCode, because Name is a type somewhere and
                        # ZipCode is a subtype somewhere, and the generating failed later on.
                        $randomizerCombination = $supportedRandomizerTypes | Where-Object { $PSItem.Type -eq $columnobject.MaskingType -and $PSItem.SubType -eq $columnobject.SubType }

                        if ($columnobject.ColumnType -notin $supportedDataTypes) {
                            Write-Message -Level Warning -Message "Unsupported data type `"$($columnobject.ColumnType)`" for column $($columnobject.Name)"
                            $unsupportedColumns += $columnobject.Name
                        } elseif ($columnobject.MaskingType -notin $supportedRandomizerTypes.Type) {
                            Write-Message -Level Warning -Message "Unsupported masking type `"$($columnobject.MaskingType)`" for column $($columnobject.Name)"
                            $unsupportedColumns += $columnobject.Name
                        } elseif (-not $randomizerCombination) {
                            Write-Message -Level Warning -Message "Unsupported masking sub type `"$($columnobject.SubType)`" for masking type `"$($columnobject.MaskingType)`" for column $($columnobject.Name)"
                            $unsupportedColumns += $columnobject.Name
                        } elseif ($randomizerCombination.RequiredParameter) {
                            # A data generation configuration has nowhere to put a Format or a Value, so these
                            # combinations can be used with Get-DbaRandomizedValue but never from here.
                            Write-Message -Level Warning -Message "Masking sub type `"$($columnobject.SubType)`" needs a $($randomizerCombination.RequiredParameter) that a data generation configuration cannot supply, for column $($columnobject.Name)"
                            $unsupportedColumns += $columnobject.Name
                        }
                    }

                    if ($unsupportedColumns.Count -gt 0) {
                        Stop-Function -Message "Skipping table $($tableobject.Schema).$($tableobject.Name) in $($db.Name), no data can be generated for these columns: $($unsupportedColumns -join ", ")" -Target $tableobject -Continue
                    }

                    $uniqueValues = @()
                    $uniqueValueColumns = @()

                    # Check if the table contains unique indexes
                    if ($tableobject.HasUniqueIndex) {
                        # Loop through the rows and generate a unique value for each row
                        Write-Message -Level Verbose -Message "Generating unique values for $($tableobject.Name)"

                        $uniqueIndexes = @($db.Tables[$($tableobject.Name)].Indexes | Where-Object IsUnique -eq $true)

                        # Only the index columns that are part of the configuration get a value generated
                        # here. The insert statement further down only names configured columns, so an
                        # index column outside the configuration is left to SQL Server. Identity columns
                        # are excluded even when they carry the unique index - the typical primary key:
                        # their values come from the identity branch of the insert, and random values
                        # here would jump the identity seed toward the type limit.
                        $identityColumnNames = @($tableobject.Columns | Where-Object Identity | Select-Object -ExpandProperty Name)
                        $uniqueValueColumns = @($uniqueIndexes.IndexedColumns.Name | Select-Object -Unique | Where-Object { $PSItem -in $tableobject.Columns.Name -and $PSItem -notin $identityColumnNames })

                        # The collision check must also see what is already persisted: without
                        # TruncateTable, a candidate matching an existing indexed value would pass
                        # the generation and then fail at insert time.
                        $existingUniqueValues = @()
                        if ($uniqueValueColumns.Count -gt 0 -and -not $tableobject.TruncateTable) {
                            $existingColumnList = "[" + ($uniqueValueColumns -join "], [") + "]"
                            $existingValuesQuery = "SELECT DISTINCT $existingColumnList FROM [$($tableobject.Schema)].[$($tableobject.Name)]"
                            try {
                                $existingUniqueValues = @(Invoke-DbaQuery -SqlInstance $server -Database $db.Name -Query $existingValuesQuery -EnableException)
                            } catch {
                                Stop-Function -Message "Error reading the existing unique index values from $($tableobject.Schema).$($tableobject.Name)" -Target $tableobject -ErrorRecord $_
                                return
                            }
                        }

                        for ($i = 0; $i -lt $tableobject.Rows; $i++) {
                            $attempt = 0

                            # Generate a candidate row holding a value for every unique index column and
                            # try again as long as a unique index of an earlier row holds the same
                            # combination. The whole candidate is regenerated on a collision, so two
                            # indexes sharing a column stay consistent within the row.
                            do {
                                $attempt++
                                $rowValue = New-Object PSCustomObject

                                foreach ($indexColumnName in $uniqueValueColumns) {
                                    # Get the column mask info
                                    $columnMaskInfo = $tableobject.Columns | Where-Object Name -eq $indexColumnName

                                    # Generate a new value
                                    try {
                                        if ($PSBoundParameters.MaxValue -and $columnMaskInfo.SubType -eq "String" -and $columnMaskInfo.MaxValue -gt $MaxValue) {
                                            $columnMaskInfo.MaxValue = $MaxValue
                                        }
                                        if ($columnMaskInfo.ColumnType -in $supportedDataTypes -and $columnMaskInfo.MaskingType -eq "Random" -and $columnMaskInfo.SubType -in "Bool", "Number", "Float", "Byte", "String") {
                                            $newValue = Get-DbaRandomizedValue -DataType $columnMaskInfo.ColumnType -Locale $Locale -Min $columnMaskInfo.MinValue -Max $columnMaskInfo.MaxValue
                                        } else {
                                            $newValue = Get-DbaRandomizedValue -RandomizerType $columnMaskInfo.MaskingType -RandomizerSubtype $columnMaskInfo.SubType -Locale $Locale -Min $columnMaskInfo.MinValue -Max $columnMaskInfo.MaxValue
                                        }
                                    } catch {
                                        Stop-Function -Message "Failure" -Target $columnMaskInfo -Continue -ErrorRecord $_
                                    }

                                    $rowValue | Add-Member -Name $indexColumnName -Type NoteProperty -Value $newValue
                                }

                                # A collision is an earlier row that carries the same values in all the
                                # configured columns of one of the unique indexes.
                                $collision = $false
                                foreach ($index in $uniqueIndexes) {
                                    $indexColumnNames = @($index.IndexedColumns.Name | Where-Object { $PSItem -in $uniqueValueColumns })

                                    if ($indexColumnNames.Count -eq 0) {
                                        continue
                                    }

                                    foreach ($existingRow in ($existingUniqueValues + $uniqueValues)) {
                                        $matchingColumnNames = @($indexColumnNames | Where-Object { $existingRow.$PSItem -eq $rowValue.$PSItem })

                                        if ($matchingColumnNames.Count -eq $indexColumnNames.Count) {
                                            $collision = $true
                                            break
                                        }
                                    }

                                    if ($collision) {
                                        break
                                    }
                                }
                            } while ($collision -and $attempt -lt 100)

                            if ($collision) {
                                Stop-Function -Message "Could not generate a unique value for the unique indexes of $($tableobject.Name) after $attempt tries" -Target $tableobject
                                return
                            }

                            # Add the row value to the array
                            $uniqueValues += $rowValue
                        }
                    }

                    if (-not $server.IsAzure) {
                        $sqlconn.ChangeDatabase($db.Name)
                    }
                    $insertQuery = ""

                    if ($Pscmdlet.ShouldProcess($instance, "Generating data for columns $($tablecolumns.Name -join ', ') in $($tableobject.Rows) rows in $($db.Name).$($tableobject.Schema).$($tableobject.Name)")) {
                        $elapsed = [System.Diagnostics.Stopwatch]::StartNew()

                        Write-ProgressHelper -StepNumber ($stepcounter++) -TotalSteps $tables.Tables.Count -Activity "Generating data" -Message "Inserting $($tableobject.Rows) rows in $($tableobject.Schema).$($tableobject.Name) in $($db.Name) on $instance"

                        if ($tableobject.TruncateTable) {
                            $query = "TRUNCATE TABLE [$($tableobject.Schema)].[$($tableobject.Name)];"

                            try {
                                $null = Invoke-DbaQuery -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $db.Name -Query $query
                            } catch {
                                Write-Message -Level VeryVerbose -Message "$query"
                                $errormessage = $_.Exception.Message.ToString()
                                Stop-Function -Message "Error truncating $($tableobject.Schema).$($tableobject.Name): $errormessage" -Target $query -Continue -ErrorRecord $_
                            }
                        }

                        if ($tableobject.Columns.Identity -contains $true) {
                            $query = "SELECT IDENT_CURRENT('[$($tableobject.Schema)].[$($tableobject.Name)]') AS CurrentIdentity,
                            IDENT_INCR('[$($tableobject.Schema)].[$($tableobject.Name)]') AS IdentityIncrement,
                            IDENT_SEED('[$($tableobject.Schema)].[$($tableobject.Name)]') AS IdentitySeed;"

                            try {
                                $identityValues = Invoke-DbaQuery -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $db.Name -Query $query
                                # https://docs.microsoft.com/en-us/sql/t-sql/public/ident-current-transact-sql says:
                                # When the IDENT_CURRENT value is NULL (because the table has never contained rows or has been truncated), the IDENT_CURRENT function returns the seed value.
                                # So if we get a 1 back, we count the rows so that the first row added to an empty table gets the number 1.
                                if ($identityValues.CurrentIdentity -eq 1) {
                                    $query = "SELECT COUNT(*) FROM [$($tableobject.Schema)].[$($tableobject.Name)];"
                                    $rowcount = Invoke-DbaQuery -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $db.Name -Query $query -As SingleValue
                                    if ($rowcount -eq 0) {
                                        $identityValues.CurrentIdentity = 0
                                    }
                                }
                            } catch {
                                Write-Message -Level VeryVerbose -Message "$query"
                                $errormessage = $_.Exception.Message.ToString()
                                Stop-Function -Message "Error getting identity values from $($tableobject.Schema).$($tableobject.Name): $errormessage" -Target $query -Continue -ErrorRecord $_
                            }

                            $insertQuery += "SET IDENTITY_INSERT [$($tableobject.Schema)].[$($tableobject.Name)] ON;`n"
                        }

                        $insertQuery += "INSERT INTO [$($tableobject.Schema)].[$($tableobject.Name)] ([$($tablecolumns.Name -join '],[')])`nVALUES`n"

                        [int]$nextIdentity = $null

                        for ($i = 1; $i -le $tableobject.Rows; $i++) {
                            $columnValues = @()

                            foreach ($columnobject in $tablecolumns) {

                                # The data type, the masking type and the subtype of every column were checked
                                # before the insert statement was built.

                                # make sure max is good
                                # A column of a unique index always gets its pre-generated value, even when
                                # it is nullable - the second NULL would already violate the index.
                                if ($tableobject.HasUniqueIndex -and $columnobject.Name -in $uniqueValueColumns) {

                                    if ($uniqueValues.Count -lt 1) {
                                        Stop-Function -Message "Could not find any unique values in dictionary" -Target $tableobject
                                        return
                                    }

                                    $columnValue = $uniqueValues[$i - 1].$($columnobject.Name)

                                } elseif ($columnobject.Nullable -and (($nullmod++) % $ModulusFactor -eq 0)) {
                                    $columnValue = $null
                                } elseif ($columnobject.Identity) {
                                    if ($nextIdentity -or (-not $nextIdentity -and $tableobject.TruncateTable)) {
                                        $nextIdentity += $identityValues.IdentityIncrement
                                    } else {
                                        $nextIdentity = $identityValues.CurrentIdentity + $identityValues.IdentityIncrement
                                    }
                                    $columnValue = $nextIdentity
                                } else {

                                    if ($columnobject.CharacterString) {
                                        $charstring = $columnobject.CharacterString
                                    } else {
                                        $charstring = $CharacterString
                                    }

                                    if (($columnobject.MinValue -or $columnobject.MaxValue) -and ($columnobject.ColumnType -match 'date')) {
                                        if (-not $columnobject.MinValue) {
                                            $columnobject.MinValue = (Get-Date -Date $columnobject.MaxValue).AddDays(-365)
                                        }
                                        if (-not $columnobject.MaxValue) {
                                            $columnobject.MaxValue = (Get-Date -Date $columnobject.MinValue).AddDays(365)
                                        }
                                    }

                                    try {
                                        if ($PSBoundParameters.MaxValue -and $columnobject.SubType -eq 'String' -and $columnobject.MaxValue -gt $MaxValue) {
                                            $columnobject.MaxValue = $MaxValue
                                        }
                                        if ($columnobject.ColumnType -in $supportedDataTypes -and $columnobject.MaskingType -eq 'Random' -and $columnobject.SubType -in 'Bool', 'Number', 'Float', 'Byte', 'String') {
                                            $randomParams = @{
                                                DataType        = $columnobject.ColumnType
                                                CharacterString = $charstring
                                                Locale          = $Locale
                                                Min             = $columnobject.MinValue
                                                Max             = $columnobject.MaxValue
                                            }
                                            $columnValue = Get-DbaRandomizedValue @randomParams
                                        } else {
                                            $randomParams = @{
                                                RandomizerType    = $columnobject.MaskingType
                                                RandomizerSubtype = $columnobject.SubType
                                                CharacterString   = $charstring
                                                Locale            = $Locale
                                                Min               = $columnobject.MinValue
                                                Max               = $columnobject.MaxValue
                                            }
                                            $columnValue = Get-DbaRandomizedValue @randomParams
                                        }

                                    } catch {
                                        Stop-Function -Message "Failure" -Target $script:faker -Continue -ErrorRecord $_
                                    }

                                }

                                # Most subtypes return a date as a string that is already formatted for SQL
                                # Server, but the ones Bogus exposes as a property, like Person.DateOfBirth,
                                # come back as a DateTime. Converting that further down with ToString() and no
                                # culture writes whatever the process culture uses, which swaps day and month
                                # everywhere but the invariant culture.
                                if ($columnValue -is [datetime]) {
                                    $columnValue = $columnValue.ToString("yyyy-MM-dd HH:mm:ss.fff", [System.Globalization.CultureInfo]::InvariantCulture)
                                }

                                if ($null -eq $columnValue -and $columnobject.Nullable -eq $true) {
                                    $columnValues += 'NULL'
                                } elseif ($columnobject.ColumnType -eq 'xml') {
                                    # nothing, unsure how i'll handle this
                                } elseif ($columnobject.ColumnType -in 'uniqueidentifier') {
                                    $columnValues += "'$columnValue'"
                                } elseif ($columnobject.ColumnType -match 'int') {
                                    $columnValues += "$columnValue"
                                } elseif ($columnobject.ColumnType -in 'bit', 'bool') {
                                    if ($columnValue) {
                                        $columnValues += "1"
                                    } else {
                                        $columnValues += "0"
                                    }
                                } else {
                                    $columnValue = ($columnValue).Tostring().Replace("'", "''")
                                    $columnValues += "'$columnValue'"
                                }
                            }

                            if ($i -lt $tableobject.Rows) {
                                $insertQuery += "( $($columnValues -join ',') ),`n"
                            } else {
                                $insertQuery += "( $($columnValues -join ',') );`n"
                            }
                        }

                        if ($tableobject.Columns.Identity -contains $true) {
                            $insertQuery += "SET IDENTITY_INSERT [$($tableobject.Schema)].[$($tableobject.Name)] OFF;"
                        }

                        try {
                            $transaction = $sqlconn.BeginTransaction()
                            $sqlcmd = New-Object Microsoft.Data.SqlClient.SqlCommand($insertQuery, $sqlconn, $transaction)
                            $null = $sqlcmd.ExecuteNonQuery()
                        } catch {
                            Write-Message -Level VeryVerbose -Message "$insertQuery"
                            $errormessage = $_.Exception.Message.ToString()
                            Stop-Function -Message "Error inserting $($tableobject.Schema).$($tableobject.Name): $errormessage" -Target $insertQuery -Continue -ErrorRecord $_
                        }


                    }

                    try {
                        $null = $transaction.Commit()
                        [PSCustomObject]@{
                            ComputerName = $db.Parent.ComputerName
                            InstanceName = $db.Parent.ServiceName
                            SqlInstance  = $db.Parent.DomainInstanceName
                            Database     = $db.Name
                            Schema       = $tableobject.Schema
                            Table        = $tableobject.Name
                            Columns      = $tableobject.Columns.Name
                            Rows         = $tableobject.Rows
                            Elapsed      = [prettytimespan]$elapsed.Elapsed
                            Status       = "Done"
                        }
                    } catch {
                        Stop-Function -Message "Error inserting into $($tableobject.Schema).$($tableobject.Name)" -Target $insertQuery -Continue -ErrorRecord $_
                    }
                }
            }

            try {
                $sqlconn.Close()
            } catch {
                Stop-Function -Message "Failure" -Continue -ErrorRecord $_
            }
        }
    }
}