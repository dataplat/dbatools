function Get-DbaDbSnapshot {
    <#
    .SYNOPSIS
        Retrieves database snapshots with their source databases, creation times, and disk usage

    .DESCRIPTION
        Collects information about all database snapshots on a SQL Server instance, showing which database each snapshot was created from, when it was created, and how much disk space it's consuming. This is useful for snapshot management, cleanup activities, and monitoring storage usage of point-in-time database copies. You can filter results by specific base databases or snapshot names to focus on particular snapshots of interest.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Filters results to snapshots created from specific base databases. Use this when you want to see all snapshots created from particular source databases like 'HR' or 'Accounting'.
        Accepts multiple database names and is useful for focusing on snapshots from databases you're actively managing.

    .PARAMETER ExcludeDatabase
        Excludes snapshots created from specific base databases from the results. Use this to filter out snapshots from databases you don't want to see, such as system databases or databases managed by other teams.
        Helpful when you want a comprehensive view but need to omit certain source databases from the output.

    .PARAMETER Snapshot
        Returns information for specific database snapshots by their snapshot names. Use this when you need details about particular snapshots like 'HR_BeforeUpdate_20240101' or 'Production_Backup_Snapshot'.
        Accepts multiple snapshot names and is ideal for checking the status or disk usage of known snapshots.

    .PARAMETER ExcludeSnapshot
        Excludes specific database snapshots from the results by their snapshot names. Use this to filter out snapshots you don't want to see in the output, such as automated system snapshots or snapshots from other environments.
        Helpful for focusing on production snapshots while excluding development or test snapshots.

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
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
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
                    $BytesOnDisk = $db.Query("SELECT SUM(BytesOnDisk) AS BytesOnDisk FROM fn_virtualfilestats(DB_ID(),NULL) S JOIN sys.databases D ON D.database_id = S.dbid", $db.Name)
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