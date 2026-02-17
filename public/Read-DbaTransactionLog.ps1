function Read-DbaTransactionLog {
    <#
    .SYNOPSIS
        Retrieves raw transaction log records from a database using fn_dblog for forensic analysis and troubleshooting

    .DESCRIPTION
        Uses SQL Server's built-in fn_dblog function to extract raw transaction log records from a live database, returning detailed information about every transaction in the format used by the SQL Server logging subsystem. This gives you access to the same low-level data that SQL Server uses internally to track database changes.

        This is primarily useful for forensic analysis when you need to understand exactly what happened to your data - like tracking down who deleted records, when specific changes occurred, or analyzing transaction patterns for troubleshooting performance issues. The raw log data includes LSN numbers, transaction IDs, operation types, and other metadata that can help reconstruct the sequence of database modifications.

        A safety limit of 0.5GB has been implemented to prevent performance issues, since reading large transaction logs can impact both the target database and the system running this command. This limit is based on testing and can be overridden using the -IgnoreLimit switch, but be aware that processing very large logs may cause performance degradation on your SQL Server instance.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies the database whose transaction log records you want to analyze. The database must be online and in a normal state.
        Use this to target the specific database where you need to investigate transaction activity or perform forensic analysis.

    .PARAMETER IgnoreLimit
        Bypasses the built-in 0.5GB safety limit that prevents performance issues when reading large transaction logs.
        Use this when you need to analyze databases with large active logs, but be aware it may impact SQL Server performance during execution.

    .PARAMETER RowLimit
        Limits the number of transaction log records returned by adding a TOP clause to the fn_dblog query.
        Use this when you only need recent transactions or want to prevent memory issues with very large logs. Automatically enables IgnoreLimit when specified.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .OUTPUTS
        System.Data.DataRow

        Returns zero or more DataRow objects representing transaction log records from the fn_dblog function. Each object represents one transaction log record with all columns from fn_dblog as individual properties.

        Common properties include:
        - RecoveryUnitId: Identifier of the recovery unit
        - LSN: Log Sequence Number identifying the position in the transaction log
        - LOP: The log operation type (e.g., INSERT, DELETE, UPDATE, ALLOCATE, DEALLOCATE, etc.)
        - Transaction ID: The transaction identifier
        - BeginTime: When the operation began
        - AllocUnitName: Name of the allocation unit affected
        - RowIdentifier: Identifies the specific row affected
        - DBFragId: Database fragmentation identifier
        - XactId: Extended transaction ID
        - XactOp: Extended transaction operation
        - Context: Operation context flags
        - AllocUnitId: Identifier of the allocation unit
        - ObjectId: Object ID of the table or index
        - IndexId: Index ID if applicable
        - PrevPageLSN: LSN of the previous page in the log chain
        - PageId: Page ID affected by the operation

        The exact set of columns depends on SQL Server version and the specific operations recorded in the transaction log. Use Select-Object * to see all available properties.

    .NOTES
        Tags: Log, LogFile, Utility
        Author: Stuart Moore (@napalmgram), stuart-moore.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Read-DbaTransactionLog

    .EXAMPLE
        PS C:\> $Log = Read-DbaTransactionLog -SqlInstance sql2016 -Database MyDatabase

        Will read the contents of the transaction log of MyDatabase on SQL Server Instance sql2016 into the local PowerShell object $Log

    .EXAMPLE
        PS C:\> $Log = Read-DbaTransactionLog -SqlInstance sql2016 -Database MyDatabase -IgnoreLimit

        Will read the contents of the transaction log of MyDatabase on SQL Server Instance sql2016 into the local PowerShell object $Log, ignoring the recommendation of not returning more that 0.5GB of log

    #>
    [CmdletBinding(DefaultParameterSetName = "Default")]
    param (
        [parameter(Mandatory)]
        [DbaInstanceParameter]$SqlInstance,
        [PSCredential]$SqlCredential,
        [parameter(Mandatory)]
        [object]$Database,
        [Switch]$IgnoreLimit,
        [int]$RowLimit = 0,
        [switch]$EnableException
    )

    try {
        $server = Connect-DbaInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
    } catch {
        Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $SqlInstance
        return
    }

    if (-not $server.databases[$Database]) {
        Stop-Function -Message "$Database does not exist"
        return
    }

    if ('Normal' -notin ($server.databases[$Database].Status -split ',')) {
        Stop-Function -Message "$Database is not in a normal State, command will not run."
        return
    }

    if ($RowLimit -gt 0) {
        Write-Message -Message "Limiting results to $RowLimit rows" -Level Verbose
        $RowLimitSql = " TOP $RowLimit "
        $IgnoreLimit = $true
    } else {
        $RowLimitSql = ""
    }


    if ($IgnoreLimit) {
        Write-Message -Level Verbose -Message "Please be aware that ignoring the recommended limits may impact on the performance of the SQL Server database and the calling system"
    } else {
        #Warn if more than 0.5GB of live log. Dodgy conversion as SMO returns the value in an unhelpful format :(
        $SqlSizeCheck = "SELECT
                                SUM(FileProperty(sf.name,'spaceused')*8/1024) AS 'SizeMb'
                                FROM sys.sysfiles sf
                                WHERE CONVERT(INT,sf.status & 0x40) / 64=1"
        $TransLogSize = $server.Query($SqlSizeCheck, $Database)
        if ($TransLogSize.SizeMb -ge 500) {
            Stop-Function -Message "$Database has more than 0.5 Gb of live log data, returning this may have an impact on the database and the calling system. If you wish to proceed please rerun with the -IgnoreLimit switch"
            return
        }
    }

    $sql = "SELECT $RowLimitSql * FROM fn_dblog(NULL,NULL)"
    Write-Message -Level Debug -Message $sql
    Write-Message -Level Verbose -Message "Starting Log retrieval"
    $server.Query($sql, $Database)

}