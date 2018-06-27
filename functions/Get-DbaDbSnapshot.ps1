#ValidationTags#Messaging,FlowControl,Pipeline,CodeStyle#
function Get-DbaDbSnapshot {
    <#
    .SYNOPSIS
        Get database snapshots with details

    .DESCRIPTION
        Retrieves the list of database snapshot available, along with their base (the db they are the snapshot of) and creation time

    .PARAMETER SqlInstance
        The SQL Server that you're connecting to.

    .PARAMETER SqlCredential
        Credential object used to connect to the SQL Server as a different user

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
        Author: niphlod

        Website: https://dbatools.io
        Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
        License: MIT https://opensource.org/licenses/MIT


    .LINK
         https://dbatools.io/Get-DbaDbSnapshot

    .EXAMPLE
        Get-DbaDbSnapshot -SqlInstance sqlserver2014a

        Returns a custom object displaying Server, Database, DatabaseCreated, SnapshotOf, SizeMB, DatabaseCreated

    .EXAMPLE
        Get-DbaDbSnapshot -SqlInstance sqlserver2014a -Database HR, Accounting

        Returns information for database snapshots having HR and Accounting as base dbs

    .EXAMPLE
        Get-DbaDbSnapshot -SqlInstance sqlserver2014a -Snapshot HR_snapshot, Accounting_snapshot

        Returns information for database snapshots HR_snapshot and Accounting_snapshot

#>
    [CmdletBinding()]
    param (
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [Alias("Credential")]
        [PSCredential]$SqlCredential,
        [Alias("Databases")]
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [object[]]$Snapshot,
        [object[]]$ExcludeSnapshot,
        [Alias('Silent')]
        [switch]$EnableException
    )

    process {
        foreach ($instance in $SqlInstance) {
            Write-Message -Level Verbose -Message "Connecting to $instance"
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            }
            catch {
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
                    if ($db.Parent.VersionMajor -ge 10) {
                        $BytesOnDisk = $db.Query("select top 1 BytesOnDisk from fn_virtualfilestats(db_id('$($db.Name)'),null) S JOIN dbo.sysdatabases D on D.dbid = S.dbid")
                    }
                    else {
                        $BytesOnDisk = $db.Query("select top 1 BytesOnDisk from fn_virtualfilestats(db_id('$($db.Name)'),null) S JOIN sys.databases D on D.database_id = S.dbid")
                    }
                    Add-Member -Force -InputObject $db -MemberType NoteProperty -Name ComputerName -value $server.NetName
                    Add-Member -Force -InputObject $db -MemberType NoteProperty -Name InstanceName -value $server.ServiceName
                    Add-Member -Force -InputObject $db -MemberType NoteProperty -Name SqlInstance -value $server.DomainInstanceName
                    Add-Member -Force -InputObject $db -MemberType NoteProperty -Name DiskUsage -value ([dbasize]($BytesOnDisk.BytesOnDisk))
                    Select-DefaultView -InputObject $db -Property ComputerName, InstanceName, SqlInstance, Name, 'DatabaseSnapshotBaseName as SnapshotOf', CreateDate, DiskUsage
                }
                catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_ -Target $db -Continue
                }
            }
        }
    }
    end {
        Test-DbaDeprecation -DeprecatedOn "1.0.0" -Alias Get-DbaDatabaseSnapshot
    }
}