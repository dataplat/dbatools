function Get-TableNameParts {
    <#
    .SYNOPSIS
        Parse a one, two, or three part table name into seperate paths

    .DESCRIPTION
    Generates a hash string based on the plaintext or securestring password and a SQL Server version. Salt is optional

    .PARAMETER Table
        The table name to parse. You can specify a one, two, or three part table name.
        If the object has special characters they must be wrapped in square brackets [ ].
        If the name contains character ']' this must be escaped by duplicating the character

    .NOTES
        Tags: Table, Internal
        Author: Patrick Flynn (@sqllensman)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .EXAMPLE
        Get-TableNameParts 'table'

        Parses a three-part name into its constitute parts.

    .EXAMPLE
        Get-TableNameParts '[Bad. Name]]].[Schema.With.Dots]]].[Another .Silly]] Name..]'

        Parses a three-part name into its constitute parts. Uses square brackets to enclose special characters.
    #>
    param (
        [string]$Table
    )
    process {
        $fqtns = @()
        #Tables with a ']' charcter in name need to be handeled
        #Require charcter to be escaped by being duplicated as per T-SQL QuoteName function
        #These need to be temporarily replaced to allow name to be parsed.
        $t = $Table
        if ($t.Contains(']]')) {
            for ($i = 0; $i -le 65535; $i++) {
                $hexStr = '{0:X4}' -f $i
                $char = [regex]::Unescape("\u$($HexStr)")
                if (!$Table.Contains($Char)) {
                    $fixChar = $Char
                    $t = $t.Replace(']]', $fixChar)
                    Break
                }
            }
        } else {
            $fixChar = $null
        }
        $splitName = [regex]::Matches($t, "(\[.+?\])|([^\.]+)").Value
        $dotcount = $splitName.Count

        $splitDb = $Schema = $tbl = $null

        switch ($dotcount) {
            1 {
                $tbl = $t
                $parsed = $true
            }
            2 {
                $schema = $splitName[0]
                $tbl = $splitName[1]
                $parsed = $true
            }
            3 {
                $splitDb = $splitName[0]
                $schema = $splitName[1]
                $tbl = $splitName[2]
                $parsed = $true
            }
            default {
                $parsed = $false
            }
        }
        if ($splitDb -like "[[]*[]]") {
            $splitDb = $splitDb.Substring(1, ($splitDb.Length - 2))
            if ($fixChar) {
                $splitDb = $splitDb.Replace($fixChar, ']')
            }
        }

        if ($schema -like "[[]*[]]") {
            $schema = $schema.Substring(1, ($schema.Length - 2))
            if ($fixChar) {
                $schema = $schema.Replace($fixChar, ']')
            }
        }

        if ($tbl -like "[[]*[]]") {
            $tbl = $tbl.Substring(1, ($tbl.Length - 2))
            if ($fixChar) {
                $tbl = $tbl.Replace($fixChar, ']')
            }
        }
        $fqtns = [PSCustomObject] @{
            InputValue = $Table
            Database   = $splitDb
            Schema     = $Schema
            Table      = $tbl
            Parsed     = $parsed
        }
        return $fqtns
    }
}