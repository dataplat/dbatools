function Get-DbaEstimatedCompletionTime {
    <#
    .SYNOPSIS
        Gets execution and estimated completion time information for queries

    .DESCRIPTION
        Gets execution and estimated completion time information for queries

        Percent complete will show for the following commands

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

        For additional information, check out https://blogs.sentryone.com/loriedwards/patience-dm-exec-requests/ and https://docs.microsoft.com/en-us/sql/relational-databases/system-dynamic-management-views/sys-dm-exec-requests-transact-sql

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        SqlLogin to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance..

    .PARAMETER Database
        The database(s) to process - this list is auto-populated from the server. If unspecified, all databases will be processed.

    .PARAMETER ExcludeDatabase
        The database(s) to exclude - this list is auto-populated from the server

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Database
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
                DB_NAME(r.database_id) as [Database],
                USER_NAME(r.user_id) as [Login],
                Command,
                start_time as StartTime,
                percent_complete as PercentComplete,

                  RIGHT('00000' + CAST(((DATEDIFF(s,start_time,GetDate()))/3600) as varchar),
                                CASE
                                    WHEN LEN(((DATEDIFF(s,start_time,GetDate()))/3600)) < 2 THEN 2
                                    ELSE LEN(((DATEDIFF(s,start_time,GetDate()))/3600))
                                 END)  + ':'
                + RIGHT('00' + CAST((DATEDIFF(s,start_time,GetDate())%3600)/60 as varchar), 2) + ':'
                + RIGHT('00' + CAST((DATEDIFF(s,start_time,GetDate())%60) as varchar), 2) as RunningTime,

                  RIGHT('00000' + CAST((estimated_completion_time/3600000) as varchar),
                        CASE
                                    WHEN LEN((estimated_completion_time/3600000)) < 2 THEN 2
                                    ELSE LEN((estimated_completion_time/3600000))
                         END)  + ':'
                + RIGHT('00' + CAST((estimated_completion_time %3600000)/60000 as varchar), 2) + ':'
                + RIGHT('00' + CAST((estimated_completion_time %60000)/1000 as varchar), 2) as EstimatedTimeToGo,
                dateadd(second,estimated_completion_time/1000, getdate()) as EstimatedCompletionTime,
                s.Text
             FROM sys.dm_exec_requests r
            CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) s"
    }

    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential

            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if ($Database) {
                $includedatabases = $Database -join "','"
                $sql = "$sql WHERE DB_NAME(r.database_id) in ('$includedatabases')"
            }

            if ($ExcludeDatabase) {
                $excludedatabases = $ExcludeDatabase -join "','"
                $sql = "$sql WHERE DB_NAME(r.database_id) not in ('$excludedatabases')"
            }

            Write-Message -Level Debug -Message $sql
            foreach ($row in ($server.Query($sql))) {
                [pscustomobject]@{
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