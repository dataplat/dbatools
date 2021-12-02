<#
    .SYNOPSIS
        Gets SQL Database information for each database that is present on the target instance(s) of SQL Server.

    .DESCRIPTION
        The Get-DbaDatabase command gets SQL database information for each database that is present on the target instance(s) of
        SQL Server. If the name of the database is provided, the command will return only the specific database information.

    .PARAMETER InputObject
        The Object to Filter

    .PARAMETER Property
        Name of the Property of InputObject to compare

    .PARAMETER Value
        Object that Property is compared against

    .PARAMETER In
        Members of InputObject where the value of the Property is within the Value set are returned

    .PARAMETER NotIn
        Members of InputObject where the value of the Property is not within the Value set are returned

    .PARAMETER Eq
        Members of InputObject where the value of the Property is equivalent to the Value

    .PARAMETER Ne
        Members of InputObject where the value of the Property is not not equivalent to the Value

    .PARAMETER Collation
        Name of the collation to use for comparison


    .NOTES
        Tags: Database
        Author: Charles Hightower

        Website: https://dbatools.io
        Copyright: (c) 2021 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT
    .EXAMPLE
        PS C:\> $server = connect-dbaInstance -sqlInstance localhost
        PS C:\> $lastCopyOnlyBackups = Get-DbaDbBackupHistory -SqlInstance $server -LastFull -IncludeCopyOnly | Where-Object IsCopyOnly
        PS C:\> $server.Databases | Compare-DbaCollationSensitiveObject -Property Name -In -Value $lastCopyOnlyBackups.Database -Collation $server.Collation

        Returns all databases on the local default SQL Server instance with copy only backups using the server's collation

    .EXAMPLE
        PS C:\> $server = connect-dbaInstance -sqlInstance localhost
        PS C:\> $lastFullBackups = Get-DbaDbBackupHistory -SqlInstance $server -LastFull
        PS C:\> $server.Databases | Compare-DbaCollationSensitiveObject -Property Name -NotIn -Value $lastFullBackups.Database -Collation $server.Collation

        Returns only the databases on the local default SQL Server instance without a Full Backup, uses server's collation

#>
Function Compare-DbaCollationSensitiveObject {
    [CmdletBinding()]
    param(
        [parameter(Mandatory, ValueFromPipeline = $true)]
        [psObject]$InputObject,
        [parameter(Mandatory)]
        [string]$Property,
        [parameter(Mandatory, ParameterSetName = 'In')]
        [switch]$In,
        [parameter(Mandatory, ParameterSetName = 'NotIn')]
        [switch]$NotIn,
        [parameter(Mandatory, ParameterSetName = 'Eq')]
        [switch]$Eq,
        [parameter(Mandatory, ParameterSetName = 'Ne')]
        [switch]$Ne,
        [parameter(Mandatory)]
        [object]$Value,
        [parameter(Mandatory)]
        [String]$Collation)
    begin {

        #If inputObject is passed in by name, change it to a pipeline, so we can use the process block
        if ($PSBoundParameters['InputObject']) {
            if ($In) {
                return $InputObject | Compare-DbaCollationSensitiveObject -Property $Property -In -Value $Value -Collation $Collation
            } elseif ($NotIn) {
                return $InputObject | Compare-DbaCollationSensitiveObject -Property $Property -NotIn -Value $Value -Collation $Collation
            } elseif ($Eq) {
                return $InputObject | Compare-DbaCollationSensitiveObject -Property $Property -Eq -Value $Value -Collation $Collation
            } elseif ($Ne) {
                return $InputObject | Compare-DbaCollationSensitiveObject -Property $Property -Ne -Value $Value -Collation $Collation
            }
        }
        $stringComparer = (New-Object -TypeName Microsoft.SqlServer.Management.Smo.Server).getStringComparer($Collation)
    }
    process {
        if ($In) {
            foreach ($ref in $_."$Property") {
                foreach ($dif in $Value) {
                    if ($stringComparer.Compare($ref, $dif) -eq 0) {
                        return $_
                    }
                }
            }
        } elseif ($NotIn) {
            foreach ($ref in $_."$Property") {
                $matchFound = $false
                foreach ($dif in $Value) {
                    if ($stringComparer.Compare($ref, $dif) -eq 0) {
                        $matchFound = $true
                    }
                }
                if (-not $matchFound) {
                    return $_
                }
            }
        } elseif ($Eq) {
            foreach ($ref in $_."$Property") {
                if ($stringComparer.Compare($ref, $Value) -eq 0) {
                    return $_
                }
            }
        } elseif ($Ne) {
            foreach ($ref in $_."$Property") {
                if ($stringComparer.Compare($ref, $Value) -ne 0) {
                    return $_
                }
            }
        }
    }
}