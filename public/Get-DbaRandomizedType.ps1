function Get-DbaRandomizedType {
    <#
    .SYNOPSIS
        Lists available data types and subtypes for generating realistic test data during database masking operations

    .DESCRIPTION
        Returns all available randomizer types and subtypes that can be used with Get-DbaRandomizedValue for data masking and test data generation. These types include realistic data patterns like Person names, Address components, Finance data, Internet values, and Random data types. This command helps you discover what fake data options are available when building data masking rules or generating test datasets for non-production environments.

    .PARAMETER RandomizedType
        Filters results to specific main data categories for realistic test data generation.
        Use this when you need to focus on particular data types like Person, Address, Finance, Internet, or Random data.
        Available types include Address, Commerce, Company, Database, Date, Finance, Hacker, Image, Internet, Lorem, Name, Person, Phone, Random, System, and more.

    .PARAMETER RandomizedSubType
        Filters results to specific data subtypes within the main categories for precise data masking scenarios.
        Use this when you need exact data patterns like FirstName, LastName, Email, CreditCardNumber, or ZipCode.
        Subtypes provide granular control over the fake data generation for targeted column masking.

    .PARAMETER Pattern
        Searches both main types and subtypes using pattern matching to find relevant data generators.
        Use this when you're unsure of exact type names or want to discover related options like searching 'Addr' to find Address-related types.
        Supports wildcard matching against both Type and SubType columns for flexible discovery.

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