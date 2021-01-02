function Get-BackupAncientHistory {
    <#
        .SYNOPSIS
            Returns details of the last full backup of a SQL Server 2000 database

        .DESCRIPTION
            Backup History command to pull limited history from a SQL 2000 instance. If not using SQL 2000, please use Get-DbaDbBackupHistory which pulls more infomation, and has more options. This is just here to cope with 2k and copy-DbaDatabase issues

        .PARAMETER SqlInstance
            SQL Server name or SMO object representing the SQL Server to connect to. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

        .PARAMETER Credential
            Credential object used to connect to the SQL Server Instance as a different user. This can be a Windows or SQL Server account. Windows users are determined by the existence of a backslash, so if you are intending to use an alternative Windows connection instead of a SQL login, ensure it contains a backslash.

        .PARAMETER Database
            Specifies one or more database(s) to process. If unspecified, all databases will be processed.

        .NOTES
        Author: Stuart Moore (@napalmgram), stuart-moore.com

        dbatools PowerShell module (https://dbatools.io)
       Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    #>
    [CmdletBinding(DefaultParameterSetName = "Default")]
    param (
        [parameter(Mandatory)]
        [DbaInstanceParameter]$SqlInstance,
        [PsCredential]$SqlCredential,
        [object[]]$Database,
        [string]$FileNameStub,
        [switch]$EnableException
    )
    begin {
        try {
            $server = Connect-SqlInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
        } catch {
            Stop-Function -Message "Failed to process Instance $SqlInstance." -InnerErrorRecord $_ -Target $SqlInstance -Continue
        }
        if ($server.SoftwareVersionMajor -gt 8) {
            Write-Message -Level Warning -Message "This is not the function you're looking for. This is for SQL 2000 only, please use Get-DbaDbBackupHistory instead. It's much nicer"
        }

        $databases = @()
        if ($null -ne $Database) {
            ForEach ($db in $Database) {
                $databases += [PScustomObject]@{name = $db }
            }
        } else {
            $databases = $server.Databases
        }
    }

    process {
        foreach ($db in $Database) {
            Write-Message -Level Verbose -Message "Processing database $db"
            $sql = "
            SELECT
            a.Server,
             a.[Database],
             a.Username,
             a.Start,
             a.[End],
             a.Duration,
             a.[Path],
             a.Type,
            NULL as TotalSize,
             a.MediaSetId,
             a.BackupSetID,
             a.Software,
              a.position,
              a.first_lsn,
              a.database_backup_lsn,
              a.checkpoint_lsn,
              a.last_lsn,
             a.first_lsn as 'FirstLSN',
              a.database_backup_lsn as 'DatabaseBackupLsn',
              a.checkpoint_lsn as 'CheckpointLsn',
              a.last_lsn as 'Lastlsn',
              a.software_major_version,
             a.DeviceType,
                NULL as is_copy_only,
            NULL as last_recovery_fork_guid
            FROM (
            SELECT
              backupset.database_name AS [Database],
              backupset.user_name AS Username,
              backupset.backup_start_date AS Start,
              backupset.server_name as [Server],
              backupset.backup_finish_date AS [End],
              DATEDIFF(SECOND, backupset.backup_start_date, backupset.backup_finish_date) AS Duration,
              mediafamily.physical_device_name AS Path,
              CASE backupset.type
             WHEN 'L' THEN 'Log'
             WHEN 'D' THEN 'Full'
             WHEN 'F' THEN 'File'
             WHEN 'I' THEN 'Differential'
             WHEN 'G' THEN 'Differential File'
             WHEN 'P' THEN 'Partial Full'
             WHEN 'Q' THEN 'Partial Differential'
             ELSE NULL
              END AS Type,
              backupset.media_set_id AS MediaSetId,
              mediafamily.media_family_id as mediafamilyid,
              backupset.backup_set_id as BackupSetID,
              CASE mediafamily.device_type
             WHEN 2 THEN 'Disk'
             WHEN 102 THEN 'Permanent Disk Device'
             WHEN 5 THEN 'Tape'
             WHEN 105 THEN 'Permanent Tape Device'
             WHEN 6 THEN 'Pipe'
             WHEN 106 THEN 'Permanent Pipe Device'
             WHEN 7 THEN 'Virtual Device'
             ELSE 'Unknown'
             END AS DeviceType,
              backupset.position,
              backupset.first_lsn,
              backupset.database_backup_lsn,
              backupset.checkpoint_lsn,
              backupset.last_lsn,
              backupset.software_major_version,
              mediaset.software_name AS Software
            FROM msdb..backupmediafamily AS mediafamily
            JOIN msdb..backupmediaset AS mediaset
              ON mediafamily.media_set_id = mediaset.media_set_id
            JOIN msdb..backupset AS backupset
              ON backupset.media_set_id = mediaset.media_set_id
            WHERE backupset.database_name = '$db'
                    ) AS a
            where  a.backupsetid in (Select max(backup_set_id) from msdb..backupset where database_name='$db')"
            Write-Message -Level Debug -Message $sql
            $results = $server.ConnectionContext.ExecuteWithResults($sql).Tables.Rows | Select-Object * -ExcludeProperty BackupSetRank, RowError, Rowstate, table, itemarray, haserrors
            Write-Message -Level SomewhatVerbose -Message "Processing as grouped output."
            $GroupedResults = $results | Group-Object -Property backupsetid
            Write-Message -Level SomewhatVerbose -Message "$($GroupedResults.Count) result-groups found."
            $groupResults = @()
            foreach ($group in $GroupedResults) {

                $fileSql = "select file_type as FileType, logical_name as LogicalName, physical_name as PhysicalName
                            from msdb.dbo.backupfile where backup_set_id='$($Group.group[0].BackupSetID)'"

                Write-Message -Level Debug -Message "FileSQL: $fileSql"

                $historyObject = New-Object Sqlcollaborative.Dbatools.Database.BackupHistory
                $historyObject.ComputerName = $server.ComputerName
                $historyObject.InstanceName = $server.ServiceName
                $historyObject.SqlInstance = $server.DomainInstanceName
                $historyObject.Database = $group.Group[0].Database
                $historyObject.UserName = $group.Group[0].UserName
                $historyObject.Start = ($group.Group.Start | Measure-Object -Minimum).Minimum
                $historyObject.End = ($group.Group.End | Measure-Object -Maximum).Maximum
                $historyObject.Duration = New-TimeSpan -Seconds ($group.Group.Duration | Measure-Object -Maximum).Maximum
                $historyObject.Path = $group.Group.Path
                $historyObject.TotalSize = $NULL
                $historyObject.Type = $group.Group[0].Type
                $historyObject.BackupSetId = $group.Group[0].BackupSetId
                $historyObject.DeviceType = $group.Group[0].DeviceType
                $historyObject.Software = $group.Group[0].Software
                $historyObject.FullName = $group.Group.Path
                $historyObject.FileList = $server.ConnectionContext.ExecuteWithResults($fileSql).Tables.Rows
                $historyObject.Position = $group.Group[0].Position
                $historyObject.FirstLsn = $group.Group[0].First_LSN
                $historyObject.DatabaseBackupLsn = $group.Group[0].database_backup_lsn
                $historyObject.CheckpointLsn = $group.Group[0].checkpoint_lsn
                $historyObject.LastLsn = $group.Group[0].Last_Lsn
                $historyObject.SoftwareVersionMajor = $group.Group[0].Software_Major_Version
                $historyObject.IsCopyOnly = if ($group.Group[0].is_copy_only -eq 1) {
                    $true
                } else {
                    $false
                }
                $groupResults += $historyObject
            }
            $groupResults | Sort-Object -Property LastLsn, Type
        }

    }

    END { }
}