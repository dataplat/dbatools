#nullable enable

namespace Dataplat.Dbatools.Commands;

// Process-body part 3 (see ProcessScript partial).
public sealed partial class InvokeDbaDbDataMaskingCommand
{
    private const string ProcessScriptPart3 = """
                                }

                                Invoke-DbaDbDataMasking $progressParams
                            }

                            # Create array to hold all column updates for this row
                            $updates = @()

                            # Process all standard columns for this row
                            foreach ($columnobject in $standardColumns) {
                                $newValue = $null

                                # Handle static values
                                if ($null -ne $columnobject.StaticValue) {
                                    $newValue = $columnobject.StaticValue

                                    if ($null -eq $newValue -and -not $columnobject.Nullable) {
                                        Write-Message -Message "Column '$($columnobject.Name)' static value cannot be null when column is set not to be nullable." -Level Warning -FunctionName Invoke-DbaDbDataMasking -ModuleName "dbatools"
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
                                        Stop-Function -Message "Something went wrong getting the unique data" -Target $query -ErrorRecord $_ -continue -FunctionName Invoke-DbaDbDataMasking
                                    }

                                    if ($null -eq $uniqueData) {
                                        Stop-Function -Message "Could not find any unique values" -Target $tableobject -FunctionName Invoke-DbaDbDataMasking
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
                                                Stop-Function "Could not convert the value. $($convertedValue.ErrorMessage)" -Target $convertedValue -continue -FunctionName Invoke-DbaDbDataMasking
                                            }
                                        } catch {
                                            Stop-Function -Message "Could not convert value" -ErrorRecord $_ -Target $row.($columnobject.Name) -continue -FunctionName Invoke-DbaDbDataMasking
                                        }

                                        $query = "SELECT [NewValue] FROM dbo.DeterministicValues WHERE [ValueKey] = $($lookupValue.NewValue)"

                                        try {
                                            $lookupResult = $null
                                            $lookupResult = $server.Databases['tempdb'].Query($query)

                                            if ($lookupResult.NewValue) {
                                                $newValue = $lookupResult.NewValue
                                            }
                                        } catch {
                                            Stop-Function -Message "Something went wrong retrieving the deterministic values" -Target $query -ErrorRecord $_ -continue -FunctionName Invoke-DbaDbDataMasking
                                        }
                                    }
                                }

                                # If we haven't determined a value yet, generate one
                                if ($null -eq $newValue -and $null -eq $columnobject.StaticValue) {
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

                                    if (-not $columnobject.MaxValue -and -not $__boundMaxValue) {
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
                                        Stop-Function -Message "Failure" -Target $columnobject -Continue -ErrorRecord $_ -FunctionName Invoke-DbaDbDataMasking
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
                                        Stop-Function "Could not convert the value. $($convertedValue.ErrorMessage)" -Target $convertedValue -continue -FunctionName Invoke-DbaDbDataMasking
                                    }
                                } catch {
                                    Stop-Function -Message "Could not convert value" -ErrorRecord $_ -Target $newValue -continue -FunctionName Invoke-DbaDbDataMasking
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
                                            Stop-Function "Could not convert the value. $($convertedValue.ErrorMessage)" -Target $convertedValue -FunctionName Invoke-DbaDbDataMasking
                                            continue
                                        }

                                        $query = "INSERT INTO dbo.DeterministicValues (ValueKey, NewValue) VALUES ($($previous.NewValue), $($convertedValue.NewValue));"
                                        $null = $server.Databases['tempdb'].Query($query)
                                    } catch {
                                        Stop-Function -Message "Could not save deterministic value.`n$_" -Target $query -ErrorRecord $_ -FunctionName Invoke-DbaDbDataMasking
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

                                        Invoke-DbaDbDataMasking $progressParams

                                        Write-Message -Level Verbose -Message "Executing batch $batchNr/$totalBatches" -FunctionName Invoke-DbaDbDataMasking -ModuleName "dbatools"

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
                                        Stop-Function -Message "Error updating $($tableobject.Schema).$($tableobject.Name): $_ `n$($stringBuilder.ToString())" -Target $stringBuilder.ToString() -Continue -ErrorRecord $_ -FunctionName Invoke-DbaDbDataMasking
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
                                Write-Message -Level Verbose -Message "Processing action for [$($columnObject.Name)]" -FunctionName Invoke-DbaDbDataMasking -ModuleName "dbatools"

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
                                # Apply actions only to the rows returned by FilterQuery
                                if ($validAction -and $tableobject.FilterQuery -and $actionIdentityValues.Count -ge 1) {
                                    for ($batchStart = 0; $batchStart -lt $actionIdentityValues.Count; $batchStart += $BatchSize) {
                                        $batchEnd = [System.Math]::Min($batchStart + $BatchSize - 1, $actionIdentityValues.Count - 1)
                                        $identityBatch = $actionIdentityValues[$batchStart .. $batchEnd] -join ", "
                                        $null = $stringBuilder.AppendLine($query.TrimEnd(";") + " WHERE [$identityColumn] IN ($identityBatch);")
                                    }
                                }

                                # Add the query to the rest
""";
}
