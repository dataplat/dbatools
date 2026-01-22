function Get-ObjectNameParts {
    <#
    .SYNOPSIS
        Parse a one, two, or three part object name into seperate paths

    .DESCRIPTION
        Takes a one, two or three part object name and splits them into Database, Schema and Name

    .PARAMETER ObjectName
        The object name to parse. You can specify a one, two, or three part object name.
        If the object has special characters they must be wrapped in square brackets [ ].
        If the name contains character ']' this must be escaped by duplicating the character

    .NOTES
        Tags: Object, Internal
        Author: Patrick Flynn (@sqllensman)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .OUTPUTS
        System.Management.Automation.PSCustomObject

        Returns a custom object containing the parsed object name components.

        Properties:
        - InputValue: The original object name string passed to the function
        - Database: The database name component (null for one or two-part names)
        - Schema: The schema name component (null for one-part names)
        - Name: The object name component
        - Parsed: Boolean indicating whether the parsing was successful (false for invalid names with 4+ parts)

    .EXAMPLE
        Get-ObjectNameParts -ObjectName 'table'

        Parses a three-part name into its constitute parts.

    .EXAMPLE
        Get-ObjectNameParts -ObjectName '[Bad. Name]]].[Schema.With.Dots]]].[Another .Silly]] Name..]'

        Parses a three-part name into its constitute parts. Uses square brackets to enclose special characters.
    #>
    param (
        [string]$ObjectName
    )
    process {
        $fqtns = @()
        #Object names with a ']' charcter in the name need to be handeled
        #Require charcter to be escaped by being duplicated as per T-SQL QuoteName function
        #These need to be temporarily replaced to allow the object name to be parsed.
        $t = $ObjectName
        if ($t.Contains(']]')) {
            for ($i = 0; $i -le 65535; $i++) {
                $hexStr = '{0:X4}' -f $i
                $fixChar = [regex]::Unescape("\u$hexStr")
                if (!$t.Contains($fixChar)) {
                    $t = $t.Replace(']]', $fixChar)
                    break
                }
            }
        } else {
            $fixChar = $null
        }
        #If the dbo schema is empty as in database..table, it has to filled temorarily to let the regex work.
        if ($t.Contains('..')) {
            for ($i = 0; $i -le 65535; $i++) {
                $hexStr = '{0:X4}' -f $i
                $fixSchema = [regex]::Unescape("\u$hexStr")
                if (!$t.Contains($fixSchema)) {
                    $t = $t.Replace('..', ".$fixSchema.")
                    break
                }
            }
        } else {
            $fixSchema = $null
        }
        $splitName = [regex]::Matches($t, "(\[.+?\])|([^\.]+)").Value
        $dotcount = $splitName.Count

        $dbName = $schema = $name = $null

        switch ($dotcount) {
            1 {
                $name = $t
                $parsed = $true
            }
            2 {
                $schema = $splitName[0]
                $name = $splitName[1]
                $parsed = $true
            }
            3 {
                $dbName = $splitName[0]
                $schema = $splitName[1]
                $name = $splitName[2]
                $parsed = $true
            }
            default {
                $parsed = $false
            }
        }
        if ($dbName -like "[[]*[]]") {
            $dbName = $dbName.Substring(1, ($dbName.Length - 2))
            if ($fixChar) {
                $dbName = $dbName.Replace($fixChar, ']')
            }
        }

        if ($schema -like "[[]*[]]") {
            $schema = $schema.Substring(1, ($schema.Length - 2))
            if ($fixChar) {
                $schema = $schema.Replace($fixChar, ']')
            }
        }

        if ($name -like "[[]*[]]") {
            $name = $name.Substring(1, ($name.Length - 2))
            if ($fixChar) {
                $name = $name.Replace($fixChar, ']')
            }
        }

        if ($fixSchema) {
            if ($dbName) {
                $dbName = $dbName.Replace($fixSchema, '')
            }
            if ($schema -eq $fixSchema) {
                $schema = $null
            } elseif ($schema) {
                $schema = $schema.Replace($fixSchema, '')
            }
            if ($name) {
                $name = $name.Replace($fixSchema, '')
            }
        }

        $fqtns = [PSCustomObject] @{
            InputValue = $ObjectName
            Database   = $dbName
            Schema     = $schema
            Name       = $name
            Parsed     = $parsed
        }
        return $fqtns
    }
}