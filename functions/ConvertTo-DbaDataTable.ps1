function ConvertTo-DbaDataTable {
    <#
    .SYNOPSIS
        Creates a DataTable for an object.

    .DESCRIPTION
        Creates a DataTable based on an object's properties. This allows you to easily write to SQL Server tables.

        Thanks to Chad Miller, this is based on his script. https://gallery.technet.microsoft.com/scriptcenter/4208a159-a52e-4b99-83d4-8048468d29dd

        If the attempt to convert to data table fails, try the -Raw parameter for less accurate datatype detection.

    .PARAMETER InputObject
        The object to transform into a DataTable.

    .PARAMETER TimeSpanType
        Specifies the type to convert TimeSpan objects into. Default is 'TotalMilliseconds'. Valid options are: 'Ticks', 'TotalDays', 'TotalHours', 'TotalMinutes', 'TotalSeconds', 'TotalMilliseconds', and 'String'.

    .PARAMETER SizeType
        Specifies the type to convert DbaSize objects to. Default is 'Int64'. Valid options are 'Int32', 'Int64', and 'String'.

    .PARAMETER IgnoreNull
        If this switch is enabled, objects with null values will be ignored (empty rows will be added by default).

    .PARAMETER Raw
        If this switch is enabled, the DataTable will be created with strings. No attempt will be made to parse/determine data types.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: DataTable, Table, Data
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
            if (($type -eq 'System.TimeSpan') -or ($type -eq 'Sqlcollaborative.Dbatools.Utility.DbaTimeSpan') -or ($type -eq 'Sqlcollaborative.Dbatools.Utility.DbaTimeSpanPretty')) {
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
            } elseif ($type -eq 'Sqlcollaborative.Dbatools.Utility.Size') {
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
                [ValidateSet('Timespan', 'Size')]
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