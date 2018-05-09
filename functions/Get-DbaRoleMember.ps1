function Get-DbaRoleMember {
    <#
.SYNOPSIS
Get members of all roles on a Sql instance.

.DESCRIPTION
Get members of all roles on a Sql instance.

Default output includes columns SQLServer, Database, Role, Member.

.PARAMETER SQLInstance
The SQL Server that you're connecting to.

.PARAMETER SqlCredential
Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

.PARAMETER Database
The database(s) to process - this list is auto-populated from the server. If unspecified, all databases will be processed.

.PARAMETER ExcludeDatabase
The database(s) to exclude - this list is auto-populated from the server

.PARAMETER IncludeServerLevel
Shows also information on Server Level Permissions.

.PARAMETER NoFixedRole
Excludes all members of fixed roles.

.PARAMETER Credential
Credential object used to connect to the SQL Server as a different user.

.NOTES
Tags: Roles, Databases
Author: Klaas Vandenberghe ( @PowerDBAKlaas )

Website: https://dbatools.io
Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
License: MIT https://opensource.org/licenses/MIT

.LINK
 https://dbatools.io/Get-DbaRoleMember

.EXAMPLE
Get-DbaRoleMember -SqlInstance ServerA

Returns a custom object displaying SQLServer, Database, Role, Member for all DatabaseRoles.

.EXAMPLE
Get-DbaRoleMember -SqlInstance sql2016 | Out-Gridview

Returns a gridview displaying SQLServer, Database, Role, Member for all DatabaseRoles.

.EXAMPLE
Get-DbaRoleMember -SqlInstance ServerA\sql987 -IncludeServerLevel

Returns a gridview displaying SQLServer, Database, Role, Member for both ServerRoles and DatabaseRoles.

#>
    [CmdletBinding()]
    Param (
        [parameter(Mandatory, ValueFromPipeline)]
        [Alias('SqlServer', 'ServerInstance')]
        [DbaInstanceParameter[]]$SqlInstance,
        [Alias("Credential")]
        [PSCredential]
        $SqlCredential,
        [Alias("Databases")]
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [switch]$IncludeServerLevel,
        [switch]$NoFixedRole
    )

    process {

        foreach ($instance in $sqlinstance) {
            Write-Verbose "Connecting to $Instance"
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential
            }
            catch {
                Write-Warning "Failed to connect to $instance"
                continue
            }

            if ($IncludeServerLevel) {
                Write-Verbose "Server Role Members included"
                $instroles = $null
                Write-Verbose "Getting Server Roles on $instance"
                $instroles = $server.roles
                if ($NoFixedRole) {
                    $instroles = $instroles | Where-Object { $_.isfixedrole -eq $false }
                }
                ForEach ($instrole in $instroles) {
                    Write-Verbose "Getting Server Role Members for $instrole on $instance"
                    $irmembers = $null
                    $irmembers = $instrole.enumserverrolemembers()
                    ForEach ($irmem in $irmembers) {
                        [PSCustomObject]@{
                            SQLInstance = $instance
                            Database    = $null
                            Role        = $instrole.name
                            Member      = $irmem.tostring()
                        }
                    }
                }
            }

            $dbs = $server.Databases

            if ($Database) {
                $dbs = $dbs | Where-Object Name -In $Database
            }

            if ($ExcludeDatabase) {
                $dbs = $dbs | Where-Object Name -NotIn $ExcludeDatabase
            }

            foreach ($db in $dbs) {
                Write-Verbose "Checking accessibility of $db on $instance"

                if ($db.IsAccessible -ne $true) {
                    Write-Warning "Database $db on $instance is not accessible"
                    continue
                }

                $dbroles = $db.roles
                Write-Verbose "Getting Database Roles for $db on $instance"

                if ($NoFixedRole) {
                    $dbroles = $dbroles | Where-Object { $_.isfixedrole -eq $false }
                }

                foreach ($dbrole in $dbroles) {
                    Write-Verbose "Getting Database Role Members for $dbrole in $db on $instance"
                    $dbmembers = $dbrole.enummembers()
                    ForEach ($dbmem in $dbmembers) {
                        [PSCustomObject]@{
                            SqlInstance = $instance
                            Database    = $db.name
                            Role        = $dbrole.name
                            Member      = $dbmem.tostring()
                        }
                    }
                }
            }
        }
    }
}
