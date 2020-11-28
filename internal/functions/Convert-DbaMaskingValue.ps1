function Convert-DbaMaskingValue {

    <#
    .SYNOPSIS
        Convert a value to a TSQL format that be used in queries

    .DESCRIPTION
        The command will take a value and with the data type return it in a format
        that can be used in queries.

        For instance, a value "this is text" with data type 'varchar' will be returned as
        'this is text' with the single quotes

        It returns an object with the following properties
        - OriginalValue
        - NewValue
        -DataType
        -ErrorMessage

    .PARAMETER Value
        The value to be converted

    .PARAMETER DataType
        Data type the value needs to be converted to

    .PARAMETER Nullable
        It's possible to send a null value. It will then be converted to 'NULL' for SQL Server

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Masking, DataMasking
        Author: Sander Stad (@sqlstad, sqlstad.nl)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Invoke-DbaDbDataMasking

    .EXAMPLE
        Convert-DbaMaskingValue -Value "please convert this" -DataType varchar

        Will convert ""please convert this" to "'please convert this'"

    .EXAMPLE
        Convert-DbaMaskingValue -Value $null -DataType varchar -Nullable

        Will convert null to "NULL"
    #>

    param(
        [Parameter(ValueFromPipeline)]
        [AllowEmptyString()]
        [object[]]$Value,
        [string]$DataType,
        [switch]$Nullable,
        [switch]$EnableException
    )

    begin {
        if (-not $Nullable -and -not $Value) {
            Stop-Function -Message "Please enter a value" -Target $Value -Continue
        }

        if (-not $Nullable -and -not $DataType) {
            Stop-Function -Message "Please enter a data type" -Target $DataType -Continue
        }

        if ($Value.Count -eq 0 -and $Nullable) {
            [PSCustomObject]@{
                OriginalValue = '$null'
                NewValue      = 'NULL'
                DataType      = $DataType
                ErrorMessage  = $null
            }
        }
    }

    process {
        if (Test-FunctionInterrupt) { return }

        foreach ($item in $Value) {

            $originalValue = $item

            [string]$newValue = $null
            [string]$errorMessage = $null

            if ($null -eq $item -or -not $item) {
                $originalValue = '$null'
                $newValue = "NULL"
            } elseif ($item -eq '') {
                $originalValue = ''

                if ($Nullable) {
                    $newValue = "NULL"
                } else {
                    $newValue = ""
                }
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
                        if (($item -match "(\d{4})-(\d{2})-(\d{2})") -or ($item -match "(\d{2})/(\d{2})/(\d{4})")) {
                            $item = ([datetime]$item).Tostring("yyyy-MM-dd HH:mm:ss.fff", [System.Globalization.CultureInfo]::InvariantCulture)
                            $newValue = "'$item'"
                        } else {
                            $errorMessage = "Value '$($item)' is not valid DATE or DATETIME format (yyyy-MM-dd)"
                        }
                    }
                    { $_ -eq 'datetime2' } {
                        if (($item -match "(\d{4})-(\d{2})-(\d{2})") -or ($item -match "(\d{2})/(\d{2})/(\d{4})")) {
                            $item = ([datetime]$item).Tostring("yyyy-MM-dd HH:mm:ss.fffffff", [System.Globalization.CultureInfo]::InvariantCulture)
                            $newValue = "'$item'"
                        } else {
                            $errorMessage = "Value '$($item)' is not valid DATE or DATETIME format (yyyy-MM-dd)"
                        }
                    }
                    { $_ -eq 'date' } {
                        if (($item -match "(\d{4})-(\d{2})-(\d{2})") -or ($item -match "(\d{2})/(\d{2})/(\d{4})")) {
                            $item = ([datetime]$item).Tostring("yyyy-MM-dd", [System.Globalization.CultureInfo]::InvariantCulture)
                            $newValue = "'$item'"
                        } else {
                            $errorMessage = "Value '$($item)' is not valid DATE or DATETIME format (yyyy-MM-dd)"
                        }
                    }
                    { $_ -like 'smalldatetime' } {
                        if (($item -match "(\d{4})-(\d{2})-(\d{2})") -or ($item -match "(\d{2})/(\d{2})/(\d{4})")) {
                            $item = ([datetime]$item).Tostring("yyyy-MM-dd HH:mm:ss", [System.Globalization.CultureInfo]::InvariantCulture)
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