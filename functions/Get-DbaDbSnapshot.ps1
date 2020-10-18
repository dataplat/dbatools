function Get-DbaDbSnapshot {
    <#
    .SYNOPSIS
        Get database snapshots with details

    .DESCRIPTION
        Retrieves the list of database snapshot available, along with their base (the db they are the snapshot of) and creation time

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Return information for only specific databases

    .PARAMETER ExcludeDatabase
        The database(s) to exclude - this list is auto-populated from the server

    .PARAMETER Snapshot
        Return information for only specific snapshots

    .PARAMETER ExcludeSnapshot
        The snapshot(s) to exclude - this list is auto-populated from the server

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Snapshot
        Author: Simone Bizzotto (@niphlod)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaDbSnapshot

    .EXAMPLE
        PS C:\> Get-DbaDbSnapshot -SqlInstance sqlserver2014a

        Returns a custom object displaying Server, Database, DatabaseCreated, SnapshotOf, SizeMB, DatabaseCreated

    .EXAMPLE
        PS C:\> Get-DbaDbSnapshot -SqlInstance sqlserver2014a -Database HR, Accounting

        Returns information for database snapshots having HR and Accounting as base dbs

    .EXAMPLE
        PS C:\> Get-DbaDbSnapshot -SqlInstance sqlserver2014a -Snapshot HR_snapshot, Accounting_snapshot

        Returns information for database snapshots HR_snapshot and Accounting_snapshot

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [object[]]$Snapshot,
        [object[]]$ExcludeSnapshot,
        [switch]$EnableException
    )
    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
            $dbs = $server.Databases | Where-Object DatabaseSnapshotBaseName
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
            if ($ExcludeSnapshot) {
                $dbs = $dbs | Where-Object { $ExcludeSnapshot -notcontains $_.Name }
            }
            foreach ($db in $dbs) {
                try {
                    $BytesOnDisk = $db.Query("SELECT SUM(BytesOnDisk) AS BytesOnDisk FROM fn_virtualfilestats(DB_ID(),NULL) S JOIN sys.databases D on D.database_id = S.dbid", $db.Name)
                    Add-Member -Force -InputObject $db -MemberType NoteProperty -Name ComputerName -value $server.ComputerName
                    Add-Member -Force -InputObject $db -MemberType NoteProperty -Name InstanceName -value $server.ServiceName
                    Add-Member -Force -InputObject $db -MemberType NoteProperty -Name SqlInstance -value $server.DomainInstanceName
                    Add-Member -Force -InputObject $db -MemberType NoteProperty -Name DiskUsage -value ([dbasize]($BytesOnDisk.BytesOnDisk))
                    Select-DefaultView -InputObject $db -Property ComputerName, InstanceName, SqlInstance, Name, 'DatabaseSnapshotBaseName as SnapshotOf', CreateDate, DiskUsage
                } catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_ -Target $db -Continue
                }
            }
        }
    }
}