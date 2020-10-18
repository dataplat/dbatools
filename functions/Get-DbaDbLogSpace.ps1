Function Get-DbaDbLogSpace {
    <#
    .SYNOPSIS
        Gets information on the database transaction log usage for each instance(s) of SQL Server.

    .DESCRIPTION
        Returns transaction log size and space used for each database on the SQL Server instance(s).

        This can be used to monitor how much of your allocated transaction log space is in use, and whether it is nearing the point where it will need to grow.

    .PARAMETER SqlInstance
        SQL Server name or SMO object representing the SQL Server to connect to. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The database(s) to process - this list is auto-populated from the server. If unspecified, all databases will be processed.

    .PARAMETER ExcludeDatabase
        The database(s) to exclude - this list is auto-populated from the server.

    .PARAMETER ExcludeSystemDatabase
        Allows you to suppress output on system databases.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Database, Space
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
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failed to process Instance $Instance" -ErrorRecord $_ -Target $instance -Continue
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
                        $logspace = $server.query('select * from sys.dm_db_log_space_usage', $db.name)
                    } catch {
                        Stop-Function -Message "Unable to collect log space data on $instance." -ErrorRecord $_ -Target $db -Continue
                    }
                    [pscustomobject]@{
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
                    $logspace = $server.Query("dbcc sqlperf(logspace)") | Where-Object { $dbs.name -contains $_.'Database Name' }
                } catch {
                    Stop-Function -Message "Unable to collect log space data on $instance." -ErrorRecord $_ -Target $db -Continue
                }

                foreach ($ls in $logspace) {
                    [pscustomobject]@{
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