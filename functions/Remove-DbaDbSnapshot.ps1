#ValidationTags#FlowControl#
function Remove-DbaDbSnapshot {
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

    .PARAMETER InputObject
        Enables input from Get-DbaDbSnapshot

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
         https://dbatools.io/Remove-DbaDbSnapshot

    .EXAMPLE
        Remove-DbaDbSnapshot -SqlInstance sqlserver2014a

        Removes all database snapshots from sqlserver2014a

    .EXAMPLE
        Remove-DbaDbSnapshot -SqlInstance sqlserver2014a -Snapshot HR_snap_20161201, HR_snap_20161101

        Removes database snapshots named HR_snap_20161201 and HR_snap_20161101

    .EXAMPLE
        Remove-DbaDbSnapshot -SqlInstance sqlserver2014a -Database HR, Accounting

        Removes all database snapshots having HR and Accounting as base dbs

    .EXAMPLE
        Remove-DbaDbSnapshot -SqlInstance sqlserver2014a -Snapshot HR_snapshot, Accounting_snapshot

        Removes HR_snapshot and Accounting_snapshot

    .EXAMPLE
        Get-DbaDbSnapshot -SqlInstance sql2016 | Where SnapshotOf -like '*dumpsterfire*' | Remove-DbaDbSnapshot

        Removes all snapshots associated with databases that have dumpsterfire in the name

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
            Stop-Function -Message "You must pipe in a snapshot or specify -Snapshot, -Database, -Exclude or -AllSnapshots"
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

            $InputObject += Get-DbaDbSnapshot -SqlInstance $server -Database $Database -ExcludeDatabase $ExcludeDatabase -Snapshot $Snapshot
        }

        foreach ($db in $InputObject) {
            try {
                $server = $db.Parent
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
            if ($Force) {
                $db | Remove-DbaDatabase -Confirm:$confirm | Select-DefaultView -Property $defaultprops
            }
            else {
                try {
                    if ($Pscmdlet.ShouldProcess("$db on $server", "SMO drop")) {
                        $db.Drop()
                        $server.Refresh()

                        [pscustomobject]@{
                            ComputerName   = $server.NetName
                            InstanceName   = $server.ServiceName
                            SqlInstance    = $server.DomainInstanceName
                            Database       = $db.name
                            Status         = "Dropped"
                        } | Select-DefaultView -Property $defaultprops
                    }
                }
                catch {
                    Write-Message -Level Verbose -Message "Could not drop database $db on $server"

                    [pscustomobject]@{
                        ComputerName   = $server.NetName
                        InstanceName   = $server.ServiceName
                        SqlInstance    = $server.DomainInstanceName
                        Database       = $db.name
                        Status         = (Get-ErrorMessage -Record $_)
                    } | Select-DefaultView -Property $defaultprops
                }
            }
        }
    }
    end {
        Test-DbaDeprecation -DeprecatedOn "1.0.0" -Alias Remove-DbaDatabaseSnapshot
    }
}