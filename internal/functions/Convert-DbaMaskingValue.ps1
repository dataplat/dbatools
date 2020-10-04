function Convert-DbaMaskingValue {

    param(
        [Parameter(ValueFromPipeline)]
        [string[]]$Value,
        [string]$DataType,
        [switch]$Nullable
    )

    begin {
        if (-not $Value) {
            Stop-Function -Message "Please enter a value" -Target $Value
        }

        if (-not $DataType) {
            Stop-Function -Message "Please enter a data type" -Target $DataType
        }
    }

    process {
        if (Test-FunctionInterrupt) { return }

        foreach ($item in $Value) {

            $originalValue = $item

            [string]$newValue = $null
            [string]$errorMessage = $null

            if ( $null -eq $item -and $Nullable) {
                $newValue = "NULL"
            } else {
                switch ($DataType.ToLower()) {
                    { $_ -in 'bit', 'bool' } {
                        if ($item -match "([0-1])") {

                            $newValue = "$item"
                        } else {
                            $errorMessage = "Value '$($item)' is not valid BIT or BOOL"
                        }
                    }
                    { $_ -like '*int*' -or $_ -in 'decimal', 'numeric', 'float', 'money', 'smallmoney', 'real' } {
                        if ($item -match "\b\d+([\.,]\d+)?") {
                            $newValue = "$item"
                        } else {
                            $errorMessage = "Value '$($item)' is not valid integer/decimal format"
                        }
                    }
                    { $_ -in 'uniqueidentifier' } {
                        $newValue = "'$item'"
                    }
                    { $_ -eq 'datetime' } {
                        if ($item -match "(\d{4})-(\d{2})-(\d{2})") {
                            $item = ([datetime]$item).Tostring("yyyy-MM-dd HH:mm:ss.fff")
                            $newValue = "'$item'"
                        } else {
                            $errorMessage = "Value '$($item)' is not valid DATE or DATETIME format (yyyy-MM-dd)"
                        }
                    }
                    { $_ -eq 'datetime2' } {
                        if ($item -match "(\d{4})-(\d{2})-(\d{2})") {
                            $item = ([datetime]$item).Tostring("yyyy-MM-dd HH:mm:ss.fffffff")
                            $newValue = "'$item'"
                        } else {
                            $errorMessage = "Value '$($item)' is not valid DATE or DATETIME format (yyyy-MM-dd)"
                        }
                    }
                    { $_ -eq 'date' } {
                        if ($item -match "(\d{4})-(\d{2})-(\d{2})") {
                            $item = ([datetime]$item).Tostring("yyyy-MM-dd")
                            $newValue = "'$item'"
                        } else {
                            $errorMessage = "Value '$($item)' is not valid DATE or DATETIME format (yyyy-MM-dd)"
                        }
                    }
                    { $_ -like 'smalldatetime' } {
                        if ($item -match "(\d{4})-(\d{2})-(\d{2})") {
                            $item = ([datetime]$item).Tostring("yyyy-MM-dd HH:mm:ss")
                            $newValue = "'$item'"
                        } else {
                            $errorMessage = "Value '$($item)' is not valid DATE or DATETIME format (yyyy-MM-dd)"
                        }
                    }
                    { $_ -eq 'time' } {
                        if ($item -match "(\d{2}):(\d{2}):(\d{2})") {
                            $item = ([datetime]$item).Tostring("HH:mm:ss.fffffff")
                            $newValue = "'$item'"
                        } else {
                            $errorMessage = "Value '$($item)' is not valid TIME format (HH:mm:ss)"
                        }
                    }
                    { $_ -eq 'xml' } {
                        # nothing, unsure how i'll handle this
                    }
                    default {
                        $item = ($item).Tostring().Replace("'", "''")
                        $newValue = "'$item'"
                    }
                }
            }

            [PSCustomObject]@{
                OriginalValue = $originalValue
                NewValue      = $newValue
                DataType      = $DataType
                ErrorMessage  = $errorMessage
            }
        }
    }
}