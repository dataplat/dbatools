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
        PS C:\> Compare-DbaStringCollation -Reference dbatools -Difference DbAToOlS -Comparison Eq -Collation SQL_Latin1_General_CP1_CI_AS
        Returns
        Collation  : SQL_Latin1_General_CP1_CI_AS
        Reference  : dbatools
        Difference : DbAToOlS
        Comparison : eq
        Equivalent : True
    .EXAMPLE
        PS C:\> Compare-DbaStringCollation -Reference Dbátools -Difference Dbatools -Comparison Eq -Collation SQL_Latin1_General_CP1_CS_AI
        Returns
        Collation  : SQL_Latin1_General_CP1_CS_AI
        Reference  : Dbátools
        Difference : Dbatools
        Comparison : Eq
        Equivalent : True
    .Example
         PS C:\> Compare-DbaStringCollation -Reference dbátools -Difference DbAtOoLs -Comparison Ne -Collation SQL_Latin1_General_CP1_CI_AI
         Returns
         Collation  : SQL_Latin1_General_CP1_CI_AI
         Reference  : dbátools
         Difference : DbAtOoLs
         Comparison : Ne
         Equivalent : False
    .EXAMPLE
        PS C:\> $collations =  Get-DbaAvailableCollation -SqlInstance localhost
        PS C:\> Compare-DbaStringCollation -Reference ﾐﾑﾒ -Difference ミムメ -Comparison Eq -Collation $collations.Name
        Returns all the collations available on SqlInstance localhost and how ﾐﾑﾒ and ミムメ would evaluate for each of them
    .EXAMPLE
        PS C:\> Compare-DbaStringCollation -Reference dbá,Tools -Difference Dba,tools -Comparison In -Collation SQL_Latin1_General_CP1_CI_AI
        Returns
        Collation  : SQL_Latin1_General_CP1_CI_AI
        Reference  : dbá
        Difference : {Dba, tools}
        Comparison : In
        Equivalent : True

        Collation  : SQL_Latin1_General_CP1_CI_AI
        Reference  : Tools
        Difference : {Dba, tools}
        Comparison : In
        Equivalent : True
    .EXAMPLE
        PS C:\> Compare-DbaStringCollation -Reference dbá,Tools -Difference Dba,tools -Comparison Notin -Collation SQL_Latin1_General_CP1_CI_AS

        Collation  : SQL_Latin1_General_CP1_CI_AS
        Reference  : dbá
        Difference : {Dba, Tools}
        Comparison : Notin
        Result     : True

        Collation  : SQL_Latin1_General_CP1_CI_AS
        Reference  : tools
        Difference : {Dba, Tools}
        Comparison : Notin
        Result     : False
    #>
    param(
        [Parameter(Mandatory)]
        [string[]]$Reference,
        [Parameter(Mandatory)]
        $Difference,
        [Parameter(Mandatory)]
        [string[]]$Collation,
        [Parameter(Mandatory)]
        [ValidateSet('In', 'Notin', 'Eq', 'Ne')]
        [string]$Comparison)
    $smo = New-Object -TypeName Microsoft.SqlServer.Management.Smo.Server

    $results = @()
    foreach ($col in $Collation) {
        foreach ($ref in $Reference) {
            switch ($Comparison) {
                'Eq' { $res = $smo.getStringComparer($col).Compare($ref, $Difference) -eq 0; break; }
                'Ne' { $res = $smo.getStringComparer($col).Compare($ref, $Difference) -ne 0; break; }
                'In' {
                    foreach ($dif in $Difference) {
                        $res = $null
                        if ($smo.getStringComparer($col).Compare($ref, $dif) -eq 0 ) {
                            $res = $true
                            break
                        }
                    }
                    if ( $null -eq $res) { $res = $false }
                }
                'Notin' {
                    foreach ($dif in $Difference) {
                        $res = $null
                        $testCondition = $smo.getStringComparer($col).Compare($ref, $dif)
                        if ($testCondition -eq 0 ) {
                            $res = $false
                            break
                        }
                    }
                    if ($null -eq $res ) { $res = $true; break; }
                }
            }
            $results += [pscustomobject]@{Collation = $col
                Reference                           = $ref
                Difference                          = $Difference
                Comparison                          = $Comparison
                Result                              = $res
            }
        }
    }
    return $results
}
