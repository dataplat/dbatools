function Get-DbaBackupRestoreProgress {
    <#
    .SYNOPSIS
        Returns all active BACKUP and RESTORE operations

    .DESCRIPTION
        Returns all active BACKUP and RESTORE operations on the provided instance(s)

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Backup, Restore, ETA
        Author: M. Boomaars

        Copyright: (c) 2021 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaBackupRestoreProgress

    .EXAMPLE
        PS C:\> Get-DbaBackupRestoreProgress -SqlInstance sql2017

        Returns all active BACKUP and RESTORE operations on SQL Server instance 2017

    .EXAMPLE
        PS C:\> Get-DbaBackupRestoreProgress -SqlInstance sql2017 -SqlCredential sqladmin

        Returns all active BACKUP and RESTORE operations on SQL Server instance 2017 using login 'sqladmin'

    .EXAMPLE
        PS C:\> Get-DbaBackupRestoreProgress -SqlInstance sql2017,sql2019 | where {$_.Command -like 'RESTORE*'} | ft -AutoSize

        Returns all active RESTORE operations on SQL Server instances 2017 and 2019

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [switch]$EnableException
    )
    begin {
        $sql = "SELECT
                    SERVERPROPERTY('MachineName') AS ComputerName,
                    ISNULL(SERVERPROPERTY('InstanceName'), 'MSSQLSERVER') AS InstanceName,
                    SERVERPROPERTY('ServerName') AS SqlInstance,
                    r.session_id AS SessionId,
                    r.command AS Command,
                    CONVERT (NUMERIC(6, 2), r.percent_complete) AS [PercentComplete],
                    CONVERT (NUMERIC(6, 2), r.total_elapsed_time / 1000.0 / 60.0) AS Elapsed_Min,
                    CONVERT (NUMERIC(6, 2), r.total_elapsed_time / 1000.0 / 60.0 / 60.0) AS Elapsed_Hrs,
                    CONVERT (VARCHAR(20), DATEADD (ms, r.estimated_completion_time, GETDATE ()), 20) AS ETA,
                    CONVERT (NUMERIC(6, 2), r.estimated_completion_time / 1000.0 / 60.0) AS ETA_Min,
                    CONVERT (NUMERIC(6, 2), r.estimated_completion_time / 1000.0 / 60.0 / 60.0) AS ETA_Hrs,
                    CONVERT (VARCHAR(100), (SELECT SUBSTRING (text, r.statement_start_offset / 2, CASE WHEN r.statement_end_offset = -1 THEN 1000 ELSE (r.statement_end_offset - r.statement_start_offset) / 2 END) FROM sys.dm_exec_sql_text (sql_handle))) AS Stmt
            FROM sys.dm_exec_requests AS r
            WHERE Command IN ( 'RESTORE DATABASE', 'BACKUP DATABASE', 'RESTORE LOG' );"
    }

    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            foreach ($row in $server.Query($sql)) {
                [PSCustomObject]@{
                    ComputerName    = $server.NetName
                    InstanceName    = $server.ServiceName
                    SqlInstance     = $server.DomainInstanceName
                    SessionId       = $row.SessionId
                    Command         = $row.Command
                    PercentComplete = $row.PercentComplete
                    Elapsed_Min     = $row.Elapsed_Min
                    Elapsed_Hrs     = $row.Elapsed_Hrs
                    ETA             = $row.ETA
                    ETA_Min         = $row.ETA_Min
                    ETA_Hrs         = $row.ETA_Hrs
                    Stmt            = $row.Stmt
                }
            }
        }
    }
}