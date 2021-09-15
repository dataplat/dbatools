function Watch-DbaDbLogin {
    <#
    .SYNOPSIS
        Tracks SQL Server logins: which host they came from, what database they're using, and what program is being used to log in.

    .DESCRIPTION
        Watch-DbaDbLogin uses SQL Server DMV's to track logins into a SQL Server table. This is helpful when you need to migrate a SQL Server and update connection strings, but have inadequate documentation on which servers/applications are logging into your SQL instance.

        Running this script every 5 minutes for a week should give you a sufficient idea about database and login usage.

        Logins from the same server are excluded from the watched set.

        The inputs for this command are either a Central Management Server (registered server repository), a flat file of server names, or to use pipeline input via Connect-DbaInstance. See the examples for more information.

    .PARAMETER SqlInstance
        The SQL Server that stores the Watch database.

    .PARAMETER SqlCms
        Specifies a Central Management Server to query for a list of servers to watch.

    .PARAMETER ServersFromFile
        Specifies a file containing a list of servers to watch. This file must contain one server name per line.

    .PARAMETER Database
        The name of the Watch database.

    .PARAMETER Table
        The name of the Watch table. By default, this is DbaTools-WatchDbLogins.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER InputObject
        Allows pipeline input from Connect-DbaInstance.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Login
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT
        Requires: sysadmin access on all SQL Servers for the most accurate results

    .LINK
        https://dbatools.io/Watch-DbaDbLogin

    .EXAMPLE
        PS C:\> Watch-DbaDbLogin -SqlInstance sqlserver -SqlCms SqlCms1

        A list of all database instances within the Central Management Server SqlCms1 is generated. Using this list, the script enumerates all the processes and gathers login information and saves it to the table Dblogins in the DatabaseLogins database on SQL Server sqlserver.

    .EXAMPLE
        PS C:\> Watch-DbaDbLogin -SqlInstance sqlcluster -Database CentralAudit -ServersFromFile .\sqlservers.txt

        A list of servers is gathered from the file sqlservers.txt in the current directory. Using this list, the script enumerates all the processes and gathers login information and saves it to the table Dblogins in the CentralAudit database on SQL Server sqlcluster.

    .EXAMPLE
        PS C:\> Watch-DbaDbLogin -SqlInstance sqlserver -SqlCms SqlCms1 -SqlCredential $cred

        A list of servers is generated using database instance names within the SQL2014Clusters group on the Central Management Server SqlCms1. Using this list, the script enumerates all the processes and gathers login information and saves it to the table Dblogins in the DatabaseLogins database on sqlserver.

    .EXAMPLE
        PS C:\> $instance1 = Connect-DbaInstance -SqlInstance sqldev01
        PS C:\> $instance2 = Connect-DbaInstance -SqlInstance sqldev02
        PS C:\> $instance1, $instance2 | Watch-DbaDbLogin -SqlInstance sqltest01 -Database CentralAudit

        Pre-connects two instances sqldev01 and sqldev02 and then using pipelining sends them to Watch-DbaDbLogin to enumerate processes and gather login info. The resulting gathered info is stored to the DbaTools-WatchDbLogins table in the CentralAudit database on the sqltest01 instance.

        Note: This is the method to use if the instances have different credentials than the instance used to store the watch data.
    #>
    [CmdletBinding(DefaultParameterSetName = "Default")]
    param (
        [parameter(Mandatory)]
        [DbaInstance]$SqlInstance,
        [object]$Database,
        [string]$Table = "DbaTools-WatchDbLogins",
        [PSCredential]$SqlCredential,

        # Central Management Server
        [string]$SqlCms,

        # File with one server per line
        [string]$ServersFromFile,

        #Pre-connected servers to query
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Server[]]$InputObject,

        [switch]$EnableException
    )

    process {
        if (Test-Bound 'SqlCms', 'ServersFromFile', 'InputObject' -Not) {
            Stop-Function -Message "You must specify a server list source using -SqlCms or -ServersFromFile or pipe in connected instances. See the command documentation and examples for more details."
            return
        }

        try {
            $serverDest = Connect-DbaInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $SqlInstance
            return
        }

        $systemdbs = "master", "msdb", "model", "tempdb"
        $excludedPrograms = "Microsoft SQL Server Management Studio - Query", "SQL Management"

        <#
            Get servers to query from Central Management Server or File
        #>
        if ($SqlCms) {
            try {
                $servers = Get-DbaRegServer -SqlInstance $SqlCms -SqlCredential $SqlCredential -EnableException
            } catch {
                Stop-Function -Message "The CMS server, $SqlCms, was not accessible." -Target $SqlCms -ErrorRecord $_
                return
            }
        }
        if (Test-Bound 'ServersFromFile') {
            if (Test-Path $ServersFromFile) {
                $servers = Get-Content $ServersFromFile
            } else {
                Stop-Function -Message "$ServersFromFile was not found." -Target $ServersFromFile
                return
            }
        }

        <#
            Connect each server
        #>
        foreach ($instance in $servers) {
            try {
                if ($instance -is [Microsoft.SqlServer.Management.RegisteredServers.RegisteredServer]) {
                    $InputObject += Connect-DbaInstance -SqlInstance $instance.ServerName -SqlCredential $SqlCredential -MinimumVersion 9
                } else {
                    $InputObject += Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
                }
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
        }

        <#
            Process each server
        #>
        foreach ($instance in $InputObject) {

            if (!(Test-SqlSa $instance)) {
                Write-Message -Level Warning -Message "Not a sysadmin on $instance, resultset would be underwhelming. Skipping.";
                continue
            }

            $sql = "
            SELECT
                s.login_time AS [LoginTime]
                , s.login_name AS [Login]
                , ISNULL(s.host_name,N'') AS [Host]
                , ISNULL(s.program_name,N'') AS [Program]
                , ISNULL(r.database_id,N'') AS [DatabaseId]
                , ISNULL(DB_NAME(r.database_id),N'') AS [Database]
                , CAST(~s.is_user_process AS bit) AS [IsSystem]
                , CaptureTime = (SELECT GETDATE())
            FROM sys.dm_exec_sessions AS s
            LEFT OUTER JOIN sys.dm_exec_requests AS r
                ON r.session_id = s.session_id"
            Write-Message -Level Debug -Message $sql

            $procs = $instance.Query($sql) | Where-Object { $_.Host -ne $instance.ComputerName -and ![string]::IsNullOrEmpty($_.Host) }
            $procs = $procs | Where-Object { $systemdbs -notcontains $_.Database -and $excludedPrograms -notcontains $_.Program }

            if ($procs.Count -gt 0) {
                $procs | Select-Object @{Label = "ComputerName"; Expression = { $instance.ComputerName } }, @{Label = "InstanceName"; Expression = { $instance.ServiceName } }, @{Label = "SqlInstance"; Expression = { $instance.DomainInstanceName } }, LoginTime, Login, Host, Program, DatabaseId, Database, IsSystem, CaptureTime | ConvertTo-DbaDataTable | Write-DbaDbTableData -SqlInstance $serverDest -Database $Database -Table $Table -AutoCreateTable

                Write-Message -Level Output -Message "Added process information for $instance to datatable."
            } else {
                Write-Message -Level Verbose -Message "No data returned for $instance."
            }
        }
    }
}