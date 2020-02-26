function Test-DbaDbDataMaskingConfig {
    <#
    .SYNOPSIS
        Checks the masking configuration if it's valid

    .DESCRIPTION
        When you're dealing with large masking configurations, things can get complicated and messy.
        This function will test for a range of rules and returns all the tables and columns that contain errors.

    .PARAMETER FilePath
        Path to the file to test

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER Force
        If this switch is enabled, existing objects on Destination with matching names from Source will be dropped.

    .NOTES
        Tags: Masking, DataMasking
        Author: Sander Stad (@sqlstad), sqlstad.nl

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        Requires: sysadmin access on SQL Servers

    .LINK
        https://dbatools.io/Test-DbaDbDataMaskingConfig

    .EXAMPLE
        Test-DbaDbDataMaskingConfig -FilePath C:\temp\_datamasking\db1.json

        Test the configuration file
    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory)]
        [string]$FilePath,
        [switch]$EnableException
    )
    begin {
        if (-not (Test-Path -Path $FilePath)) {
            Stop-Function -Message "Could not find masking config file $FilePath" -Target $FilePath
            return
        }

        # Get all the items that should be processed
        try {
            $json = Get-Content -Path $FilePath -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        } catch {
            Stop-Function -Message "Could not parse masking config file" -ErrorRecord $_ -Target $FilePath
        }

        if (-not $json.Type) {
            Stop-Function -Message "Configuration file does not contain a type. This is either an older configuration or an invalid one. Please make sure that the json file contains '`"Type`": `"DataMaskingConfiguration`", '" -Target $json.Type
            return
        }

        if ($json.Type -ne "DataMaskingConfiguration") {
            Stop-Function -Message "Configuration file is not a valid masking configuration. Type found '$($json.Type)'" -Target $json.Type
            return
        }

        $supportedDataTypes = 'bigint', 'bit', 'bool', 'char', 'date', 'datetime', 'datetime2', 'decimal', 'int', 'money', 'nchar', 'ntext', 'nvarchar', 'smalldatetime', 'smallint', 'text', 'time', 'uniqueidentifier', 'userdefineddatatype', 'varchar'

        $randomizerTypes = Get-DbaRandomizedType

        $requiredColumnProperties = 'CharacterString', 'ColumnType', 'Composite', 'Deterministic', 'Format', 'MaskingType', 'MaxValue', 'MinValue', 'Name', 'Nullable', 'KeepNull', 'SubType'
    }
    process {
        if (Test-FunctionInterrupt) { return }

        foreach ($table in $json.Tables) {

            foreach ($column in $table.Columns) {

                # Test the column properties
                $columnProperties = $column | Get-Member | Where-Object MemberType -eq NoteProperty | Select-Object Name -ExpandProperty Name
                $compareResult = Compare-Object -ReferenceObject $requiredColumnProperties -DifferenceObject $columnProperties

                if ($null -ne $compareResult) {
                    if ($compareResult.SideIndicator -contains "<=") {
                        [PSCustomObject]@{
                            Table  = $table.Name
                            Column = $column.Name
                            Value  = ($compareResult | Where-Object SideIndicator -eq "<=").InputObject -join ","
                            Error  = "The column does not contain all the required properties. Please check the column "
                        }
                    }

                    if ($compareResult.SideIndicator -contains "=>") {
                        [PSCustomObject]@{
                            Table  = $table.Name
                            Column = $column.Name
                            Value  = ($compareResult | Where-Object SideIndicator -eq "=>").InputObject -join ","
                            Error  = "The column contains a property that is not in the required properties. Please check the column"
                        }
                    }
                }

                # Test column type
                if ($column.ColumnType -notin $supportedDataTypes) {
                    [PSCustomObject]@{
                        Table  = $table.Name
                        Column = $column.Name
                        Value  = $column.ColumnType
                        Error  = "ColumnType is not a supported data type "
                    }
                }

                # Test masking type
                if ($column.MaskingType -notin $randomizerTypes.Type) {
                    [PSCustomObject]@{
                        Table  = $table.Name
                        Column = $column.Name
                        Value  = $column.MaskingType
                        Error  = "MaskingType is not valid"
                    }
                }

                # Test masking sub type
                if ($null -ne $column.SubType -and $column.SubType -notin $randomizerTypes.SubType) {
                    [PSCustomObject]@{
                        Table  = $table.Name
                        Column = $column.Name
                        Value  = $column.SubType
                        Error  = "SubType is not valid"
                    }
                }

                # Test date types
                if ($column.ColumnType.ToLower() -eq 'date') {

                    if ($column.MaskingType -ne 'Date' -and ($column.SubType -ne 'DateOfBirth' -and $null -ne $column.Subtype)) {
                        [PSCustomObject]@{
                            Table  = $table.Name
                            Column = $column.Name
                            Value  = $column.MaskingType
                            Error  = "MaskingType should be date when ColumnType is 'date'"
                        }
                    }

                    if ($null -ne $Column.SubType -and $Column.SubType.ToLower() -eq 'between') {

                        if (-not ($null -eq $column.MinValue) -and -not ([datetime]::TryParse($column.MinValue, [ref]"2002-12-31"))) {
                            [PSCustomObject]@{
                                Table  = $table.Name
                                Column = $column.Name
                                Value  = $column.MinValue
                                Error  = "The value for MinValue is not a valid date"
                            }
                        }

                        if (-not ($null -eq $column.MaxValue) -and -not ([datetime]::TryParse($column.MaxValue, [ref]"2002-12-31"))) {
                            [PSCustomObject]@{
                                Table  = $table.Name
                                Column = $column.Name
                                Value  = $column.MaxValue
                                Error  = "The value for MaxValue is not a valid date"
                            }
                        }

                        if ($null -eq $column.MinValue) {
                            [PSCustomObject]@{
                                Table  = $table.Name
                                Column = $column.Name
                                Value  = 'null'
                                Error  = "The value for MinValue cannot be 'null' when using sub type 'Between'"
                            }
                        }

                        if ($null -eq $column.MaxValue) {
                            [PSCustomObject]@{
                                Table  = $table.Name
                                Column = $column.Name
                                Value  = 'null'
                                Error  = "The value for MaxValue cannot be 'null' when using sub type 'Between'"
                            }
                        }
                    }
                }
            }
        }
    }
}