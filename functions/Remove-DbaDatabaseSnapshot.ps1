#ValidationTags#FlowControl#
function Remove-DbaDatabaseSnapshot {
    <#
    .SYNOPSIS
        Removes database snapshots

    .DESCRIPTION
        Removes (drops) database snapshots from the server

    .PARAMETER SqlInstance
        The SQL Server that you're connecting to

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

    .PARAMETER PipelineSnapshot
        Internal parameter

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Snapshot, Database
        Author: niphlod

        Website: https://dbatools.io
        Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
        License: MIT https://opensource.org/licenses/MIT

    .LINK
         https://dbatools.io/Remove-DbaDatabaseSnapshot

    .EXAMPLE
        Remove-DbaDatabaseSnapshot -SqlInstance sqlserver2014a

        Removes all database snapshots from sqlserver2014a

    .EXAMPLE
        Remove-DbaDatabaseSnapshot -SqlInstance sqlserver2014a -Snapshot HR_snap_20161201, HR_snap_20161101

        Removes database snapshots named HR_snap_20161201 and HR_snap_20161101

    .EXAMPLE
        Remove-DbaDatabaseSnapshot -SqlInstance sqlserver2014a -Database HR, Accounting

        Removes all database snapshots having HR and Accounting as base dbs

    .EXAMPLE
        Remove-DbaDatabaseSnapshot -SqlInstance sqlserver2014a -Snapshot HR_snapshot, Accounting_snapshot

        Removes HR_snapshot and Accounting_snapshot

    .EXAMPLE
        Get-DbaDatabaseSnapshot -SqlInstance sql2016 | Where SnapshotOf -like '*dumpsterfire*' | Remove-DbaDatabaseSnapshot

        Removes all snapshots associated with databases that have dumpsterfire in the name

#>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [parameter(Mandatory = $false, ValueFromPipeline = $true)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [Alias("Credential")]
        [PSCredential]
        $SqlCredential,
        [Alias("Databases")]
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [object[]]$Snapshot,
        [parameter(ValueFromPipeline = $true)]
        [object]$PipelineSnapshot,
        [switch]$AllSnapshots,
        [switch]$Force,
        [Alias('Silent')]
        [switch]$EnableException
    )

    process {
        if (!$Snapshot -and !$Database -and !$AllSnapshots -and $null -eq $PipelineSnapshot -and !$ExcludeDatabase) {
            Stop-Function -Message "You must specify -Snapshot, -Database, -Exclude or -AllSnapshots"
            return
        }
        # handle the database object passed by the pipeline
        # do we need a specialized type back ?
        if ($null -ne $PipelineSnapshot -and $PipelineSnapshot.getType().Name -eq 'pscustomobject') {
            if ($Pscmdlet.ShouldProcess($PipelineSnapshot.SnapshotDb.Parent.DomainInstanceName, "Remove db snapshot $($PipelineSnapshot.SnapshotDb.Name)")) {
                try {
                    $server = $PipelineSnapshot.SnapshotDb.Parent
                }
                catch {
                    Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
                }
                try {
                    if ($Force) {
                        $server.KillAllProcesses($PipelineSnapshot.SnapshotDb.Name)
                    }
                    $null = $server.Query("drop database [$($PipelineSnapshot.SnapshotDb.Name)]")
                    $status = "Dropped"
                }
                catch {
                    Write-Message -Level Warning -Message $_
                    $status = "Drop failed"
                }

                [PSCustomObject]@{
                    ComputerName = $PipelineSnapshot.SnapshotDb.Parent.NetName
                    InstanceName = $PipelineSnapshot.SnapshotDb.Parent.ServiceName
                    SqlInstance  = $PipelineSnapshot.SnapshotDb.Parent.DomainInstanceName
                    Database     = $PipelineSnapshot.Database
                    SnapshotOf   = $PipelineSnapshot.SnapshotOf
                    Status       = $status
                }
            }
            return
        }

        # if piped value either doesn't exist or is not the proper type
        foreach ($instance in $SqlInstance) {
            Write-Message -Level Verbose -Message "Connecting to $instance"
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }


            $alldbq = @"
SELECT sn.name AS Name, dt.name AS DatabaseSnapshotBaseName, sn.create_date AS CreateDate,
CASE WHEN sn.state = 6 THEN 0 ELSE 1 END AS IsAccessible,
CASE WHEN sn.source_database_id IS NOT NULL THEN 1 ELSE 0 END AS IsDatabaseSnapshot
FROM sys.databases sn
LEFT JOIN sys.databases dt
ON sn.source_database_id = dt.database_id
"@
            $dbs = $server.Query($alldbq)
            if ($Database) {
                $dbs = $dbs | Where-Object { $Database -contains $_.DatabaseSnapshotBaseName }
            }

            if ($ExcludeDatabase) {
                $dbs = $dbs | Where-Object { $ExcludeDatabase -notcontains $_.DatabaseSnapshotBaseName }
            }

            if ($Snapshot) {
                $dbs = $dbs | Where-Object { $Snapshot -contains $_.Name }
            }

            if (!$Snapshot -and !$Database) {
                $dbs = $dbs | Where-Object IsDatabaseSnapshot -eq $true | Sort-Object DatabaseSnapshotBaseName, Name
            }


            foreach ($dbraw in $dbs) {
                if ($dbraw.IsAccessible -eq $false) {
                    Write-Message -Level Warning -Message "Database $dbraw is not accessible."
                    continue
                }
                $db = $server.Databases[$($dbraw.Name)]
                if ($Pscmdlet.ShouldProcess($server.name, "Remove db snapshot $db")) {
                    $basedb = $db.DatabaseSnapshotBaseName
                    try {
                        if ($Force) {
                            # cannot drop the snapshot if someone is using it
                            $server.KillAllProcesses($db)
                        }
                        $null = $server.Query("drop database $db")
                        $status = "Dropped"
                    }
                    catch {
                        Write-Message -Level Warning -Message $_
                        $status = "Drop failed"
                    }
                    [PSCustomObject]@{
                        ComputerName = $server.NetName
                        InstanceName = $server.ServiceName
                        SqlInstance  = $server.DomainInstanceName
                        Database     = $db
                        SnapshotOf   = $basedb
                        Status       = $status
                    }
                }
            }
        }
    }
}

