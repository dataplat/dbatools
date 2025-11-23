function Get-DbaEstimatedCompletionTime {
    <#
    .SYNOPSIS
        Monitors progress and estimated completion times for long-running SQL Server operations

    .DESCRIPTION
        Retrieves real-time progress information for long-running SQL Server maintenance and administrative operations by querying sys.dm_exec_requests. This function helps DBAs monitor the status of time-intensive tasks without having to guess when they'll complete or manually check SQL Server Management Studio.

        Shows progress details including percent complete, running time, estimated time remaining, and projected completion time. Only returns operations that SQL Server can provide completion estimates for - quick queries and standard SELECT statements won't appear in the results.

        Percent complete will show for the following commands:

        ALTER INDEX REORGANIZE
        AUTO_SHRINK option with ALTER DATABASE
        BACKUP DATABASE
        DBCC CHECKDB
        DBCC CHECKFILEGROUP
        DBCC CHECKTABLE
        DBCC INDEXDEFRAG
        DBCC SHRINKDATABASE
        DBCC SHRINKFILE
        RECOVERY
        RESTORE DATABASE
        ROLLBACK
        TDE ENCRYPTION

        Particularly useful during scheduled maintenance windows, large database restores, or when troubleshooting performance issues where you need visibility into what's currently running and how much longer it will take.

        For additional information, check out https://blogs.sentryone.com/loriedwards/patience-dm-exec-requests/ and https://docs.microsoft.com/en-us/sql/relational-databases/system-dynamic-management-views/sys-dm-exec-requests-transact-sql

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        SqlLogin to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance..

    .PARAMETER Database
        Filters results to show only long-running operations within the specified database(s). Accepts multiple database names or wildcards.
        Use this when you need to monitor specific databases during maintenance windows or troubleshoot performance issues in particular databases.

    .PARAMETER ExcludeDatabase
        Excludes long-running operations from the specified database(s) when monitoring across the entire instance.
        Helpful when you want to monitor all databases except system databases or exclude databases with known maintenance operations.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Diagnostic, Query
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaEstimatedCompletionTime

    .EXAMPLE
        PS C:\> Get-DbaEstimatedCompletionTime -SqlInstance sql2016

        Gets estimated completion times for queries performed against the entire server

    .EXAMPLE
        PS C:\> Get-DbaEstimatedCompletionTime -SqlInstance sql2016 | Select-Object *

        Gets estimated completion times for queries performed against the entire server PLUS the SQL query text of each command

    .EXAMPLE
        PS C:\> Get-DbaEstimatedCompletionTime -SqlInstance sql2016 | Where-Object { $_.Text -match 'somequerytext' }

        Gets results for commands whose queries only match specific text (match is like LIKE but way more powerful)

    .EXAMPLE
        PS C:\> Get-DbaEstimatedCompletionTime -SqlInstance sql2016 -Database Northwind,pubs,Adventureworks2014

        Gets estimated completion times for queries performed against the Northwind, pubs, and Adventureworks2014 databases

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [switch]$EnableException
    )

    begin {
        $sql = "SELECT
                DB_NAME(r.database_id) AS [Database],
                USER_NAME(r.user_id) AS [Login],
                Command,
                start_time AS StartTime,
                percent_complete AS PercentComplete,

                  RIGHT('00000' + CAST(((DATEDIFF(s,start_time,GETDATE()))/3600) AS VARCHAR),
                                CASE
                                    WHEN LEN(((DATEDIFF(s,start_time,GETDATE()))/3600)) < 2 THEN 2
                                    ELSE LEN(((DATEDIFF(s,start_time,GETDATE()))/3600))
                                 END)  + ':'
                + RIGHT('00' + CAST((DATEDIFF(s,start_time,GETDATE())%3600)/60 AS VARCHAR), 2) + ':'
                + RIGHT('00' + CAST((DATEDIFF(s,start_time,GETDATE())%60) AS VARCHAR), 2) AS RunningTime,

                  RIGHT('00000' + CAST((estimated_completion_time/3600000) AS VARCHAR),
                        CASE
                                    WHEN LEN((estimated_completion_time/3600000)) < 2 THEN 2
                                    ELSE LEN((estimated_completion_time/3600000))
                         END)  + ':'
                + RIGHT('00' + CAST((estimated_completion_time %3600000)/60000 AS VARCHAR), 2) + ':'
                + RIGHT('00' + CAST((estimated_completion_time %60000)/1000 AS VARCHAR), 2) AS EstimatedTimeToGo,
                DATEADD(SECOND,estimated_completion_time/1000, GETDATE()) AS EstimatedCompletionTime,
                s.Text
             FROM sys.dm_exec_requests r
            CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) s
            WHERE r.estimated_completion_time > 0"
    }

    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if ($Database) {
                $includedatabases = $Database -join "','"
                $sql = "$sql AND DB_NAME(r.database_id) in ('$includedatabases')"
            }

            if ($ExcludeDatabase) {
                $excludedatabases = $ExcludeDatabase -join "','"
                $sql = "$sql AND DB_NAME(r.database_id) not in ('$excludedatabases')"
            }

            Write-Message -Level Debug -Message $sql
            foreach ($row in ($server.Query($sql))) {
                [PSCustomObject]@{
                    ComputerName            = $server.ComputerName
                    InstanceName            = $server.ServiceName
                    SqlInstance             = $server.DomainInstanceName
                    Database                = $row.Database
                    Login                   = $row.Login
                    Command                 = $row.Command
                    PercentComplete         = $row.PercentComplete
                    StartTime               = $row.StartTime
                    RunningTime             = $row.RunningTime
                    EstimatedTimeToGo       = $row.EstimatedTimeToGo
                    EstimatedCompletionTime = $row.EstimatedCompletionTime
                    Text                    = $row.Text
                } | Select-DefaultView -ExcludeProperty Text
            }
        }
    }
}