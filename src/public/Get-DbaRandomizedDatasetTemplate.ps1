function Get-DbaRandomizedDatasetTemplate {
    <#
    .SYNOPSIS
        Gets the dataset templates

    .DESCRIPTION
        Retrieves the templates from the default directory and if assigned custom directories

    .PARAMETER Template
        The name of the template to use.
        It will go through the default templates to see if it's present

    .PARAMETER Path
        Path or paths that contain template files

    .PARAMETER ExcludeDefault
        Exclude the default templates

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