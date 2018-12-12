function Invoke-DbaDbDataMasking {
    <#
    .SYNOPSIS
        Invoke-DbaDbDataMasking generates random data for tables

    .DESCRIPTION
        Invoke-DbaDbDataMasking is able to generate random data for tables.
        It will use a configuration file that can be made manually or generated using New-PSDCMaskingConfiguration

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
        [string]$Query,
        [switch]$Force,
        [switch]$EnableException
    )
    begin {
        # Set defaults
        $charString = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'

        # Create the faker objects
        Add-Type -Path (Resolve-Path -Path "$script:PSModuleRoot\bin\datamasking\Bogus.dll")
        $faker = New-Object Bogus.Faker($Locale)
    }

    process {
        if (Test-FunctionInterrupt) {
            return
        }

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
                            # Loop thorough the columns
                            foreach ($column in $table.Columns) {
                                $newValue = switch ($column.MaskingType.ToLower()) {
                                    { $_ -in 'name', 'address', 'finance' } {
                                        $faker.$($column.MaskingType).$($column.SubType)()
                                    }
                                    { $_ -in 'date', 'datetime', 'datetime2', 'smalldatetime' } {
                                        ($faker.Date.Past()).ToString("yyyyMMdd")
                                    }
                                    "number" {
                                        $faker.$($column.MaskingType).$($column.SubType)($column.MaxLength)
                                    }
                                    "shuffle" {
                                        ($row.($column.Name) -split '' | Sort-Object {
                                                Get-Random
                                            }) -join ''
                                    }
                                    "string" {
                                        $faker.$($column.MaskingType).String2($column.MaxLength, $charString)
                                    }
                                    default {
                                        if (-not $column.MaxLength) {
                                            $column.MaxLength = 10
                                        }
                                        if ($column.ColumnType -in 'date', 'datetime', 'datetime2', 'smalldatetime') {
                                            ($faker.Date.Past()).ToString("yyyyMMdd")
                                        } else {
                                            $faker.Random.String2(1, $column.MaxLength, $charString)
                                        }

                                    }
                                }

                                $oldValue = ($row.$($column.Name)).Tostring().Replace("'", "''")
                                $newValue = ($newValue).Tostring().Replace("'", "''")

                                $updates += "[$($column.Name)] = '$newValue'"
                                $wheres += "[$($column.Name)] = '$oldValue'"
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
                                }
                            } catch {
                                Stop-Function -Message "Could not execute the query: $updatequery" -Target $updatequery -Continue
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