Function Compare-DbaStringCollation {
    <#
    .SYNOPSIS
        Compares string  using a collation
    .DESCRIPTION
        The Compare-DbaStringCollation command uses the server management object's getStringComparer() function to compare strings for a given collation
    .PARAMETER Reference
        Reference String
    .PARAMETER Difference
        Specifies String or array of strings to compare
    .PARAMETER Collation
        Specifies Collation to use for string comparison
    .NOTES
        Tags: Database
        Authors: Charles Hightower,
        Website: https://dbatools.io
        Copyright: (c) 2021 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        References: https://stackoverflow.com/questions/9384642/what-net-stringcomparer-is-equivalent-sqls-latin1-general-ci-as
        https://docs.microsoft.com/en-us/dotnet/api/microsoft.sqlserver.management.smo.server.getstringcomparer?view=sql-smo-160
        https://docs.microsoft.com/en-us/dotnet/api/system.string.compare?view=net-5.0
    .EXAMPLE
        PS C:\> Compare-DbaStringCollation -Reference dbá,Tools -Difference Dba,tools -Collation SQL_Latin1_General_CP1_CI_AI
        Returns  dbá,Tools
    #>
    param(
        [Parameter(Mandatory)]
        [string[]]$Reference,
        [Parameter(Mandatory)]
        [string[]]$Difference,
        [Parameter(Mandatory)]
        [string]$Collation)

    $smo = New-Object -TypeName Microsoft.SqlServer.Management.Smo.Server

    $results = @()
    foreach ($ref in $Reference) {
        foreach ($dif in $Difference) {
            if ($smo.getStringComparer($Collation).Compare($ref, $dif) -eq 0 ) {
                $results += $ref
            }
        }
    }
    return $results
}