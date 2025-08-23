function Test-DbaDbDataGeneratorConfig {
    <#
    .SYNOPSIS
        Validates JSON configuration files used for generating realistic test data in SQL Server databases

    .DESCRIPTION
        Validates JSON configuration files created by New-DbaDbDataGeneratorConfig before using them with Invoke-DbaDbDataGenerator to populate tables with realistic fake data. The function performs comprehensive validation including checking for required column properties, verifying data types are supported, confirming masking types exist in the Bogus library, and validating subtypes are available.

        This validation step prevents runtime errors during data generation and helps catch configuration issues early in the test data creation workflow. Returns detailed error information for any invalid configurations, showing exactly which tables and columns have problems so you can fix them before attempting to generate data.

    .PARAMETER FilePath
        Specifies the path to the JSON configuration file created by New-DbaDbDataGeneratorConfig that needs validation.
        Use this to verify your data generation configuration before running Invoke-DbaDbDataGenerator to avoid runtime errors.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: DataGeneration
        Author: Sander Stad (@sqlstad), sqlstad.nl

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        Requires: sysadmin access on SQL Servers

    .LINK
        https://dbatools.io/Test-DbaDbDataGeneratorConfig

    .EXAMPLE
        Test-DbaDbDataGeneratorConfig -FilePath C:\temp\_datamasking\db1.json

        Test the configuration file
    #>

    [cmdletbinding()]
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
            Stop-Function -Message "Configuration file does not contain a type. This is either an older configuration or an invalid one. Please make sure that the json file contains '`"Type`": `"DataGenerationConfiguration`", '" -Target $json.Type
            return
        }

        if ($json.Type -ne "DataGenerationConfiguration") {
            Stop-Function -Message "Configuration file is not a valid data generation configuration. Type found '$($json.Type)'" -Target $json.Type
            return
        }

        $supportedDataTypes = 'bigint', 'bit', 'bool', 'char', 'date', 'datetime', 'datetime2', 'decimal', 'int', 'money', 'nchar', 'ntext', 'nvarchar', 'smalldatetime', 'text', 'time', 'uniqueidentifier', 'userdefineddatatype', 'varchar'

        $randomizerTypes = Get-DbaRandomizedType

        $requiredColumnProperties = 'CharacterString', 'ColumnType', 'Composite', 'ForeignKey', 'Identity', 'MaskingType', 'MaxValue', 'MinValue', 'Name', 'Nullable', 'SubType'
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
            }
        }

    } # End process


}