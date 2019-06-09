function Test-DbaDataGenerationConfiguration {
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
        Tags: Data generation, testing
        Author: Sander Stad (@sqlstad), sqlstad.nl

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        Requires: sysadmin access on SQL Servers

    .LINK
        https://dbatools.io/Test-DbaDataGenerationConfiguration

    .EXAMPLE

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
    }

    process {
        if (Test-FunctionInterrupt) { return }

        $errors = @()

        $errors
    } # End process

}