function Remove-DbaDatabase {
    <#
    .SYNOPSIS
        Removes user databases using multiple fallback methods to handle stuck or locked databases.

    .DESCRIPTION
        Removes user databases by attempting three different drop methods in sequence until one succeeds. First tries the standard KillDatabase() method, then attempts to set the database to single-user mode with rollback immediate before dropping, and finally uses the SMO Drop() method. This approach handles databases that are stuck due to active connections, replication, mirroring, or other locks that prevent normal removal. System databases are automatically excluded from removal operations.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.You must have sysadmin access and server version must be SQL Server version 2000 or higher.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies the user database(s) to remove from the SQL Server instance. Accepts multiple database names and supports wildcards for pattern matching.
        Use this when you need to remove specific databases rather than all user databases. System databases (master, model, msdb, tempdb, resource) are automatically excluded and cannot be removed.

    .PARAMETER InputObject
        Accepts database objects from the pipeline, typically from Get-DbaDatabase or other dbatools database commands.
        Use this for pipeline operations when you want to filter databases first, then remove the filtered results. This provides more flexibility than specifying database names directly.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Delete, Database
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Remove-DbaDatabase

    .EXAMPLE
        PS C:\> Remove-DbaDatabase -SqlInstance sql2016 -Database containeddb

        Prompts then removes the database containeddb on SQL Server sql2016

    .EXAMPLE
        PS C:\> Remove-DbaDatabase -SqlInstance sql2016 -Database containeddb, mydb

        Prompts then removes the databases containeddb and mydb on SQL Server sql2016

    .EXAMPLE
        PS C:\> Remove-DbaDatabase -SqlInstance sql2016 -Database containeddb -Confirm:$false

        Does not prompt and swiftly removes containeddb on SQL Server sql2016

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance server\instance | Remove-DbaDatabase

        Removes all the user databases from server\instance

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance server\instance | Remove-DbaDatabase -Confirm:$false

        Removes all the user databases from server\instance without any confirmation
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = "Default")]
    param (
        [parameter(Mandatory, ParameterSetName = "instance")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]
        $SqlCredential,
        [parameter(Mandatory, ParameterSetName = "instance")]
        [Alias('Name')]
        [object[]]$Database,
        [Parameter(ValueFromPipeline, Mandatory, ParameterSetName = "databases")]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [switch]$EnableException
    )

    process {

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
            $InputObject += $server.Databases | Where-Object { $_.Name -in $Database }
        }

        # Excludes system databases as these cannot be deleted
        $system_dbs = @( "master", "model", "tempdb", "resource", "msdb" )
        $InputObject = $InputObject | Where-Object { $_.Name -notin $system_dbs }

        foreach ($db in $InputObject) {
            try {
                $server = $db.Parent
                if ($Pscmdlet.ShouldProcess("$db on $server", "KillDatabase")) {
                    $server.KillDatabase($db.name)
                    $server.Refresh()
                    Remove-TeppCacheItem -SqlInstance $server -Type database -Name $db.name

                    [PSCustomObject]@{
                        ComputerName = $server.ComputerName
                        InstanceName = $server.ServiceName
                        SqlInstance  = $server.DomainInstanceName
                        Database     = $db.name
                        Status       = "Dropped"
                    }
                }
            } catch {
                try {
                    if ($Pscmdlet.ShouldProcess("$db on $server", "alter db set single_user with rollback immediate then drop")) {
                        $null = $server.Query("if exists (select * from sys.databases where name = '$($db.name)' and state = 0) alter database $db set single_user with rollback immediate; drop database $db")

                        [PSCustomObject]@{
                            ComputerName = $server.ComputerName
                            InstanceName = $server.ServiceName
                            SqlInstance  = $server.DomainInstanceName
                            Database     = $db.name
                            Status       = "Dropped"
                        }
                    }
                } catch {
                    try {
                        if ($Pscmdlet.ShouldProcess("$db on $server", "SMO drop")) {
                            $dbName = $db.Name
                            $db.Parent.databases[$dbName].Drop()
                            $server.Refresh()

                            [PSCustomObject]@{
                                ComputerName = $server.ComputerName
                                InstanceName = $server.ServiceName
                                SqlInstance  = $server.DomainInstanceName
                                Database     = $db.name
                                Status       = "Dropped"
                            }
                        }
                    } catch {
                        Write-Message -Level Verbose -Message "Could not drop database $db on $server"

                        [PSCustomObject]@{
                            ComputerName = $server.ComputerName
                            InstanceName = $server.ServiceName
                            SqlInstance  = $server.DomainInstanceName
                            Database     = $db.name
                            Status       = (Get-ErrorMessage -Record $_)
                        }
                    }
                }
            }
        }
    }
}