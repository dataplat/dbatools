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

        $supportedDataTypes = 'bigint', 'bit', 'bool', 'char', 'date', 'datetime', 'datetime2', 'decimal', 'int', 'float', 'guid', 'money', 'numeric', 'nchar', 'ntext', 'nvarchar', 'real', 'smalldatetime', 'smallint', 'text', 'time', 'tinyint', 'uniqueidentifier', 'userdefineddatatype', 'varchar'
        $supportedFakerMaskingTypes = ($script:faker | Get-Member -MemberType Property | Select-Object Name -ExpandProperty Name)
        # The value of the property DateTimeReference is currently $null, which causes the next line to throw an exception.
        # We have to contact the developer of Bogus to solve the issue.
        $supportedFakerSubTypes = ($script:faker | Get-Member -MemberType Property | Where-Object Name -ne DateTimeReference) | ForEach-Object { ($script:faker.$($_.Name)) | Get-Member -MemberType Method | Where-Object { $_.Name -notlike 'To*' -and $_.Name -notlike 'Get*' -and $_.Name -notlike 'Trim*' -and $_.Name -notin 'Add', 'Equals', 'CompareTo', 'Clone', 'Contains', 'CopyTo', 'EndsWith', 'IndexOf', 'IndexOfAny', 'Insert', 'IsNormalized', 'LastIndexOf', 'LastIndexOfAny', 'Normalize', 'PadLeft', 'PadRight', 'Remove', 'Replace', 'Split', 'StartsWith', 'Substring', 'Letter', 'Lines', 'Paragraph', 'Paragraphs', 'Sentence', 'Sentences' } | Select-Object name -ExpandProperty Name }
        $supportedFakerSubTypes += "Date"
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
                Test-DbaDbDataGeneratorConfig -FilePath $FilePath -EnableException
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

                    $uniqueValues = @()

                    # Check if the table contains unique indexes
                    if ($tableobject.HasUniqueIndex) {
                        # Loop through the rows and generate a unique value for each row
                        Write-Message -Level Verbose -Message "Generating unique values for $($tableobject.Name)"

                        for ($i = 0; $i -lt $tableobject.Rows; $i++) {
                            $rowValue = New-Object PSCustomObject

                            # Loop through each of the unique indexes
                            foreach ($index in ($db.Tables[$($tableobject.Name)].Indexes | Where-Object IsUnique -eq $true )) {

                                # Loop through the index columns
                                foreach ($indexColumn in $index.IndexedColumns) {
                                    # Get the column mask info
                                    $columnMaskInfo = $tableobject.Columns | Where-Object Name -eq $indexColumn.Name

                                    if ($columnMaskInfo) {
                                        # Generate a new value
                                        try {
                                            if ($PSBoundParameters.MaxValue -and $columnMaskInfo.SubType -eq 'String' -and $columnMaskInfo.MaxValue -gt $MaxValue) {
                                                $columnMaskInfo.MaxValue = $MaxValue
                                            }
                                            if ($columnMaskInfo.ColumnType -in $supportedDataTypes -and $columnMaskInfo.MaskingType -eq 'Random' -and $columnMaskInfo.SubType -in 'Bool', 'Number', 'Float', 'Byte', 'String') {
                                                $newValue = Get-DbaRandomizedValue -DataType $columnMaskInfo.ColumnType -Locale $Locale -Min $columnMaskInfo.MinValue -Max $columnMaskInfo.MaxValue
                                            } else {
                                                $newValue = Get-DbaRandomizedValue -RandomizerType $columnMaskInfo.MaskingType -RandomizerSubtype $columnMaskInfo.SubType -Locale $Locale -Min $columnMaskInfo.MinValue -Max $columnMaskInfo.MaxValue
                                            }
                                        } catch {
                                            Stop-Function -Message "Failure" -Target $columnMaskInfo -Continue -ErrorRecord $_
                                        }

                                        # Check if the value is already present as a property
                                        if (($rowValue | Get-Member -MemberType NoteProperty).Name -notcontains $indexColumn.Name) {
                                            $rowValue | Add-Member -Name $indexColumn.Name -Type NoteProperty -Value $newValue
                                        }
                                    }

                                }

                                # To be sure the values are unique, loop as long as long as needed to generate a unique value
                                while (($uniqueValues | Select-Object -Property ($rowValue | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name)) -match $rowValue) {

                                    $rowValue = New-Object PSCustomObject

                                    # Loop through the index columns
                                    foreach ($indexColumn in $index.IndexedColumns) {
                                        # Get the column mask info
                                        $columnMaskInfo = $tableobject.Columns | Where-Object Name -eq $indexColumn.Name

                                        # Generate a new value
                                        try {
                                            if ($PSBoundParameters.MaxValue -and $columnMaskInfo.SubType -eq 'String' -and $columnMaskInfo.MaxValue -gt $MaxValue) {
                                                $columnMaskInfo.MaxValue = $MaxValue
                                            }
                                            if ($columnMaskInfo.ColumnType -in $supportedDataTypes -and $columnMaskInfo.MaskingType -eq 'Random' -and $columnMaskInfo.SubType -in 'Bool', 'Number', 'Float', 'Byte', 'String') {
                                                $newValue = Get-DbaRandomizedValue -DataType $columnMaskInfo.ColumnType -Locale $Locale -Min $columnMaskInfo.MinValue -Max $columnMaskInfo.MaxValue
                                            } else {
                                                $newValue = Get-DbaRandomizedValue -RandomizerType $columnMaskInfo.MaskingType -RandomizerSubtype $columnMaskInfo.SubType -Locale $Locale -Min $columnMaskInfo.MinValue -Max $columnMaskInfo.MaxValue
                                            }

                                        } catch {
                                            Stop-Function -Message "Failure" -Target $script:faker -Continue -ErrorRecord $_
                                        }

                                        # Check if the value is already present as a property
                                        if (($rowValue | Get-Member -MemberType NoteProperty).Name -notcontains $indexColumn.Name) {
                                            $rowValue | Add-Member -Name $indexColumn.Name -Type NoteProperty -Value $newValue
                                            $uniqueValueColumns += $indexColumn.Name
                                        }
                                    }
                                }
                            }
                            # Add the row value to the array
                            $uniqueValues += $rowValue
                        }
                    }

                    $uniqueValueColumns = $uniqueValueColumns | Select-Object -Unique

                    if (-not $server.IsAzure) {
                        $sqlconn.ChangeDatabase($db.Name)
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

                                if ($columnobject.ColumnType -notin $supportedDataTypes) {
                                    Stop-Function -Message "Unsupported data type '$($columnobject.ColumnType)' for column $($columnobject.Name)" -Target $columnobject -Continue
                                }

                                if ($columnobject.MaskingType -notin $supportedFakerMaskingTypes) {
                                    Stop-Function -Message "Unsupported masking type '$($columnobject.MaskingType)' for column $($columnobject.Name)" -Target $columnobject -Continue
                                }

                                if ($columnobject.SubType -notin $supportedFakerSubTypes) {
                                    Stop-Function -Message "Unsupported masking sub type '$($columnobject.SubType)' for column $($columnobject.Name)" -Target $columnobject -Continue
                                }

                                # make sure max is good
                                if ($columnobject.Nullable -and (($nullmod++) % $ModulusFactor -eq 0)) {
                                    $columnValue = $null
                                } elseif ($tableobject.HasUniqueIndex -and $columnobject.Name -in $uniqueValueColumns) {

                                    if ($uniqueValues.Count -lt 1) {
                                        Stop-Function -Message "Could not find any unique values in dictionary" -Target $tableobject
                                        return
                                    }

                                    $columnValue = $uniqueValues[$rowNumber].$($columnobject.Name)

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