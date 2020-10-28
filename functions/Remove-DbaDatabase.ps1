function Remove-DbaDatabase {
    <#
    .SYNOPSIS
        Drops a user database, hopefully even the really stuck ones.

    .DESCRIPTION
        Tries a bunch of different ways to remove a user created database or two or more.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.You must have sysadmin access and server version must be SQL Server version 2000 or higher.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The database(s) to process - this list is auto-populated from the server. If unspecified, all databases will be processed.

    .PARAMETER InputObject
        A collection of databases (such as returned by Get-DbaDatabase), to be removed.

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
        [object[]]$Database,
        [Parameter(ValueFromPipeline, Mandatory, ParameterSetName = "databases")]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [switch]$EnableException
    )

    process {

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
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

                    [pscustomobject]@{
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

                        [pscustomobject]@{
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

                            [pscustomobject]@{
                                ComputerName = $server.ComputerName
                                InstanceName = $server.ServiceName
                                SqlInstance  = $server.DomainInstanceName
                                Database     = $db.name
                                Status       = "Dropped"
                            }
                        }
                    } catch {
                        Write-Message -Level Verbose -Message "Could not drop database $db on $server"

                        [pscustomobject]@{
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