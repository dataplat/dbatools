function Invoke-DbaDbDataGenerator {
    <#
    .SYNOPSIS
        Invoke-DbaDbDataGenerator generates random data for tables

    .DESCRIPTION
        Invoke-DbaDbDataMasking is able to generate random data for tables.

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

    .PARAMETER ExactLength
        Mask string values to the same length. So 'Tate' will be replaced with 4 random characters.

    .PARAMETER ModulusFactor
        Calculating the next nullable by using the remainder from the modulus. Default is every 10.

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
        Tags: DataGeneration, Database
        Author: Sander Stad (@sqlstad, sqlstad.nl)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Invoke-DbaDbDataGenerator

    .EXAMPLE
        Invoke-DbaDbDataGenerator -SqlInstance SQLDB2 -Database DB1 -FilePath C:\Temp\sqldb1.db1.tables.json

        Apply the data generation configuration from the file "sqldb1.db1.tables.json" to the db1 database on sqldb2. Prompt for confirmation for each table.

    .EXAMPLE
        Get-ChildItem -Path C:\Temp\sqldb1.db1.tables.json | Invoke-DbaDbDataGenerator -SqlInstance SQLDB2 -Database DB1 -Confirm:$false

        Apply the data generation configuration from the file "sqldb1.db1.tables.json" to the db1 database on sqldb2. Do not prompt for confirmation.

    .EXAMPLE
        New-DbaDbDataGeneratorConfig -SqlInstance SQLDB1 -Database DB1 -Path C:\Temp\clone -OutVariable file
        $file | Invoke-DbaDbDataGenerator -SqlInstance SQLDB2 -Database DB1 -Confirm:$false

        Create the data generation configuration file "sqldb1.db1.tables.json", then use it to mask the db1 database on sqldb2. Do not prompt for confirmation.

    .EXAMPLE
        Get-ChildItem -Path C:\Temp\sqldb1.db1.tables.json | Invoke-DbaDbDataGenerator -SqlInstance SQLDB2, sqldb3 -Database DB1 -Confirm:$false

        See what would happen if you the data generation configuration from the file "sqldb1.db1.tables.json" to the db1 database on sqldb2 and sqldb3. Do not prompt for confirmation.

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
        [string]$Query,
        [int]$MaxValue,
        [switch]$ExactLength,
        [int]$ModulusFactor = 10,
        [switch]$EnableException
    )

    begin {
        # Create the faker objects
        Add-Type -Path (Resolve-Path -Path "$script:PSModuleRoot\bin\datamasking\Bogus.dll")
        $faker = New-Object Bogus.Faker($Locale)

        $supportedDataTypes = 'bit', 'bool', 'char', 'date', 'datetime', 'datetime2', 'decimal', 'int', 'money', 'nchar', 'ntext', 'nvarchar', 'smalldatetime', 'text', 'time', 'uniqueidentifier', 'userdefineddatatype', 'varchar'

        $supportedFakerMaskingTypes = ($faker | Get-Member -MemberType Property | Select-Object Name -ExpandProperty Name)

        $supportedFakerSubTypes = ($faker | Get-Member -MemberType Property) | ForEach-Object { ($faker.$($_.Name)) | Get-Member -MemberType Method | Where-Object {$_.Name -notlike 'To*' -and $_.Name -notlike 'Get*' -and $_.Name -notlike 'Trim*' -and $_.Name -notin 'Add', 'Equals', 'CompareTo', 'Clone', 'Contains', 'CopyTo', 'EndsWith', 'IndexOf', 'IndexOfAny', 'Insert', 'IsNormalized', 'LastIndexOf', 'LastIndexOfAny', 'Normalize', 'PadLeft', 'PadRight', 'Remove', 'Replace', 'Split', 'StartsWith', 'Substring', 'Letter', 'Lines', 'Paragraph', 'Paragraphs', 'Sentence', 'Sentences'} | Select-Object name -ExpandProperty Name }

        $supportedFakerSubTypes += "Date"

        #$foreignKeyQuery = Get-Content -Path "$script:PSModuleRoot\bin\datageneration\ForeignKeyHierarchy.sql"
    }

    process {
        if (Test-FunctionInterrupt) {
            return
        }

        if ($FilePath.ToString().StartsWith('http')) {
            $tables = Invoke-RestMethod -Uri $FilePath
        } else {
            # Check if the destination is accessible
            if (-not (Test-Path -Path $FilePath)) {
                Stop-Function -Message "Could not find masking config file $FilePath" -Target $FilePath
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

        if (Test-FunctionInterrupt) {
            return
        }

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
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

                                    # Generate a new value
                                    $newValue = $faker.$($columnMaskInfo.MaskingType).$($columnMaskInfo.SubType)()

                                    # Check if the value is already present as a property
                                    if (($rowValue | Get-Member -MemberType NoteProperty).Name -notcontains $indexColumn.Name) {
                                        $rowValue | Add-Member -Name $indexColumn.Name -Type NoteProperty -Value $newValue
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
                                        $newValue = $faker.$($columnMaskInfo.MaskingType).$($columnMaskInfo.SubType)()

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
                    $tableobject.HasUniqueIndex
                    $uniqueValues.Count
                    $uniqueValueColumns = $uniqueValueColumns | Select-Object -Unique

                    $sqlconn.ChangeDatabase($db.Name)

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

                    if ($Pscmdlet.ShouldProcess($instance, "Generating data $($tablecolumns.Name -join ', ') in $($data.Rows.Count) rows in $($db.Name).$($tableobject.Schema).$($tableobject.Name)")) {
                        $transaction = $sqlconn.BeginTransaction()
                        $elapsed = [System.Diagnostics.Stopwatch]::StartNew()

                        Write-ProgressHelper -StepNumber ($stepcounter++) -TotalSteps $tables.Tables.Count -Activity "Generating data" -Message "Inserting $($tableobject.Rows) rows in $($tableobject.Schema).$($tableobject.Name) in $($db.Name) on $instance"

                        if ($tableobject.TruncateTable) {
                            $query += "TRUNCATE TABLE [$($tableobject.Schema)].[$($tableobject.Name)];`n"

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
                            } catch {
                                Write-Message -Level VeryVerbose -Message "$query"
                                $errormessage = $_.Exception.Message.ToString()
                                Stop-Function -Message "Error setting identity values from $($tableobject.Schema).$($tableobject.Name): $errormessage" -Target $query -Continue -ErrorRecord $_
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
                                    $columnValues += $null
                                } elseif ($tableobject.HasUniqueIndex -and $columnobject.Name -in $uniqueValueColumns) {

                                    if ($uniqueValues.Count -lt 1) {
                                        Stop-Function -Message "Could not find any unique values in dictionary" -Target $tableobject
                                        return
                                    }

                                    $newValue = $uniqueValues[$rowNumber].$($columnobject.Name)

                                } elseif ($columnobject.Identity) {
                                    if ($nextIdentity -or (-not $nextIdentity -and $tableobject.TruncateTable)) {
                                        $nextIdentity += $identityValues.IdentityIncrement
                                    } else {
                                        $nextIdentity = $identityValues.CurrentIdentity + $identityValues.IdentityIncrement
                                    }
                                    $columnValues += $nextIdentity
                                } else {
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

                                    if ($columnobject.CharacterString) {
                                        $charstring = $columnobject.CharacterString
                                    } else {
                                        $charstring = $CharacterString
                                    }

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

                                    if (($columnobject.MinValue -or $columnobject.MaxValue) -and ($columnobject.ColumnType -match 'date')) {
                                        $nowmin = $columnobject.MinValue
                                        $nowmax = $columnobject.MaxValue
                                        if (-not $nowmin) {
                                            $nowmin = (Get-Date -Date $nowmax).AddDays(-365)
                                        }
                                        if (-not $nowmax) {
                                            $nowmax = (Get-Date -Date $nowmin).AddDays(365)
                                        }
                                    }

                                    try {
                                        $columnValue = $null

                                        if (-not $columnValue) {
                                            $columnValue = switch ($columnobject.ColumnType) {
                                                {
                                                    $psitem -in 'bit', 'bool'
                                                } {
                                                    $faker.System.Random.Bool()
                                                }
                                                {
                                                    $psitem -match 'date'
                                                } {
                                                    if ($columnobject.MinValue -or $columnobject.MaxValue) {
                                                        ($faker.Date.Between($nowmin, $nowmax)).ToString("yyyyMMdd")
                                                    } else {
                                                        ($faker.Date.Past()).ToString("yyyyMMdd")
                                                    }
                                                }
                                                {
                                                    $psitem -match 'int'
                                                } {
                                                    if ($columnobject.MinValue -or $columnobject.MaxValue) {
                                                        $faker.System.Random.Int($columnobject.MinValue, $columnobject.MaxValue)
                                                    } else {
                                                        $faker.System.Random.Int(0, $max)
                                                    }
                                                }
                                                'money' {
                                                    if ($columnobject.MinValue -or $columnobject.MaxValue) {
                                                        $faker.Finance.Amount($columnobject.MinValue, $columnobject.MaxValue)
                                                    } else {
                                                        $faker.Finance.Amount(0, $max)
                                                    }
                                                }
                                                'time' {
                                                    ($faker.Date.Past()).ToString("h:mm tt zzz")
                                                }
                                                'uniqueidentifier' {
                                                    $faker.System.Random.Guid().Guid
                                                }
                                                'userdefineddatatype' {
                                                    if ($columnobject.MaxValue -eq 1) {
                                                        $faker.System.Random.Bool()
                                                    } else {
                                                        $null
                                                    }
                                                }
                                                default {
                                                    $null
                                                }
                                            }
                                        }

                                        if (-not $columnValue) {
                                            $columnValue = switch ($columnobject.SubType.ToLower()) {
                                                'number' {
                                                    $faker.$($columnobject.MaskingType).$($columnobject.SubType)($columnobject.MaxValue)
                                                }
                                                {
                                                    $psitem -in 'bit', 'bool'
                                                } {
                                                    $faker.System.Random.Bool()
                                                }
                                                {
                                                    $psitem -in 'date', 'datetime', 'datetime2', 'smalldatetime'
                                                } {
                                                    if ($columnobject.MinValue -or $columnobject.MaxValue) {
                                                        ($faker.Date.Between($nowmin, $nowmax)).ToString("yyyyMMdd")
                                                    } else {
                                                        ($faker.Date.Past()).ToString("yyyyMMdd")
                                                    }
                                                }
                                                'shuffle' {
                                                    ($row.($columnobject.Name) -split '' | Sort-Object {
                                                            Get-Random
                                                        }) -join ''
                                                }
                                                'string' {
                                                    if ($max -eq -1) {
                                                        $max = 1024
                                                    }

                                                    if ($columnobject.SubType -eq "String" -and (Test-Bound -ParameterName ExactLength)) {
                                                        $max = ($row.$($columnobject.Name)).Length
                                                    }

                                                    if ($columnobject.ColumnType -eq 'xml') {
                                                        $null
                                                    } else {
                                                        $faker.$($columnobject.MaskingType).String2($max, $charstring)
                                                    }
                                                }
                                                default {
                                                    $null
                                                }
                                            }
                                        }

                                        if (-not $columnValue) {
                                            $columnValue = switch ($columnobject.MaskingType.ToLower()) {
                                                {
                                                    $psitem -in 'bit', 'bool'
                                                } {
                                                    $faker.System.Random.Bool()
                                                }
                                                {
                                                    $psitem -in 'address', 'commerce', 'company', 'context', 'database', 'date', 'finance', 'hacker', 'hashids', 'image', 'internet', 'lorem', 'name', 'person', 'phone', 'random', 'rant', 'system'
                                                } {
                                                    if ($columnobject.Format) {
                                                        $faker.$($columnobject.MaskingType).$($columnobject.SubType)("$($columnobject.Format)")
                                                    } else {
                                                        $faker.$($columnobject.MaskingType).$($columnobject.SubType)()
                                                    }
                                                }
                                                default {
                                                    if ($max -eq -1) {
                                                        $max = 1024
                                                    }
                                                    if ((Test-Bound -ParameterName ExactLength)) {
                                                        $max = ($row.$($columnobject.Name)).ToString().Length
                                                    }
                                                    if ($max -eq 1) {
                                                        $faker.System.Random.Bool()
                                                    } else {
                                                        try {
                                                            if ($columnobject.Format) {
                                                                $faker.$($columnobject.MaskingType).$($columnobject.SubType)("$($columnobject.Format)")
                                                            } else {
                                                                $faker.$($columnobject.MaskingType).$($columnobject.SubType)()
                                                            }
                                                        } catch {
                                                            $faker.Random.String2($max, $charstring)
                                                        }
                                                    }
                                                }
                                            }

                                        }
                                    } catch {
                                        Stop-Function -Message "Failure" -Target $faker -Continue -ErrorRecord $_
                                    }


                                    if ($columnobject.ColumnType -eq 'xml') {
                                        # nothing, unsure how i'll handle this
                                    } elseif ($columnobject.ColumnType -in 'uniqueidentifier') {
                                        if ($null -eq $columnValue -and $columnobject.Nullable) {
                                            $columnValues += "NULL"
                                        } else {
                                            $columnValues += "'$columnValue'"
                                        }
                                    } elseif ($columnobject.ColumnType -match 'int') {
                                        if ($null -eq $columnValue -and $columnobject.Nullable) {
                                            $columnValues += "NULL"
                                        } else {
                                            $columnValues += "$columnValue"
                                        }
                                    } elseif ($columnobject.ColumnType -in 'bit', 'bool') {
                                        if ($null -eq $columnValue -and $columnobject.Nullable) {
                                            $columnValues += "NULL"
                                        } else {
                                            if ($newValue) {
                                                $columnValues += "1"
                                            } else {
                                                $columnValues += "0"
                                            }
                                        }
                                    } else {
                                        if ($null -eq $columnValue -and $columnobject.Nullable) {
                                            $columnValues += "NULL"
                                        } else {
                                            $columnValue = ($columnValue).Tostring().Replace("'", "''")
                                            $columnValues += "'$columnValue'"
                                        }
                                    }

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
                        #$insertQuery
                        try {
                            $sqlcmd = New-Object System.Data.SqlClient.SqlCommand($insertQuery, $sqlconn, $transaction)
                            $null = $sqlcmd.ExecuteNonQuery()
                        } catch {
                            Write-Message -Level VeryVerbose -Message "$insertQuery"
                            $errormessage = $_.Exception.Message.ToString()
                            Stop-Function -Message "Error inserting $($tableobject.Schema).$($tableobject.Name): $errormessage" -Target $insertQuery -Continue -ErrorRecord $_
                        }


                    }

                    try {
                        $null = $transaction.Commit()
                        [pscustomobject]@{
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