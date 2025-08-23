function Get-DbaRandomizedDataset {
    <#
    .SYNOPSIS
        Generates random test data using predefined templates for development and testing scenarios

    .DESCRIPTION
        Generates random test datasets using JSON templates that define column names and data types. This function creates realistic sample data for database development, testing, and training environments without exposing production data. Templates can specify SQL Server data types (varchar, int, datetime) or semantic data types (Name.FirstName, Address.City, Person.DateOfBirth) for more realistic datasets. Built-in templates include PersonalData with common PII fields, and you can create custom templates for specific business scenarios.

    .PARAMETER Template
        Specifies the name of one or more built-in templates to use for data generation.
        Use this when you want to generate data using predefined column structures like PersonalData which includes names, addresses, and birthdates.
        The function searches through default templates in the module's bin\randomizer\templates directory to find matching names.

    .PARAMETER TemplateFile
        Specifies the full path to one or more custom JSON template files that define column structures and data types.
        Use this when you need to generate data based on your own custom templates rather than the built-in ones.
        Template files must be valid JSON with a Columns array defining Name, Type, and SubType properties for each column.

    .PARAMETER RandomizerSubType
        This parameter is not used in the current function implementation.
        The randomizer subtypes are defined within the template files themselves for each column.

    .PARAMETER Rows
        Specifies how many rows of test data to generate for each template.
        Use this to control the size of your test dataset based on your development or testing needs.
        Defaults to 100 rows if not specified.

    .PARAMETER Locale
        Specifies the locale for generating culture-specific data like names, addresses, and phone numbers.
        Use this when you need test data that matches a specific geographic region or language for realistic testing scenarios.
        Defaults to 'en' (English) if not specified.

    .PARAMETER InputObject
        Accepts template objects piped from Get-DbaRandomizedDatasetTemplate.
        Use this in pipeline scenarios where you first retrieve templates and then generate data from them.
        Each input object should contain template information including the FullName path to the JSON template file.

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
        Author: Sander Stad (@sqlstad, sqlstad.nl)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaRandomizedDataset

    .EXAMPLE
        Get-DbaRandomizedDataset -Template Personaldata

        Generate a data set based on the default template PersonalData.

    .EXAMPLE
        Get-DbaRandomizedDataset -Template Personaldata -Rows 10

        Generate a data set based on the default template PersonalData with 10 rows

    .EXAMPLE
        Get-DbaRandomizedDataset -TemplateFile C:\Dataset\FinancialData.json

        Generates data set based on a template file in another directory

    .EXAMPLE
        Get-DbaRandomizedDataset -Template Personaldata, FinancialData

        Generates multiple data sets

    .EXAMPLE
        Get-DbaRandomizedDatasetTemplate -Template PersonalData | Get-DbaRandomizedDataset

        Pipe the templates from Get-DbaRandomizedDatasetTemplate to Get-DbaRandomizedDataset and generate the data set
    #>
    [CmdLetBinding()]
    param(
        [string[]]$Template,
        [string[]]$TemplateFile,
        [int]$Rows = 100,
        [string]$Locale = 'en',
        [parameter(ValueFromPipeline)]
        [object[]]$InputObject,
        [switch]$EnableException
    )

    process {
        if (Test-FunctionInterrupt) { return }

        $supportedDataTypes = 'bigint', 'bit', 'bool', 'char', 'date', 'datetime', 'datetime2', 'decimal', 'int', 'float', 'guid', 'money', 'numeric', 'nchar', 'ntext', 'nvarchar', 'real', 'smalldatetime', 'smallint', 'text', 'time', 'tinyint', 'uniqueidentifier', 'userdefineddatatype', 'varchar'

        # Check variables
        if (-not $InputObject -and -not $Template -and -not $TemplateFile) {
            Stop-Function -Message "Please enter a template or assign a template file" -Continue
        }

        $templates = @()

        # Get all thee templates
        if ($Template) {
            $templates += Get-DbaRandomizedDatasetTemplate -Template $Template

            if ($templates.Count -lt 1) {
                Stop-Function -Message "Could not find any templates" -Continue
            }

            $InputObject += $templates
        }

        foreach ($file in $InputObject) {
            # Get all the items that should be processed
            try {
                $templateSet = Get-Content -Path $file.FullName -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            } catch {
                Stop-Function -Message "Could not parse template file" -ErrorRecord $_ -Target $TemplateFile
                return
            }

            # Generate the rows
            for ($i = 1; $i -le $Rows; $i++) {
                $row = New-Object PSCustomObject

                foreach ($column in $templateSet.Columns) {
                    try {
                        if ($column.SubType -in $supportedDataTypes) {
                            $value = Get-DbaRandomizedValue -DataType $column.SubType -Locale $Locale -EnableException
                        } else {
                            $value = Get-DbaRandomizedValue -RandomizerType $column.Type -RandomizerSubtype $column.SubType -Locale $Locale -EnableException
                        }

                        $row | Add-Member -Name $column.Name -Type NoteProperty -Value $value
                    } catch {
                        Stop-Function -Message "Could not generate a randomized value.`n$_" -ErrorRecord $_ -Continue
                    }
                }

                $row

            }
        }

    }
}