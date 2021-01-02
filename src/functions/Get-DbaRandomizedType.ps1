function Get-DbaRandomizedType {
    <#
    .SYNOPSIS
        Get the randomized types and sub types

    .DESCRIPTION
        Retrieves the types and sub types available

    .PARAMETER RandomizedType
        Filter the randomized types

    .PARAMETER RandomizedSubType
        Filter the randomized sub types

    .PARAMETER Pattern
        Get the types and sub types based on a pattern

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
        https://dbatools.io/Get-DbaRandomizedType

    .EXAMPLE
        Get-DbaRandomizedType

        Get all the types and subtypes

    .EXAMPLE
        Get-DbaRandomizedType -Pattern "Addr"

        Find all the types and sub types based on a pattern

    .EXAMPLE
        Get-DbaRandomizedType -RandomizedType Person

        Find all the sub types for Person

    .EXAMPLE
        Get-DbaRandomizedType -RandomizedSubType LastName

        Get all the types and subtypes that known by "LastName"

    #>
    [CmdLetBinding()]

    param(
        [string[]]$RandomizedType,
        [string[]]$RandomizedSubType,
        [string]$Pattern,
        [switch]$EnableException
    )

    begin {

        # Get all the random possibilities
        try {
            $randomizerTypes = Import-Csv (Resolve-Path -Path "$script:PSModuleRoot\bin\randomizer\en.randomizertypes.csv")
        } catch {
            Stop-Function -Message "Could not import randomized types" -Continue
        }

    }

    process {

        if (Test-FunctionInterrupt) { return }

        $types = @()

        if ($Pattern) {
            $types += $randomizerTypes | Where-Object Type -match $Pattern
            $types += $randomizerTypes | Where-Object SubType -match $Pattern
        } else {
            $types = $randomizerTypes
        }

        if ($RandomizedType) {
            $types = $types | Where-Object Type -in $RandomizedType
        }

        if ($RandomizedSubType) {
            $types = $types | Where-Object SubType -in $RandomizedSubType
        }

        $types | Select-Object Type, SubType -Unique | Sort-Object Type, SubType

    }

}