
Function Get-DbaCollationEquals {
    <#
    .SYNOPSIS
        Gets whether two strings are equivalent using any given collation.
    .DESCRIPTION
        The Get-DbaCollationEquals command uses the server management object's getStringComparer() function to compare two strings for a given collation
    .PARAMETER SqlInstance
        The target SQL Server instance this parameter
    .PARAMETER String1
        Specifies first string to compare
    .PARAMETER String2
        Specifies second string to compare
    .PARAMETER Collation
        Specifies Collation to use for string comparison
    .NOTES
        Tags: Database
        Author: Charles Hightower (@chightow)
        Website: https://dbatools.io
        Copyright: (c) 2021 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        Written need to compare two strings in powershell and get the same result as you would in sql for a given collation

        References: https://stackoverflow.com/questions/9384642/what-net-stringcomparer-is-equivalent-sqls-latin1-general-ci-as
        https://docs.microsoft.com/en-us/dotnet/api/microsoft.sqlserver.management.smo.server.getstringcomparer?view=sql-smo-160
        https://docs.microsoft.com/en-us/dotnet/api/system.string.compare?view=net-5.0
    .EXAMPLE

        PS C:\> Get-DbaCollationEquals -Collation 'SQL_Latin1_General_CP1_CI_AS' -String1 'x³' -String2 'x₃'
        Returns True  SQL_Latin1_General_CP1_CI_AS is a Width Insensitve for Unicode Data x³ x₃ X3 are all equivalent
    .EXAMPLE
        PS C:\> Get-DbaCollationEquals -Collation 'SQL_Latin1_General_CP1_CI_AI' -String1 'á' -String2 'Á'
        Returns True SQL_Latin1_General_CP1_CI_AI is Latin1-General, case-insensitive, accent-insensitive
    #>
    param([string]$Collation, [string]$String1, [string]$String2, [Microsoft.SqlServer.Management.Smo.Server]$SqlInstance )
    if (-not $SqlInstance) {
        $SqlInstance = New-Object -TypeName Microsoft.SqlServer.Management.Smo.Server
    }
    return $SqlInstance.getStringComparer($Collation).Compare($string1, $string2) -eq 0
}