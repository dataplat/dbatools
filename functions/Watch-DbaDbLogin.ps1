function Watch-DbaDbLogin {
    <#
        .SYNOPSIS
            Tracks SQL Server logins: which host they came from, what database they're using, and what program is being used to log in.

        .DESCRIPTION
            Watch-DbaDbLogin uses SQL Server DMVs to track logins into a SQL Server table. This is helpful when you need to migrate a SQL Server and update connection strings, but have inadequate documentation on which servers/applications are logging into your SQL instance.

            Running this script every 5 minutes for a week should give you a sufficient idea about database and login usage.

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
            Allows you to login to servers using SQL Logins instead of Windows Authentication (AKA Integrated or Trusted).

            To use:
            $scred = Get-Credential, then pass $scred object to the -SqlCredential parameter.

            Windows Authentication will be used if SqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials.

            To connect as a different Windows user, run PowerShell as that user.

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Tags: Login
            Author: Chrissy LeMaire (@cl), netnerds.net
            Requires: sysadmin access on all SQL Servers for the most accurate results

            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

        .LINK
            https://dbatools.io/Watch-DbaDbLogin

        .EXAMPLE
            Watch-DbaDbLogin -SqlInstance sqlserver -SqlCms SqlCms1

            A list of all database instances within the Central Management Server SqlCms1 is generated. Using this list, the script enumerates all the processes and gathers login information and saves it to the table Dblogins in the DatabaseLogins database on SQL Server sqlserver.

        .EXAMPLE
            Watch-DbaDbLogin -SqlInstance sqlcluster -Database CentralAudit -ServersFromFile .\sqlservers.txt

            A list of servers is gathered from the file sqlservers.txt in the current directory. Using this list, the script enumerates all the processes and gathers login information and saves it to the table Dblogins in the CentralAudit database on SQL Server sqlcluster.

        .EXAMPLE
            Watch-DbaDbLogin -SqlInstance sqlserver -SqlCms SqlCms1 -SqlCredential $cred

            A list of servers is generated using database instance names within the SQL2014Clusters group on the Central Management Server SqlCms1. Using this list, the script enumerates all the processes and gathers login information and saves it to the table Dblogins in the DatabaseLogins database on sqlserver.

    #>
    [CmdletBinding(DefaultParameterSetName = "Default")]
    param (
        [parameter(Mandatory = $true)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstance]$SqlInstance,
        [object]$Database,
        [string]$Table = "DbaTools-WatchDbLogins",
        [PSCredential]$SqlCredential,

        # Central Management Server
        [string]$SqlCms,

        # File with one server per line
        [string]$ServersFromFile,
        [switch][Alias('Silent')]$EnableException
    )

    process {
        if (Test-Bound 'SqlCms', 'ServersFromFile' -Not) {
            Stop-Function -Message "You must specify a server list source using -SqlCms or -ServersFromFile"
            return
        }

        Write-Message -Level Verbose -Message "Attempting to connect to $SqlInstance"
        try {
            Write-Message -Level Verbose -Message "Connecting to $SqlInstance"
            $serverDest = Connect-SqlInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
        }
        catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $SqlInstance -Continue
        }

        $systemdbs = "master", "msdb", "model", "tempdb"
        $excludedPrograms = "Microsoft SQL Server Management Studio - Query", "SQL Management"

        <#
            Get servers to query from Central Management Server or File
        #>
        if ($SqlCms) {
            try {
                $servers = Get-DbaRegisteredServerName -SqlInstance $SqlCms -SqlCredential $SqlCredential -EnableException
            }
            catch {
                Stop-Function -Message "The CMS server, $SqlCms, was not accessible." -Target $SqlCms -ErrorRecord $_
                return
            }
        }
        if (Test-Bound 'ServersFromFile') {
            if (Test-Path $ServersFromFile) {
                $servers = Get-Content $ServersFromFile
            }
            else {
                Stop-Function -Message "$ServersFromFile was not found." -Target $ServersFromFile
                return
            }
        }

        <#
            Process each server
        #>
        foreach ($instance in $servers) {
            Write-Message -Level Verbose -Message "Attempting to connect to $instance"
            try {
                Write-Message -Level Verbose -Message "Connecting to $instance"
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if (!(Test-SqlSa $server)) {
                Write-Warning "Not a sysadmin on $instance, resultset would be underwhelming. Skipping.";
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

            $procs = $server.Query($sql) | Where-Object { $_.Host -ne $sourceserver.ComputerNamePhysicalNetBIOS -and ![string]::IsNullOrEmpty($_.Host) }
            $procs = $procs | Where-Object { $systemdbs -notcontains $_.Database -and $excludedPrograms -notcontains $_.Program }

            if ($procs.Count -gt 0) {
                $procs | Select-Object @{Label = "ComputerName"; Expression = {$server.NetName}}, @{Label = "InstanceName"; Expression = {$server.ServiceName}}, @{Label = "SqlInstance"; Expression = {$server.DomainInstanceName}}, LoginTime, Login, Host, Program, DatabaseId, Database, IsSystem, CaptureTime | Out-DbaDataTable | Write-DbaDataTable -SqlInstance $serverDest -Database $Database -Table $Table -AutoCreateTable

                Write-Output "Added process information for $instance to datatable."
            }
            else {
                Write-message -Level Verbose -Message "No data returned for $instance."
            }
        }
    }
    end {
        Test-DbaDeprecation -DeprecatedOn "1.0.0" -EnableException:$false -Alias Watch-SqlDbLogin
    }
}