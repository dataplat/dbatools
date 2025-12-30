Function Get-DbaDbLogSpace {
    <#
    .SYNOPSIS
        Retrieves transaction log space usage and capacity information from SQL Server databases.

    .DESCRIPTION
        Collects detailed transaction log metrics including total size, used space percentage, and used space in bytes for databases across SQL Server instances. Uses the sys.dm_db_log_space_usage DMV on SQL Server 2012+ or DBCC SQLPERF(logspace) on older versions.

        Essential for proactive log space monitoring to prevent unexpected transaction log growth, identify databases approaching log capacity limits, and plan log file sizing. Helps DBAs avoid transaction failures caused by full transaction logs and optimize log file allocation strategies.

    .PARAMETER SqlInstance
        SQL Server name or SMO object representing the SQL Server to connect to. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies which databases to check for transaction log space usage. Accepts wildcards for pattern matching.
        Use this when you need to monitor specific databases instead of checking all databases on the instance, particularly useful for focusing on high-growth or critical databases.

    .PARAMETER ExcludeDatabase
        Specifies databases to skip when checking transaction log space usage. Accepts wildcards for pattern matching.
        Use this to exclude databases you don't need to monitor regularly, such as test databases, read-only databases, or databases with known stable log usage patterns.

    .PARAMETER ExcludeSystemDatabase
        Excludes system databases (master, model, msdb, tempdb) from the transaction log space report.
        Use this when focusing on user databases only, as system database log usage is typically managed differently and may not require the same monitoring attention.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .OUTPUTS
        PSCustomObject

        Returns one object per database containing transaction log space usage metrics.

        Properties:
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name (service name)
        - SqlInstance: The full SQL Server instance name (computer\instance format)
        - Database: The name of the database
        - LogSize: The total size of the transaction log file(s) for the database, formatted as a dbasize object (e.g., "10 MB", "1 GB")
        - LogSpaceUsedPercent: The percentage of the transaction log that is currently in use (0-100)
        - LogSpaceUsed: The amount of space currently used in the transaction log file(s), formatted as a dbasize object

        The command uses sys.dm_db_log_space_usage DMV on SQL Server 2012+ or DBCC SQLPERF(logspace) on earlier versions, but returns identical output structure for both.

    .NOTES
        Tags: Storage, Space, Log, File
        Author: Jess Pomfret, JessPomfret.com

        Website: https://dbatools.io
        Copyright: (c) 2019 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaDbLogSpace

    .EXAMPLE
        PS C:\> Get-DbaDbLogSpace -SqlInstance Server1

        Returns the transaction log usage information for all databases on Server1

    .EXAMPLE
        PS C:\> Get-DbaDbLogSpace -SqlInstance Server1 -Database Database1, Database2

        Returns the transaction log usage information for both Database1 and Database 2 on Server1

    .EXAMPLE
        PS C:\> Get-DbaDbLogSpace -SqlInstance Server1 -ExcludeDatabase Database3

        Returns the transaction log usage information for all databases on Server1, except Database3

    .EXAMPLE
        PS C:\> Get-DbaDbLogSpace -SqlInstance Server1 -ExcludeSystemDatabase

        Returns the transaction log usage information for all databases on Server1, except the system databases

    .EXAMPLE
        PS C:\> Get-DbaRegisteredServer -SqlInstance cmsServer | Get-DbaDbLogSpace -Database Database1

        Returns the transaction log usage information for Database1 for a group of servers from SQL Server Central Management Server (CMS).
    #>
    [CmdletBinding()]
    param (
        [parameter(ValueFromPipeline, Mandatory)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [string[]]$ExcludeDatabase,
        [switch]$ExcludeSystemDatabase,
        [switch]$EnableException
    )

    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
            $dbs = $server.Databases | Where-Object IsAccessible

            if ($Database) {
                $dbs = $dbs | Where-Object Name -in $Database
            }
            if ($ExcludeDatabase) {
                $dbs = $dbs | Where-Object Name -NotIn $ExcludeDatabase
            }

            if ($ExcludeSystemDatabase) {
                $dbs = $dbs | Where-Object IsSystemObject -eq $false
            }

            # 2012+ use new DMV
            if ($server.versionMajor -ge 11) {
                foreach ($db in $dbs) {
                    try {
                        $logspace = $server.query('SELECT * FROM sys.dm_db_log_space_usage', $db.name)
                    } catch {
                        Stop-Function -Message "Unable to collect log space data on $instance." -ErrorRecord $_ -Target $db -Continue
                    }
                    [PSCustomObject]@{
                        ComputerName        = $server.ComputerName
                        InstanceName        = $server.ServiceName
                        SqlInstance         = $server.DomainInstanceName
                        Database            = $db.name
                        LogSize             = [dbasize]($logspace.total_log_size_in_bytes)
                        LogSpaceUsedPercent = $logspace.used_log_space_in_percent
                        LogSpaceUsed        = [dbasize]($logspace.used_log_space_in_bytes)
                    }
                }
            } else {
                try {
                    $logspace = $server.Query("DBCC SQLPERF(LOGSPACE)") | Where-Object { $dbs.name -contains $_.'Database Name' }
                } catch {
                    Stop-Function -Message "Unable to collect log space data on $instance." -ErrorRecord $_ -Target $db -Continue
                }

                foreach ($ls in $logspace) {
                    [PSCustomObject]@{
                        ComputerName        = $server.ComputerName
                        InstanceName        = $server.ServiceName
                        SqlInstance         = $server.DomainInstanceName
                        Database            = $ls.'Database Name'
                        LogSize             = [dbasize]($ls.'Log Size (MB)' * 1MB)
                        LogSpaceUsedPercent = $ls.'Log Space Used (%)'
                        LogSpaceUsed        = [dbasize]($ls.'Log Size (MB)' * ($ls.'Log Space Used (%)' / 100) * 1MB)
                    }
                }
            }
        }
    }
}