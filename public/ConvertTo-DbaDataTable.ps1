function ConvertTo-DbaDataTable {
    <#
    .SYNOPSIS
        Converts PowerShell objects into .NET DataTable objects for bulk SQL Server operations

    .DESCRIPTION
        Converts PowerShell objects into .NET DataTable objects with proper column types and database-compatible data formatting. This is essential for bulk operations like importing data into SQL Server tables using Write-DbaDataTable or other bulk insert methods.

        The function automatically detects and converts data types to SQL Server-compatible formats, handling special dbatools types like DbaSize (file sizes) and DbaTimeSpan objects. You can control how these special types are converted - for example, converting TimeSpan objects to total milliseconds, seconds, or string representations.

        Common scenarios include taking results from Get-DbaDatabase, Get-DbaBackupHistory, or other dbatools commands and preparing them for storage in custom reporting tables. The function handles complex object arrays, null values, and provides both strongly-typed and raw string conversion modes.

        Thanks to Chad Miller, this is based on his script. https://gallery.technet.microsoft.com/scriptcenter/4208a159-a52e-4b99-83d4-8048468d29dd

        If the attempt to convert to data table fails, try the -Raw parameter for less accurate datatype detection.

    .PARAMETER InputObject
        PowerShell objects to convert into a DataTable with proper SQL Server-compatible column types.
        Accepts results from dbatools commands like Get-DbaDatabase, Get-DbaBackupHistory, or any PowerShell object array.
        Handles complex properties, arrays, and dbatools-specific types like DbaSize and DbaTimeSpan automatically.

    .PARAMETER TimeSpanType
        Controls how TimeSpan and DbaTimeSpan objects are converted for database storage.
        Use 'TotalMilliseconds' (default) for precise timing data, 'TotalSeconds' for general duration tracking, or 'String' to preserve readable format.
        Common when converting backup duration, job runtime, or database uptime data for reporting tables.

    .PARAMETER SizeType
        Controls how DbaSize objects (file sizes, database sizes) are converted for database storage.
        Use 'Int64' (default) for precise byte values suitable for calculations, 'Int32' for smaller datasets, or 'String' to preserve human-readable format like '1.5 GB'.
        Essential when storing database size reports, backup file information, or disk space data.

    .PARAMETER IgnoreNull
        Excludes null objects from the DataTable instead of creating empty rows.
        Use this when preparing clean datasets for bulk insert operations where empty rows would cause issues.
        Helpful when processing filtered results that may contain null entries from failed connections or missing databases.

    .PARAMETER Raw
        Forces all DataTable columns to be strings instead of detecting proper data types.
        Use this as a fallback when automatic type detection fails or when you need maximum compatibility with target tables that expect string data.
        Trades type safety for reliability when dealing with complex or problematic object properties.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Table, Data
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io/
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/ConvertTo-DbaDataTable

    .OUTPUTS
        System.Object[]

    .EXAMPLE
        PS C:\> Get-Service | ConvertTo-DbaDataTable

        Creates a DataTable from the output of Get-Service.

    .EXAMPLE
        PS C:\> ConvertTo-DbaDataTable -InputObject $csv.cheesetypes

        Creates a DataTable from the CSV object $csv.cheesetypes.

    .EXAMPLE
        PS C:\> $dblist | ConvertTo-DbaDataTable

        Creates a DataTable from the $dblist object passed in via pipeline.

    .EXAMPLE
        PS C:\> Get-Process | ConvertTo-DbaDataTable -TimeSpanType TotalSeconds

        Creates a DataTable with the running processes and converts any TimeSpan property to TotalSeconds.

    #>
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseOutputTypeCorrectly", "", Justification = "PSSA Rule Ignored by BOH")]
    [OutputType([System.Object[]])]
    param (
        [Parameter(Position = 0,
            Mandatory,
            ValueFromPipeline)]
        [AllowNull()]
        [PSObject[]]$InputObject,
        [ValidateSet("Ticks",
            "TotalDays",
            "TotalHours",
            "TotalMinutes",
            "TotalSeconds",
            "TotalMilliseconds",
            "String")]
        [ValidateNotNullOrEmpty()]
        [string]$TimeSpanType = "TotalMilliseconds",
        [ValidateSet("Int64", "Int32", "String")]
        [string]$SizeType = "Int64",
        [switch]$IgnoreNull,
        [switch]$Raw,
        [switch]$EnableException
    )

    begin {
        Write-Message -Level Debug -Message "Bound parameters: $($PSBoundParameters.Keys -join ", ")"
        Write-Message -Level Debug -Message "TimeSpanType = $TimeSpanType | SizeType = $SizeType"

        function Convert-Type {
            # This function will check so that the type is an accepted type which could be used when inserting into a table.
            # If a type is accepted (included in the $type array) then it will be passed on, otherwise it will first change type before passing it on.
            # Special types will have both their types converted as well as the value.
            # TimeSpan is a special type and will be converted into the $timespantype. (default: TotalMilliseconds) so that the timespan can be stored in a database further down the line.
            [CmdletBinding()]
            param (
                $type,
                $value,
                $timespantype = 'TotalMilliseconds',
                $sizetype = 'Int64'
            )

            $types = [System.Collections.ArrayList]@(
                'System.Int32',
                'System.UInt32',
                'System.Int16',
                'System.UInt16',
                'System.Int64',
                'System.UInt64',
                'System.Decimal',
                'System.Single',
                'System.Double',
                'System.Byte',
                'System.Byte[]',
                'System.SByte',
                'System.Boolean',
                'System.DateTime',
                'System.Guid',
                'System.Char'
            )

            # The $special variable is used to mark the return value if a conversion was made on the value itself.
            # If this is set to true the original value will later be ignored when updating the DataTable.
            # And the value returned from this function will be used instead. (cannot modify existing properties)
            $special = $false
            $specialType = ""

            # Special types need to be converted in some way.
            # This attempt is to convert timespan into something that works in a table.
            # I couldn't decide on what to convert it to so the user can decide.
            # If the parameter is not used, TotalMilliseconds will be used as default.
            # Ticks are more accurate but I think milliseconds are more useful most of the time.
            if (($type -eq 'System.TimeSpan') -or ($type -eq 'Dataplat.Dbatools.Utility.DbaTimeSpan') -or ($type -eq 'Dataplat.Dbatools.Utility.DbaTimeSpanPretty')) {
                $special = $true
                if ($timespantype -eq 'String') {
                    $value = $value.ToString()
                    $type = 'System.String'
                } else {
                    # Let's use Int64 for all other types than string.
                    # We could match the type more closely with the timespantype but that can be added in the future if needed.
                    $value = $value.$timespantype
                    $type = 'System.Int64'
                }
                $specialType = 'Timespan'
            } elseif ($type -eq 'Dataplat.Dbatools.Utility.Size') {
                $special = $true
                switch ($sizetype) {
                    'Int64' {
                        $value = $value.Byte
                        $type = 'System.Int64'
                    }
                    'Int32' {
                        $value = $value.Byte
                        $type = 'System.Int32'
                    }
                    'String' {
                        $value = $value.ToString()
                        $type = 'System.String'
                    }
                }
                $specialType = 'Size'
            } elseif ($type -eq 'Dataplat.Dbatools.Utility.DbaDateTime[]') {
                if (-not ($null -eq $value)) {
                    $special = $true
                    $value = $value
                    $type = 'System.String'
                    $specialType = 'String'
                }
            } elseif (-not ($type -in $types)) {
                # All types which are not found in the array will be converted into strings.
                # In this way we don't ignore it completely and it will be clear in the end why it looks as it does.
                $type = 'System.String'
            }

            # return a hashtable instead of an object. I like hashtables :)
            return @{ type = $type; Value = $value; Special = $special; SpecialType = $specialType }
        }

        function Convert-SpecialType {
            <#
            .SYNOPSIS
                Converts a value for a known column.

            .DESCRIPTION
                Converts a value for a known column.

            .PARAMETER Value
                The value to convert

            .PARAMETER Type
                The special type for which to convert

            .PARAMETER SizeType
                The size type defined by the user

            .PARAMETER TimeSpanType
                The timespan type defined by the user
        #>
            [CmdletBinding()]
            param (
                $Value,
                [ValidateSet('Timespan', 'Size', 'DateTime', 'String')]
                [string]$Type,
                [string]$SizeType,
                [string]$TimeSpanType
            )

            switch ($Type) {
                'Size' {
                    if ($SizeType -eq 'String') { return $Value.ToString() }
                    else { return $Value.Byte }
                }
                'Timespan' {
                    if ($TimeSpanType -eq 'String') {
                        $Value.ToString()
                    } else {
                        $Value.$TimeSpanType
                    }
                }
                'DateTime' {
                    return [System.DateTime]$Value.DateTime
                }
                'String' {
                    return ($Value | ForEach-Object { $_.ToString() }) -Join ', '
                }
            }
        }

        function Add-Column {
            <#
            .SYNOPSIS
                Adds a column to the datatable in progress.

            .DESCRIPTION
                Adds a column to the datatable in progress.

            .PARAMETER Property
                The property for which to add a column.

            .PARAMETER DataTable
                Autofilled. The table for which to add a column.

            .PARAMETER TimeSpanType
                Autofilled. How should timespans be handled?

            .PARAMETER SizeType
                Autofilled. How should sizes be handled?

            .PARAMETER Raw
                Autofilled. Whether the column should be string, no matter the input.
        #>
            [CmdletBinding()]
            param (
                [System.Management.Automation.PSPropertyInfo]$Property,
                [System.Data.DataTable]$DataTable = $datatable,
                [string]$TimeSpanType = $TimeSpanType,
                [string]$SizeType = $SizeType,
                [bool]$Raw = $Raw
            )

            $type = $property.TypeNameOfValue
            try {
                if ($Property.MemberType -like 'ScriptProperty') {
                    $type = $Property.GetType().FullName
                }
            } catch { $type = 'System.String' }

            $converted = Convert-Type -type $type -value $property.Value -timespantype $TimeSpanType -sizetype $SizeType

            $column = New-Object System.Data.DataColumn
            $column.ColumnName = $property.Name.ToString()
            if (-not $Raw) {
                $column.DataType = [System.Type]::GetType($converted.type)
            }
            $null = $DataTable.Columns.Add($column)
            $converted
        }

        $datatable = New-Object System.Data.DataTable

        # Accelerate subsequent lookups of columns and special type columns
        $columns = @()
        $specialColumns = @()
        $specialColumnsType = @{ }

        $ShouldCreateColumns = $true
    }

    process {
        #region Handle null objects
        if ($null -eq $InputObject) {
            if (-not $IgnoreNull) {
                $datarow = $datatable.NewRow()
                $datatable.Rows.Add($datarow)
            }

            # Only ends the current process block
            return
        }
        #endregion Handle null objects


        foreach ($object in $InputObject) {
            #region Handle null objects
            if ($null -eq $object) {
                if (-not $IgnoreNull) {
                    $datarow = $datatable.NewRow()
                    $datatable.Rows.Add($datarow)
                }
                continue
            }
            #endregion Handle null objects

            #Handle rows already being System.Data.DataRow
            if ($object.GetType().FullName -eq 'System.Data.DataRow') {
                $datatable.Merge($object.Table)
                $datatable = $datatable.DefaultView.ToTable($true)
                continue
            }

            # The new row to insert
            $datarow = $datatable.NewRow()

            #region Process Properties
            $objectProperties = $object.PSObject.Properties
            foreach ($property in $objectProperties) {
                #region Create Columns as needed
                if ($ShouldCreateColumns) {
                    $newColumn = Add-Column -Property $property
                    $columns += $property.Name
                    if ($newColumn.Special) {
                        $specialColumns += $property.Name
                        $specialColumnsType[$property.Name] = $newColumn.SpecialType
                    }
                }
                #endregion Create Columns as needed

                # Handle null properties, as well as properties with access errors
                try {
                    $propValueLength = $property.value.length
                } catch {
                    $propValueLength = 0
                }

                #region Insert value into column of row
                if ($propValueLength -gt 0) {
                    # If the typename was a special typename we want to use the value returned from Convert-Type instead.
                    # We might get error if we try to change the value for $property.value if it is read-only. That's why we use $converted.value instead.
                    if ($property.Name -in $specialColumns) {
                        $datarow.Item($property.Name) = Convert-SpecialType -Value $property.value -Type $specialColumnsType[$property.Name] -SizeType $SizeType -TimeSpanType $TimeSpanType
                    } else {
                        if ($property.value.ToString().length -eq 15) {
                            if ($property.value.ToString() -eq 'System.Object[]') {
                                $value = $property.value -join ", "
                            } elseif ($property.value.ToString() -eq 'System.String[]') {
                                $value = $property.value -join ", "
                            } else {
                                $value = $property.value
                            }
                        } else {
                            $value = $property.value
                        }

                        try {
                            $datarow.Item($property.Name) = $value
                        } catch {
                            if ($property.Name -notin $columns) {
                                try {
                                    $newColumn = Add-Column -Property $property
                                    $columns += $property.Name
                                    if ($newColumn.Special) {
                                        $specialColumns += $property.Name
                                        $specialColumnsType[$property.Name] = $newColumn.SpecialType
                                    }

                                    $datarow.Item($property.Name) = $newColumn.Value
                                } catch {
                                    Stop-Function -Message "Failed to add property $($property.Name) from $object" -ErrorRecord $_ -Target $object
                                }
                            } else {
                                Stop-Function -Message "Failed to add property $($property.Name) from $object" -ErrorRecord $_ -Target $object
                            }
                        }
                    }
                }
                #endregion Insert value into column of row
            }

            $datatable.Rows.Add($datarow)
            # If this is the first non-null object then the columns has just been created.
            # Set variable to false to skip creating columns from now on.
            if ($ShouldCreateColumns) {
                $ShouldCreateColumns = $false
            }
            #endregion Process Properties
        }
    }
    end {
        Write-Message -Level InternalComment -Message "Finished."
        , $datatable
    }
}