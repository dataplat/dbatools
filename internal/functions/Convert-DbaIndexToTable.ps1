function Convert-DbaIndexToTable {
    [CmdLetBinding()]

    param(
        [DbaInstanceParameter]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [string[]]$Schema,
        [string[]]$Table,
        [string[]]$Index,
        [switch]$Unique,
        [switch]$EnableException
    )

    begin {
        # Some parameter checking
        if (-not $SqlInstance) {
            Stop-Function -Message "Please enter an instance" -Continue
        }

        # Get the database
        $db = Get-DbaDatabase -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database

        # Stringbuilder to get store all the queries
        $tableStatements = @()
    }

    process {
        if (Test-FunctionInterrupt) { return }

        # Filter all the schemas
        if ($Schema) {
            [array]$tables = $db.Tables | Where-Object { $_.Schema -in $Schema }
        } else {
            [array]$tables = $db.Tables
        }

        # Filter the tables
        if ($Table) {
            [array]$tables = $tables | Where-Object { $_.Name -in $Table }
        }

        # Loop through each of the tables
        foreach ($tableObject in $tables) {
            Write-Message -Message "Processing table [$($tableObject.Schema)].[$($tableObject.Name)]" -Level Verbose

            # Get the indexes
            if ($Unique) {
                [array]$indexes = $tableObject.Indexes | Where-Object { $_.IsUnique -eq $true }
            } else {
                [array]$indexes = $tableObject.Indexes
            }

            # Get the indexed columns
            [array]$indexedColumns = $indexes.IndexedColumns | Select-Object -ExpandProperty Name

            # Based on the indexed columns, get the actual column from the table object
            [array]$columns = $tableObject.Columns | Where-Object { $_.Name -in $indexedColumns -and $_.Identity -eq $false } | Select-Object -Unique

            $columnStatements = @()

            foreach ($columnObject in $columns) {
                # Check for user defined data types
                if ($columnObject.DataType.SqlDataType -eq 'UserDefinedDataType') {
                    $uddt = $db.UserDefinedDataTypes[$columnObject.DataType.Name]

                    [string]$dataType = $uddt.SystemType.ToLower().Trim()
                    [int]$length = $uddt.Length
                } else {
                    [string]$dataType = $columnObject.DataType.SqlDataType.ToString().ToLower()
                    [int]$length = $columnObject.DataType.MaximumLength
                }

                # Based on the data type create a different column statement
                switch ($dataType) {
                    { $_ -in "bigint", "date", "datetime", "datetime2", "smallint", "time", "tinyint" } {
                        $columnStatements += "[$($columnObject.Name)] [$dataType]"
                    }
                    { $_ -like "*char*" } {
                        $columnStatements += "[$($columnObject.Name)] [$dataType]($length)"
                    }
                    default {
                        $columnStatements += "[$($columnObject.Name)] [$dataType]"
                    }
                }
            }

            # Add the id in there
            $columnStatements += "[RowNr] [bigint]"

            # The query
            if ($columns.Count -ge 1) {
                [array]$columnNames = $columns.Name
                $columnNames += "RowNr"

                $tableStatements += [PSCustomObject]@{
                    Schema               = "$($tableObject.Schema)"
                    Table                = "$($tableObject.Name)"
                    Columns              = $columnNames
                    TempTableName        = "$($tableObject.Schema)_$($tableObject.Name)"
                    CreateStatement      = "CREATE TABLE $($tableObject.Schema)_$($tableObject.Name)($($columnStatements -join ","));"
                    UniqueIndexName      = "UIX_$($tableobject.Schema)_$($tableobject.Name)"
                    UniqueIndexStatement = "CREATE UNIQUE NONCLUSTERED INDEX [UIX_$($tableobject.Schema)_$($tableobject.Name)] ON $($tableObject.Schema)_$($tableObject.Name)([$($columnNames -join '],[')] ASC);"
                }
            }
        }
    }

    end {
        if (Test-FunctionInterrupt) { return }

        $tableStatements
    }
}