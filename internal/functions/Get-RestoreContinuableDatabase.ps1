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
        $Server = Connect-SqlInstance -Sqlinstance $SqlInstance -SqlCredential $SqlCredential
    } catch {
        Write-Message -Level Warning -Message "Cannot connect to $SqlInstance"
        break
    }
    if ($Server.VersionMajor -ge 9) {
        $sql = "select distinct db_name(database_id) as 'Database', differential_base_lsn, redo_start_lsn, redo_start_fork_guid as 'FirstRecoveryForkID' from master.sys.master_files where redo_start_lsn is not NULL"
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