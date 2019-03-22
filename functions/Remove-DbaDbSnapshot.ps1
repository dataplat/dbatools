#ValidationTags#Messaging,FlowControl,Pipeline,CodeStyle#
function Remove-DbaDbSnapshot {
    <#
    .SYNOPSIS
        Removes database snapshots

    .DESCRIPTION
        Removes (drops) database snapshots from the server

    .PARAMETER SqlInstance
        The target SQL Server instance or instances

    .PARAMETER SqlCredential
        Credential object used to connect to the SQL Server as a different user

    .PARAMETER Database
        Removes snapshots for only this specific base db

    .PARAMETER ExcludeDatabase
        Removes snapshots excluding this specific base dbs

    .PARAMETER Snapshot
        Restores databases from snapshot with this name only

    .PARAMETER AllSnapshots
        Specifies that you want to remove all snapshots from the server

    .PARAMETER Force
        Will forcibly kill all running queries that prevent the drop process.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run

    .PARAMETER Confirm
        Prompts for confirmation of every step.

    .PARAMETER InputObject
        Enables input from Get-DbaDbSnapshot

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Snapshot, Database
        Author: Simone Bizzotto (@niphold)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Remove-DbaDbSnapshot

    .EXAMPLE
        PS C:\> Remove-DbaDbSnapshot -SqlInstance sql2014 -Snapshot HR_snap_20161201, HR_snap_20161101

        Removes database snapshots named HR_snap_20161201 and HR_snap_20161101

    .EXAMPLE
        PS C:\> Remove-DbaDbSnapshot -SqlInstance sql2014 -Database HR, Accounting

        Removes all database snapshots having HR and Accounting as base dbs

    .EXAMPLE
        PS C:\> Get-DbaDbSnapshot -SqlInstance sql2014 -Database HR, Accounting | Remove-DbaDbSnapshot

        Removes all database snapshots having HR and Accounting as base dbs

    .EXAMPLE
        PS C:\> Remove-DbaDbSnapshot -SqlInstance sql2014 -Snapshot HR_snapshot, Accounting_snapshot

        Removes HR_snapshot and Accounting_snapshot

    .EXAMPLE
        PS C:\> Get-DbaDbSnapshot -SqlInstance sql2016 | Where-Object SnapshotOf -like '*dumpsterfire*' | Remove-DbaDbSnapshot

        Removes all snapshots associated with databases that have dumpsterfire in the name

    .EXAMPLE
        PS C:\> Get-DbaDbSnapshot -SqlInstance sql2016 | Out-GridView -Passthru | Remove-DbaDbSnapshot

        Allows the selection of snapshots on sql2016 to remove

    .EXAMPLE
        PS C:\> Remove-DbaDbSnapshot -SqlInstance sql2014 -AllSnapshots

        Removes all database snapshots from sql2014

    .EXAMPLE
        PS C:\> Remove-DbaDbSnapshot -SqlInstance sql2014 -AllSnapshots -Confirm

        Removes all database snapshots from sql2014 and prompts for each database

    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [Alias("Credential")]
        [PSCredential]$SqlCredential,
        [Alias("Databases")]
        [string[]]$Database,
        [string[]]$ExcludeDatabase,
        [string[]]$Snapshot,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [switch]$AllSnapshots,
        [switch]$Force,
        [Alias('Silent')]
        [switch]$EnableException
    )
    begin {
        $defaultprops = 'ComputerName', 'InstanceName', 'SqlInstance', 'Database as Name', 'Status'
    }
    process {
        if (!$Snapshot -and !$Database -and !$AllSnapshots -and $null -eq $InputObject -and !$ExcludeDatabase) {
            Stop-Function -Message "You must pipe in a snapshot or specify -Snapshot, -Database, -ExcludeDatabase or -AllSnapshots"
            return
        }

        # if piped value either doesn't exist or is not the proper type
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $InputObject += Get-DbaDbSnapshot -SqlInstance $server -Database $Database -ExcludeDatabase $ExcludeDatabase -Snapshot $Snapshot
        }

        foreach ($db in $InputObject) {
            $server = $db.Parent

            if (-not $db.DatabaseSnapshotBaseName) {
                Stop-Function -Message "$db on $server is not a database snapshot" -Continue
            }

            if ($Force) {
                $db | Remove-DbaDatabase -Confirm:$false | Select-DefaultView -Property $defaultprops
            } else {
                try {
                    if ($Pscmdlet.ShouldProcess("$db on $server", "Drop snapshot")) {
                        $db.Drop()
                        $server.Refresh()

                        [pscustomobject]@{
                            ComputerName = $server.ComputerName
                            InstanceName = $server.ServiceName
                            SqlInstance  = $server.DomainInstanceName
                            Database     = $db.name
                            Status       = "Dropped"
                        } | Select-DefaultView -Property $defaultprops
                    }
                } catch {
                    Write-Message -Level Verbose -Message "Could not drop database $db on $server"

                    [pscustomobject]@{
                        ComputerName = $server.ComputerName
                        InstanceName = $server.ServiceName
                        SqlInstance  = $server.DomainInstanceName
                        Database     = $db.name
                        Status       = (Get-ErrorMessage -Record $_)
                    } | Select-DefaultView -Property $defaultprops
                }
            }
        }
    }
    end {
        Test-DbaDeprecation -DeprecatedOn "1.0.0" -Alias Remove-DbaDatabaseSnapshot
    }
}