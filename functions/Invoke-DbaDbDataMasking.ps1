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

    .PARAMETER FilePath
        Configuration file that contains the which tables and columns need to be masked

    .PARAMETER Query
        If you would like to mask only a subset of a table, use the Query parameter, otherwise all data will be masked.

    .PARAMETER Locale
        Set the local to enable certain settings in the masking

    .PARAMETER CharacterString
        The characters to use in string data. 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789' by default

    .PARAMETER MaxValue
        Force a max length of strings instead of relying on datatype maxes. Note if a string datatype has a lower MaxValue, that will be used instead.

        Useful for adhoc updates and testing, otherwise, the config file should be used.

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
        https://dbatools.io/Invoke-DbaDbDataMasking

    .EXAMPLE
        Invoke-DbaDbDataMasking -SqlInstance SQLDB1 -Database DB1 -FilePath C:\Temp\DB1.tables.json

        Apply the data masking configuration from the file "DB1.tables.json" to the database
    #>
    [CmdLetBinding()]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [PSCredential]$Credential,
        [string[]]$Database,
        [parameter(Mandatory, ValueFromPipeline)]
        [Alias('Path', 'FullName')]
        [object]$FilePath,
        [string]$Locale = 'en',
        [string]$CharacterString = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789',
        [string]$Query,
        [switch]$Force,
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

        if ($FilePath.StartsWith('http')) {
            $tables = Invoke-RestMethod -Uri $FilePath
        } else {
            # Check if the destination is accessible
            if (-not (Test-Path -Path $FilePath -Credential $Credential)) {
                Stop-Function -Message "Could not find masking config file" -ErrorRecord $_ -Target $FilePath
                return
            }

            # Get all the items that should be processed
            try {
                $tables = Get-Content -Path $FilePath -Credential $Credential -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            } catch {
                Stop-Function -Message "Could not parse masking config file" -ErrorRecord $_ -Target $FilePath
                return
            }
        }

        foreach ($tabletest in $tables.Tables) {
            foreach ($columntest in $tabletest.Columns) {
                if ($columntest.ColumnType -in 'hierarchyid', 'geography', 'xml') {
                    Stop-Function -Message "$($columntest.ColumnType) is not supported, please remove the column $($columntest.Name) from the $($tabletest.Name) table" -Target $tables
                }
            }
        }

        if (Test-FunctionInterrupt) {
            return
        }

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            foreach ($db in (Get-DbaDatabase -SqlInstance $server -Database $Database)) {

                foreach ($table in $tables.Tables) {
                    if ($table.Name -in $db.Tables.Name) {
                        try {
                            if (-not (Test-Bound -ParameterName Query)) {
                                $query = "SELECT * FROM [$($table.Schema)].[$($table.Name)]"
                            }

                            $data = $db.Query($query) | ConvertTo-DbaDataTable
                        } catch {
                            Stop-Function -Message "Something went wrong retrieving the data from table $($table.Name)" -Target $Database
                        }

                        # Loop through each of the rows and change them
                        foreach ($row in $data.Rows) {
                            $updates = $wheres = @()

                            foreach ($column in $table.Columns) {
                                # make sure max is good
                                if ($MaxValue) {
                                    if ($column.MaxValue -le $MaxValue) {
                                        $max = $column.MaxValue
                                    } else {
                                        $max = $MaxValue
                                    }
                                }

                                if (-not $column.MaxValue -and -not (Test-Bound -ParameterName MaxValue)) {
                                    $max = 10
                                }

                                if ($column.CharacterString) {
                                    $charstring = $column.CharacterString
                                } else {
                                    $charstring = $CharacterString
                                }

                                # make sure min is good
                                if ($column.MinValue) {
                                    $min = $column.MinValue
                                } else {
                                    if ($column.CharacterString) {
                                        $min = 1
                                    } else {
                                        $min = 0
                                    }
                                }

                                if (($column.MinValue -or $column.MaxValue) -and ($column.ColumnType -match 'date')) {
                                    $nowmin = $column.MinValue
                                    $nowmax = $column.MaxValue
                                    if (-not $nowmin) {
                                        $nowmin = (Get-Date -Date $nowmax).AddDays(-365)
                                    }
                                    if (-not $nowmax) {
                                        $nowmax = (Get-Date -Date $nowmin).AddDays(365)
                                    }
                                }

                                try {
                                    $newValue = switch ($column.ColumnType) {
                                        { $psitem -in 'bit', 'bool', 'flag' } {
                                            $faker.System.Random.Bool()
                                        }
                                        { $psitem -match 'date' } {
                                            if ($column.MinValue -or $column.MaxValue) {
                                                ($faker.Date.Between($nowmin, $nowmax)).ToString("yyyyMMdd")
                                            } else {
                                                ($faker.Date.Past()).ToString("yyyyMMdd")
                                            }
                                        }
                                        { $psitem -match 'int' } {
                                            if ($column.MinValue -or $column.MaxValue) {
                                                $faker.System.Random.Int($column.MinValue, $column.MaxValue)
                                            } else {
                                                $faker.System.Random.Int(0, $max)
                                            }
                                        }
                                        'money' {
                                            if ($column.MinValue -or $column.MaxValue) {
                                                $faker.Finance.Amount($column.MinValue, $column.MaxValue)
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
                                        $newValue = switch ($column.Subtype.ToLower()) {
                                            'number' {
                                                $faker.$($column.MaskingType).$($column.SubType)($column.MaxValue)
                                            }
                                            { $psitem -in 'bit', 'bool', 'flag' } {
                                                $faker.System.Random.Bool()
                                            }
                                            { $psitem -in 'name', 'address', 'finance' } {
                                                $faker.$($column.MaskingType).$($column.SubType)()
                                            }
                                            { $psitem -in 'date', 'datetime', 'datetime2', 'smalldatetime' } {
                                                if ($column.MinValue -or $column.MaxValue) {
                                                    ($faker.Date.Between($nowmin, $nowmax)).ToString("yyyyMMdd")
                                                } else {
                                                    ($faker.Date.Past()).ToString("yyyyMMdd")
                                                }
                                            }
                                            'shuffle' {
                                                ($row.($column.Name) -split '' | Sort-Object {
                                                        Get-Random
                                                    }) -join ''
                                            }
                                            'string' {
                                                if ($max -eq -1) {
                                                    $max = 1024
                                                }
                                                if ($column.ColumnType -eq 'xml') {
                                                    $null
                                                } else {
                                                    $faker.$($column.MaskingType).String2($max, $charstring)
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

                                if ($column.ColumnType -eq 'xml') {
                                    # nothing, unsure how i'll handle this
                                } elseif ($column.ColumnType -in 'uniqueidentifier') {
                                    $updates += "[$($column.Name)] = '$newValue'"
                                } elseif ($column.ColumnType -match 'int') {
                                    $updates += "[$($column.Name)] = $newValue"
                                } else {
                                    $newValue = ($newValue).Tostring().Replace("'", "''")
                                    $updates += "[$($column.Name)] = '$newValue'"
                                }

                                if ($column.ColumnType -notin 'xml', 'geography') {
                                    $oldValue = ($row.$($column.Name)).Tostring().Replace("'", "''")
                                    $wheres += "[$($column.Name)] = '$oldValue'"
                                }
                            }

                            $updatequery = "UPDATE [$($table.Schema)].[$($table.Name)] SET $($updates -join ', ') WHERE $($wheres -join ' AND ')"

                            try {
                                Write-Message -Level Debug -Message $updatequery
                                $db.Query($updatequery)
                                [pscustomobject]@{
                                    SqlInstance = $db.Parent.Name
                                    Database    = $db.Name
                                    Schema      = $table.Schema
                                    Table       = $table.Name
                                    Query       = $updatequery
                                    Status      = "Success"
                                } | Select-DefaultView -ExcludeProperty Query
                            } catch {
                                Write-Message -Level VeryVerbose -Message "$updatequery"
                                Stop-Function -Message "Error updating $($table.Schema).$($table.Name)" -Target $updatequery -Continue -ErrorRecord $_
                            }
                        }
                    } else {
                        Stop-Function -Message "Table $($table.Name) is not present" -Target $Database -Continue
                    }
                }
            }
        }
    }
}