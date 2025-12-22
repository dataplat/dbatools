function Get-RestoreContinuableDatabase {
    <#
    .SYNOPSIS
    Gets a list of databases from a SQL instance that are in a state for further restores

    .DESCRIPTION
    Takes a SQL instance and checks for databases with a redo_start_lsn value, and returns the database name and that value
    -gt SQl 2005 it comes from master.sys.master_files
    -eq SQL 2000 DBCC DBINFO
    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [object]$SqlInstance,
        [PSCredential]$SqlCredential,
        [switch]$EnableException
    )

    try {
        $server = Connect-DbaInstance -Sqlinstance $SqlInstance -SqlCredential $SqlCredential
    } catch {
        Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $SqlInstance
        return
    }
    if ($server.VersionMajor -ge 9) {
        $sql = "SELECT DB_NAME(database_id) AS 'Database', MIN(differential_base_lsn) AS differential_base_lsn, MIN(redo_start_lsn) AS redo_start_lsn, redo_start_fork_guid AS 'FirstRecoveryForkID' FROM sys.master_files WHERE redo_start_lsn IS NOT NULL GROUP BY database_id, redo_start_fork_guid"
    } else {
        $sql = "
              CREATE TABLE #db_info
                (
                ParentObject NVARCHAR(128) COLLATE database_default ,
                Object       NVARCHAR(128) COLLATE database_default,
                Field        NVARCHAR(128) COLLATE database_default,
                Value        SQL_VARIANT
                )"
    }
    $server.ConnectionContext.ExecuteWithResults($sql).Tables.Rows
}