function Get-DbaRandomizedDataset {
    <#
    .SYNOPSIS
        This function will generate a random data set based on a template

    .DESCRIPTION
        Generates a random value based on a template.
        The templates standardized in the templates folder and can be used to generate a data set.
        There is also an option to point to a specific template

    .PARAMETER Template
        The name of the template to use.
        It will go through the default templates to see if it's present

    .PARAMETER TemplateFile
        File to use as a template

    .PARAMETER RandomizerSubType
        Subtype to use.

    .PARAMETER Rows
        Amount of rows to generate. Th default is 100.

    .PARAMETER Locale
        Set the local to enable certain settings in the masking. The default is 'en'

    .PARAMETER InputObject
        Accepts piped input from Get-DbaRandomizedDatasetTemplate

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