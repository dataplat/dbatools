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
        Returns True
    .EXAMPLE
        PS C:\> Compare-DbaStringCollation -Reference Dbátools -Difference Dbatools -Comparison Eq -Collation SQL_Latin1_General_CP1_CS_AI
        Returns True
    .Example
         PS C:\> Compare-DbaStringCollation -Reference dbátools -Difference DbAtOoLs -Comparison Ne -Collation SQL_Latin1_General_CP1_CI_AI
         Returns False
    .EXAMPLE
        PS C:\> $collations =  Get-DbaAvailableCollation -SqlInstance localhost
        PS C:\> foreach($collation in $collations){
                    $equalivent = Compare-DbaStringCollation -Reference ﾐﾑﾒ -Difference ミムメ -Comparison Eq -Collation $collation.Name
                    IF($equalivent){$collation.Name}}
        Returns all the collations available on SqlInstance localhost where ﾐﾑﾒ and ミムメ would evaluate to be the same string
    .EXAMPLE
        PS C:\> Compare-DbaStringCollation -Reference dbá -Difference Dba,tools -Comparison In -Collation SQL_Latin1_General_CP1_CI_AI
        Returns True
    .EXAMPLE
        PS C:\> Compare-DbaStringCollation -Reference dbá -Difference Dba,tools -Comparison Notin -Collation SQL_Latin1_General_CP1_CI_AS
        Returns True
    #>
    param(
        [Parameter(Mandatory)]
        [string[]]$Reference,
        [Parameter(Mandatory)]
        [string[]]$Difference,
        [Parameter(Mandatory)]
        [string]$Collation,
        [Parameter(Mandatory)]
        [ValidateSet('In', 'Notin', 'Eq', 'Ne')]
        [string]$Comparison)
    $smo = New-Object -TypeName Microsoft.SqlServer.Management.Smo.Server
    $results = @()
    foreach ($ref in $Reference) {
        switch ($Comparison) {
            'Eq' { $equalivent = $smo.getStringComparer($Collation).Compare($ref, $Difference) -eq 0 }
            'Ne' { $equalivent = $smo.getStringComparer($Collation).Compare($ref, $Difference) -ne 0 }
            'In' {
                foreach ($dif in $Difference) {
                    if ($smo.getStringComparer($Collation).Compare($ref, $dif) -eq 0 ) {
                        $equalivent = $true
                        break
                    }
                }
                $equalivent = $false;
            }
            'Notin' {
                foreach ($dif in $Difference) {
                    if ($smo.getStringComparer($Collation).Compare($ref, $dif) -eq 0 ) {
                        $equalivent = $false
                        break
                    }
                }
                $equalivent = $true
            }
        }
        $results += [pscustomobject]@{Collation = $Collation
            Reference                           = $ref
            Difference                          = $Difference
            Equivalent                          = $equalivent
        }
    }
    return $results
}