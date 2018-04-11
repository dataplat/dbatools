function Get-DbaDbRole {
    <#
.SYNOPSIS
Get database roles on a Sql instance.

.DESCRIPTION
Get database roles on a Sql instance.

Default output includes columns SQLServer, Database, Role.

.PARAMETER SQLInstance
The SQL Server that you're connecting to.

.PARAMETER SqlCredential
Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

.PARAMETER Database
The database(s) to process - this list is auto-populated from the server. If unspecified, all databases will be processed.

.PARAMETER ExcludeDatabase
The database(s) to exclude - this list is auto-populated from the server

.PARAMETER ExcludeFixedRole
Excludes all fixed roles.

.PARAMETER Credential
Credential object used to connect to the SQL Server as a different user.

.PARAMETER EnableException
    By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
    This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
    Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

.NOTES
Tags: Roles, Databases
Author: Klaas Vandenberghe ( @PowerDBAKlaas )

Website: https://dbatools.io
Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
License: MIT https://opensource.org/licenses/MIT

.LINK
 https://dbatools.io/Get-DbaDbRole

.EXAMPLE
Get-DbaDbRole -SqlInstance ServerA

Returns a custom object displaying SQLServer, Database, Role for all DatabaseRoles on sql instance ServerA.

.EXAMPLE
Get-DbaDbRole -SqlInstance ServerA | Out-Gridview

Returns a gridview displaying SQLServer, Database, Role for all DatabaseRoles on sql instance ServerA.

.EXAMPLE
Get-DbaDbRole -SqlInstance ServerB\sql16 -ExcludeDatabase DBADB,TestDB

Returns SQLServer, Database, Role for DatabaseRoles on sql instance ServerB\sql16, except those in databases DBADB and TestDB.

.EXAMPLE
'ServerB\sql16','ServerA' | Get-DbaDbRole

Returns SQLServer, Database, Role for DatabaseRoles on sql instances ServerA and ServerB\sql16.

.EXAMPLE
Get-DbaDbRole -SqlInstance ServerB\sql16 -Database AccountingDB

Returns SQLServer, Database, Role for DatabaseRoles in database AccountingDB on sql instance ServerB\sql16.

.EXAMPLE
Get-DbaDbRole -SqlInstance ServerB\sql16 -ExcludeFixedRoles

Returns SQLServer, Database, Role for DatabaseRoles on sql instance ServerB\sql16, but not the fixed roles.

#>
    [CmdletBinding()]
    Param (
        [parameter(Mandatory, ValueFromPipeline)]
        [Alias('SqlServer', 'ServerInstance')]
        [DbaInstanceParameter[]]$SqlInstance,
        [Alias("Credential")]
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [switch]$ExcludeFixedRole,
        [Alias('Silent')]
        [switch]$EnableException
    )

    process {

        foreach ($instance in $sqlInstance) {
            try {
                Write-Message -Level Verbose -Message "Connecting to $instance"
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $dbs = $server.Databases | Where-Object IsAccessible

            if ($Database) {
                Write-Message -Level Verbose -Message "Databases to check: $Database"
                $dbs = $dbs | Where-Object Name -In $Database
            }

            if ($ExcludeDatabase) {
                Write-Message -Level Verbose -Message "Databases excluded from check: $ExcludeDatabase"
                $dbs = $dbs | Where-Object Name -NotIn $ExcludeDatabase
            }

            foreach ($db in $dbs) {
                Write-Message -Level Verbose -Message "Checking accessibility of $db on $instance"

                if ($db.IsAccessible -ne $true) {
                    Write-Message -Level Warning -Message "Database $db on $instance is not accessible"
                    continue
                }

                $dbroles = $db.roles
                Write-Message -Level Verbose -Message "Getting Database Roles for $db on $instance"

                if ($ExcludeFixedRole) {
                    $dbroles = $dbroles | Where-Object IsFixedRole -eq $false
                }

                foreach ($dbrole in $dbroles) {
                    Add-Member -Force -InputObject $dbrole -MemberType NoteProperty -Name ComputerName -value $server.NetName
                    Add-Member -Force -InputObject $dbrole -MemberType NoteProperty -Name InstanceName -value $server.ServiceName
                    Add-Member -Force -InputObject $dbrole -MemberType NoteProperty -Name SqlInstance -value $server.DomainInstanceName
                    Add-Member -Force -InputObject $dbrole -MemberType NoteProperty -Name Database -value $db.Name

                    Select-DefaultView -InputObject $dbrole -Property ComputerName, InstanceName, SqlInstance, Database, Name, Owner, CreateDate, DateLastModified, IsFixedRole
                }
            }
        }
    }
}
