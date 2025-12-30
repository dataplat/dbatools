function Get-DbaRandomizedDatasetTemplate {
    <#
    .SYNOPSIS
        Retrieves JSON template files that define column structures for generating realistic test data

    .DESCRIPTION
        Retrieves JSON template files from default and custom directories that define how to generate realistic test datasets. These templates specify column names, data types, and semantic subtypes (like Name.FirstName, Address.City) for creating structured sample data for development and testing environments. The default templates include PersonalData with common fields like names, addresses, and birthdates, and you can specify custom template directories to include organization-specific data patterns.

    .PARAMETER Template
        Specifies which template files to retrieve by name (without the .json extension).
        Use this to filter results when you only need specific templates like "PersonalData" or custom templates.
        If not specified, all available templates from the specified paths are returned.

    .PARAMETER Path
        Specifies one or more directory paths containing custom JSON template files for data generation.
        Use this when your organization has created custom templates beyond the default dbatools templates.
        Templates from these paths are added to the default templates unless -ExcludeDefault is specified.

    .PARAMETER ExcludeDefault
        Excludes the built-in dbatools templates from the results.
        Use this when you only want to work with custom templates from specified paths.
        The default templates include common data patterns like PersonalData with names, addresses, and dates.

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
        https://dbatools.io/Get-DbaRandomizedDatasetTemplate

    .OUTPUTS
        PSCustomObject

        Returns one object per available template file. Each object contains information about a single template that can be used with Get-DbaRandomizedDataset to generate test data.

        Properties:
        - BaseName: The template name without the .json extension (string)
        - FullName: The complete file path to the JSON template file (string)

        When called without filters, returns all templates from the default dbatools templates directory. When -Path is specified, also includes templates from custom directories. The -Template parameter filters results to only matching template names. The -ExcludeDefault switch excludes built-in templates and only returns custom templates from specified paths.

    .EXAMPLE
        Get-DbaRandomizedDatasetTemplate

        Get the templates from the default directory

    .EXAMPLE
        Get-DbaRandomizedDatasetTemplate  -Template Personaldata, Test

        Get the templates from thedefault directory and filter on PersonalData and Test

    .EXAMPLE
        Get-DbaRandomizedDatasetTemplate  -Path C:\DatasetTemplates

        Get the templates from a custom directory

    #>
    [CmdLetBinding()]
    param(
        [string[]]$Template,
        [string[]]$Path,
        [switch]$ExcludeDefault,
        [switch]$EnableException
    )

    begin {
        $templates = @()

        # Get all the default templates
        if (-not $ExcludeDefault) {
            $templates += Get-ChildItem (Resolve-Path -Path "$script:PSModuleRoot\bin\randomizer\templates\*.json")
        }
    }

    process {
        if (Test-FunctionInterrupt) { return }

        # Get the templates from the file path
        foreach ($p in $Path) {
            $templates += Get-ChildItem (Resolve-Path -Path "$Path\*.json")
        }

        # Filter the template if neccesary
        if ($Template) {
            $templates = $templates | Where-Object BaseName -in $Template
        }

        $templates | Select-Object BaseName, FullName
    }
}