function Get-DbaTrigger {
    <#
.SYNOPSIS
Get all existing triggers on one or more SQL instances.

.DESCRIPTION
Get all existing triggers on one or more SQL instances.

Default output includes columns ComputerName, SqlInstance, Database, TriggerName, IsEnabled and DateLastModified.

.PARAMETER SqlInstance
The SQL Instance that you're connecting to.

.PARAMETER SqlCredential
SqlCredential object used to connect to the SQL Server as a different user.

.PARAMETER Database
The database(s) to process - this list is auto-populated from the server. If unspecified, all databases will be processed.

.PARAMETER ExcludeDatabase
The database(s) to exclude - this list is auto-populated from the server

.NOTES
Tags: Database, Triggers
Author: Klaas Vandenberghe ( @PowerDBAKlaas )

Website: https://dbatools.io
Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
License: MIT https://opensource.org/licenses/MIT

.LINK
 https://dbatools.io/Get-DbaTrigger

.EXAMPLE
Get-DbaTrigger -SqlInstance ComputerA\sql987

Returns a custom object displaying ComputerName, SqlInstance, Database, TriggerName, IsEnabled and DateLastModified.

.EXAMPLE
Get-DbaTrigger -SqlInstance 'ComputerA\sql987','ComputerB'

Returns a custom object displaying ComputerName, SqlInstance, Database, TriggerName, IsEnabled and DateLastModified from two instances.

.EXAMPLE
Get-DbaTrigger -SqlInstance ComputerA\sql987 | Out-Gridview

Returns a gridview displaying ComputerName, SqlInstance, Database, TriggerName, IsEnabled and DateLastModified.

.EXAMPLE
'ComputerA\sql987','ComputerB' | Get-DbaTrigger | Out-Gridview

Returns a custom object displaying ComputerName, SqlInstance, Database, TriggerName, IsEnabled and DateLastModified from two instances.

#>
    [CmdletBinding()]
    param (
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [Alias("ServerInstance", "SqlServer", "instance")]
        [DbaInstanceParameter[]]$SqlInstance,
        [Alias("Credential")]
        [PSCredential]
        $SqlCredential,
        [Alias("Databases")]
        [object[]]$Database,
        [object[]]$ExcludeDatabase
    )

    process {
        foreach ($Instance in $SqlInstance) {
            Write-Verbose "Connecting to $Instance"
            try {
                $server = Connect-SqlInstance -SqlInstance $Instance -SqlCredential $SqlCredential -Erroraction SilentlyContinue
            }
            catch {
                Write-Warning "Can't connect to $Instance"
                continue
            }

            Write-Verbose "Getting Server Level Triggers on $Instance"
            $server.Triggers |
                ForEach-Object {
                [PSCustomObject]@{
                    ComputerName     = $server.NetName
                    InstanceName     = $server.ServiceName
                    SqlInstance      = $server.DomainInstanceName
                    TriggerLevel     = "Server"
                    Database         = $null
                    TriggerName      = $_.Name
                    Status           = switch ($_.IsEnabled) { $true { "Enabled" } $false { "Disabled" } }
                    DateLastModified = $_.DateLastModified
                }
            }

            Write-Verbose "Getting Database Level Triggers on $Instance"
            $dbs = $server.Databases | Where-Object { $_.status -eq 'Normal' }

            if ($Database) {
                $dbs = $dbs | Where-Object Name -in $Database
            }
            if ($ExcludeDatabase) {
                $dbs = $dbs | Where-Object Name -notin $ExcludeDatabase
            }

            $dbs |
                ForEach-Object {
                $DatabaseName = $_.Name
                Write-Verbose "Getting Database Level Triggers on Database $DatabaseName on $Instance"
                $_.Triggers |
                    ForEach-Object {
                    [PSCustomObject]@{
                        ComputerName     = $server.NetName
                        InstanceName     = $server.ServiceName
                        SqlInstance      = $server.DomainInstanceName
                        TriggerLevel     = "Database"
                        Database         = $DatabaseName
                        TriggerName      = $_.Name
                        Status           = switch ($_.IsEnabled) { $true { "Enabled" } $false { "Disabled" } }
                        DateLastModified = $_.DateLastModified
                    }
                }
            }
        }
    }
}
