function Remove-DbaDatabase {
    <#
.SYNOPSIS
Drops a database, hopefully even the really stuck ones.

.DESCRIPTION
Tries a bunch of different ways to remove a database or two or more.

.PARAMETER SqlInstance
The SQL Server instance holding the databases to be removed.You must have sysadmin access and server version must be SQL Server version 2000 or higher.

.PARAMETER SqlCredential
Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

.PARAMETER Database
The database(s) to process - this list is auto-populated from the server. If unspecified, all databases will be processed.

.PARAMETER InputObject
A collection of databases (such as returned by Get-DbaDatabase), to be removed.

.PARAMETER IncludeSystemDb
Use this switch to disable any kind of verbose messages

.PARAMETER WhatIf
Shows what would happen if the command were to run. No actions are actually performed.

.PARAMETER Confirm
Prompts you for confirmation before executing any changing operations within the command.

.PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

.NOTES
Tags: Delete, Databases

Website: https://dbatools.io
Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
License: MIT https://opensource.org/licenses/MIT

.LINK
https://dbatools.io/Remove-DbaDatabase

.EXAMPLE
Remove-DbaDatabase -SqlInstance sql2016 -Database containeddb

Prompts then removes the database containeddb on SQL Server sql2016

.EXAMPLE
Remove-DbaDatabase -SqlInstance sql2016 -Database containeddb, mydb

Prompts then removes the databases containeddb and mydb on SQL Server sql2016

.EXAMPLE
Remove-DbaDatabase -SqlInstance sql2016 -Database containeddb -Confirm:$false

Does not prompt and swiftly removes containeddb on SQL Server sql2016

.EXAMPLE
Get-DbaDatabase -SqlInstance server\instance -ExcludeAllSystemDb | Remove-DbaDatabase

Removes all the user databases from server\instance

.EXAMPLE
Get-DbaDatabase -SqlInstance server\instance -ExcludeAllSystemDb | Remove-DbaDatabase -Confirm:$false

Removes all the user databases from server\instance without any confirmation
#>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High', DefaultParameterSetName = "Default")]
    Param (
        [parameter(, Mandatory, ParameterSetName = "instance")]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [parameter(Mandatory = $false)]
        [Alias("Credential")]
        [PSCredential]
        $SqlCredential,
        [parameter(Mandatory, ParameterSetName = "instance")]
        [Alias("Databases")]
        [object[]]$Database,
        [Parameter(ValueFromPipeline, Mandatory, ParameterSetName = "databases")]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [switch]$IncludeSystemDb,
        [Alias('Silent')]
        [switch]$EnableException
    )

    process {

        foreach ($instance in $SqlInstance) {
            try {
                Write-Message -Level Verbose -Message "Connecting to $instance"
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
            $InputObject += $server.Databases | Where-Object { $_.Name -in $Database }
        }

        $system_dbs = @( "master", "model", "tempdb", "resource", "msdb" )

        if (-not($IncludeSystemDb)) {
            $InputObject = $InputObject | Where-Object { $_.Name -notin $system_dbs}
        }

        foreach ($db in $InputObject) {
            try {
                $server = $db.Parent
                if ($Pscmdlet.ShouldProcess("$db on $server", "KillDatabase")) {
                    $server.KillDatabase($db.name)
                    $server.Refresh()

                    [pscustomobject]@{
                        ComputerName = $server.NetName
                        InstanceName = $server.ServiceName
                        SqlInstance  = $server.DomainInstanceName
                        Database     = $db.name
                        Status       = "Dropped"
                    }
                }
            }
            catch {
                try {
                    if ($Pscmdlet.ShouldProcess("$db on $server", "alter db set single_user with rollback immediate then drop")) {
                        $null = $server.Query("if exists (select * from sys.databases where name = '$($db.name)' and state = 0) alter database $db set single_user with rollback immediate; drop database $db")

                        [pscustomobject]@{
                            ComputerName = $server.NetName
                            InstanceName = $server.ServiceName
                            SqlInstance  = $server.DomainInstanceName
                            Database     = $db.name
                            Status       = "Dropped"
                        }
                    }
                }
                catch {
                    try {
                        if ($Pscmdlet.ShouldProcess("$db on $server", "SMO drop")) {
                            $server.databases[$dbname].Drop()
                            $server.Refresh()

                            [pscustomobject]@{
                                ComputerName = $server.NetName
                                InstanceName = $server.ServiceName
                                SqlInstance  = $server.DomainInstanceName
                                Database     = $db.name
                                Status       = "Dropped"
                            }
                        }
                    }
                    catch {
                        Write-Message -Level Verbose -Message "Could not drop database $db on $server"

                        [pscustomobject]@{
                            ComputerName = $server.NetName
                            InstanceName = $server.ServiceName
                            SqlInstance  = $server.DomainInstanceName
                            Database     = $db.name
                            Status       = $_
                        }
                    }
                }
            }
        }
    }
}
