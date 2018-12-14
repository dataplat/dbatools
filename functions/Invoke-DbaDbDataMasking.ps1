function Invoke-DbaDbDataMasking {
    <#
    .SYNOPSIS
        Invoke-DbaDbDataMasking generates random data for tables

    .DESCRIPTION
        Invoke-DbaDbDataMasking is able to generate random data for tables.
        It will use a configuration file that can be made manually or generated using New-DbaDbMaskingConfig

        Note that the following column and data types are not currently supported:
        Identity
        ForeignKey
        Computed
        Hierarchyid
        Geography
        Xml

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

    .PARAMETER Query
        If you would like to mask only a subset of a table, use the Query parameter, otherwise all data will be masked.

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
        Tags: DataMasking, Database
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
        [string]$Query,
        [int]$MaxValue,
        [switch]$EnableException
    )
    begin {
        # Create the faker objects
        Add-Type -Path (Resolve-Path -Path "$script:PSModuleRoot\bin\datamasking\Bogus.dll")
        $faker = New-Object Bogus.Faker($Locale)
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

        if ($Table) {
            $tables = $tables | Where-Object Name -in $Table
        }

        foreach ($tabletest in $tables.Tables) {
            foreach ($columntest in $tabletest.Columns) {
                if ($columntest.ColumnType -in 'hierarchyid', 'geography', 'xml' -and $columntest.Name -notin $Column) {
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

            foreach ($db in (Get-DbaDatabase -SqlInstance $server -Database $Database)) {
                $stepcounter = 0
                foreach ($tableobject in $tables.Tables) {
                    if ($tableobject.Name -in $ExcludeTable) {
                        Write-Message -Level Verbose -Message "Skipping $($tableobject.Name) because it is explicitly excluded"
                        continue
                    }

                    if ($tableobject.Name -notin $db.Tables.Name) {
                        Stop-Function -Message "Table $($tableobject.Name) is not present in $db" -Target $db -Continue
                    }
                    try {
                        if (-not (Test-Bound -ParameterName Query)) {
                            $query = "SELECT * FROM [$($tableobject.Schema)].[$($tableobject.Name)]"
                        }

                        $data = $db.Query($query) | ConvertTo-DbaDataTable
                    } catch {
                        Stop-Function -Message "Something went wrong retrieving the data from table $($tableobject.Name)" -Target $Database
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

                    if ($Pscmdlet.ShouldProcess($instance, "Masking $($tablecolumns.Name -join ', ') in $($data.Rows.Count) rows in $($db.Name).$($tableobject.Schema).$($tableobject.Name)")) {

                        Write-ProgressHelper -StepNumber ($stepcounter++) -TotalSteps $tables.Tables.Count -Activity "Masking data" -Message "Updating $($data.Rows.Count) rows in $($tableobject.Schema).$($tableobject.Name) in $($db.Name) on $instance"

                        # Loop through each of the rows and change them
                        foreach ($row in $data.Rows) {
                            $updates = $wheres = @()

                            foreach ($columnobject in $tablecolumns) {
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
                                    $newValue = switch ($columnobject.ColumnType) {
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
                                        default {
                                            $null
                                        }
                                    }

                                    if (-not $newValue) {
                                        $newValue = switch ($columnobject.Subtype.ToLower()) {
                                            'number' {
                                                $faker.$($columnobject.MaskingType).$($columnobject.SubType)($columnobject.MaxValue)
                                            }
                                            {
                                                $psitem -in 'bit', 'bool'
                                            } {
                                                $faker.System.Random.Bool()
                                            }
                                            {
                                                $psitem -in 'name', 'address', 'finance'
                                            } {
                                                $faker.$($columnobject.MaskingType).$($columnobject.SubType)()
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
                                                if ($columnobject.ColumnType -eq 'xml') {
                                                    $null
                                                } else {
                                                    $faker.$($columnobject.MaskingType).String2($max, $charstring)
                                                }
                                            }
                                            default {
                                                if ($max -eq -1) {
                                                    $max = 1024
                                                }
                                                $faker.Random.String2($max, $charstring)
                                            }
                                        }
                                    }
                                } catch {
                                    Stop-Function -Message "Failure" -Target $faker -Continue -ErrorRecord $_
                                }

                                if ($columnobject.ColumnType -eq 'xml') {
                                    # nothing, unsure how i'll handle this
                                } elseif ($columnobject.ColumnType -in 'uniqueidentifier') {
                                    $updates += "[$($columnobject.Name)] = '$newValue'"
                                } elseif ($columnobject.ColumnType -match 'int') {
                                    $updates += "[$($columnobject.Name)] = $newValue"
                                } else {
                                    $newValue = ($newValue).Tostring().Replace("'", "''")
                                    $updates += "[$($columnobject.Name)] = '$newValue'"
                                }

                                if ($columnobject.ColumnType -notin 'xml', 'geography') {
                                    $oldValue = ($row.$($columnobject.Name)).Tostring().Replace("'", "''")
                                    $wheres += "[$($columnobject.Name)] = '$oldValue'"
                                }
                            }

                            $updatequery = "UPDATE [$($tableobject.Schema)].[$($tableobject.Name)] SET $($updates -join ', ') WHERE $($wheres -join ' AND ')"

                            try {
                                $db.Query($updatequery)
                            } catch {
                                Write-Message -Level VeryVerbose -Message "$updatequery"
                                Stop-Function -Message "Error updating $($tableobject.Schema).$($tableobject.Name)" -Target $updatequery -Continue -ErrorRecord $_
                            }
                        }
                        [pscustomobject]@{
                            ComputerName = $db.Parent.ComputerName
                            InstanceName = $db.Parent.ServiceName
                            SqlInstance  = $db.Parent.DomainInstanceName
                            Database     = $db.Name
                            Schema       = $tableobject.Schema
                            Table        = $tableobject.Name
                            Columns      = $tableobject.Columns.Name
                            Status       = "Masked"
                        }
                    }
                }
            }
        }
    }
}