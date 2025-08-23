function Remove-DbaDbSnapshot {
    <#
    .SYNOPSIS
        Drops database snapshots from SQL Server instances

    .DESCRIPTION
        Removes database snapshots by executing DROP DATABASE statements against the target SQL Server instances. Database snapshots are point-in-time, read-only copies of databases that consume minimal space through copy-on-write technology. This function helps DBAs clean up obsolete snapshots that are no longer needed for reporting, testing, or recovery purposes. The Force parameter can terminate active connections to snapshots that might otherwise prevent the drop operation from succeeding.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies the base database(s) whose snapshots should be removed. Only snapshots created from these source databases will be dropped.
        Use this when you need to clean up snapshots for specific databases while leaving other snapshots intact.

    .PARAMETER ExcludeDatabase
        Excludes snapshots from the specified base database(s) from removal. All other snapshots on the instance will be removed.
        Use this when you want to remove most snapshots but preserve those from critical databases.

    .PARAMETER Snapshot
        Specifies the exact snapshot name(s) to remove. Accepts multiple snapshot names for targeted removal operations.
        Use this when you know the specific snapshot names you want to drop, such as outdated test or reporting snapshots.

    .PARAMETER AllSnapshots
        Removes all database snapshots found on the target SQL Server instance(s). This affects every snapshot regardless of source database.
        Use this for complete snapshot cleanup operations, typically during maintenance windows or server decommissioning.

    .PARAMETER Force
        Terminates active connections and running queries against snapshots to allow the drop operation to complete successfully.
        Use this when snapshots have active sessions that would normally block the removal process.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run

    .PARAMETER Confirm
        Prompts for confirmation of every step.

    .PARAMETER InputObject
        Accepts database snapshot objects from Get-DbaDbSnapshot for pipeline operations. This allows filtering and processing snapshots before removal.
        Use this for complex filtering scenarios where you first identify specific snapshots with Get-DbaDbSnapshot.

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
        PS C:\> Get-DbaDbSnapshot -SqlInstance sql2016 | Out-GridView -PassThru | Remove-DbaDbSnapshot

        Allows the selection of snapshots on sql2016 to remove

    .EXAMPLE
        PS C:\> Remove-DbaDbSnapshot -SqlInstance sql2014 -AllSnapshots

        Removes all database snapshots from sql2014

    .EXAMPLE
        PS C:\> Remove-DbaDbSnapshot -SqlInstance sql2014 -AllSnapshots -Confirm

        Removes all database snapshots from sql2014 and prompts for each database

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High")]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [string[]]$ExcludeDatabase,
        [string[]]$Snapshot,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [switch]$AllSnapshots,
        [switch]$Force,
        [switch]$EnableException
    )
    begin {
        if ($Force) { $ConfirmPreference = 'none' }

        $defaultProps = 'ComputerName', 'InstanceName', 'SqlInstance', 'Database as Name', 'Status'
    }
    process {
        if (!$Snapshot -and !$Database -and !$AllSnapshots -and $null -eq $InputObject -and !$ExcludeDatabase) {
            Stop-Function -Message "You must pipe in a snapshot or specify -Snapshot, -Database, -ExcludeDatabase or -AllSnapshots"
            return
        }

        # if piped value either doesn't exist or is not the proper type
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $InputObject += Get-DbaDbSnapshot -SqlInstance $server -Database $Database -ExcludeDatabase $ExcludeDatabase -Snapshot $Snapshot
        }

        foreach ($db in $InputObject) {
            $server = $db.Parent

            if (-not $db.DatabaseSnapshotBaseName) {
                Stop-Function -Message "$db on $server is not a database snapshot" -Continue
            }

            if ($Force) {
                $db | Remove-DbaDatabase -Confirm:$false | Select-DefaultView -Property $defaultProps
            } else {
                try {
                    if ($PsCmdlet.ShouldProcess("$db on $server", "Drop snapshot")) {
                        $db.Drop()
                        $server.Refresh()

                        [PSCustomObject]@{
                            ComputerName = $server.ComputerName
                            InstanceName = $server.ServiceName
                            SqlInstance  = $server.DomainInstanceName
                            Database     = $db.name
                            Status       = "Dropped"
                        } | Select-DefaultView -Property $defaultProps
                    }
                } catch {
                    Write-Message -Level Verbose -Message "Could not drop database $db on $server"

                    [PSCustomObject]@{
                        ComputerName = $server.ComputerName
                        InstanceName = $server.ServiceName
                        SqlInstance  = $server.DomainInstanceName
                        Database     = $db.name
                        Status       = (Get-ErrorMessage -Record $_)
                    } | Select-DefaultView -Property $defaultProps
                }
            }
        }
    }
}