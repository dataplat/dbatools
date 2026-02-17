function Get-DbaProcess {
    <#
    .SYNOPSIS
        Retrieves active SQL Server processes and sessions with detailed connection and activity information.

    .DESCRIPTION
        Displays comprehensive information about SQL Server processes including session details, connection properties, timing data, and the last executed SQL statement. This function combines data from multiple system views to provide a complete picture of current database activity.

        Use this to monitor active connections, identify blocking processes, track application connections, troubleshoot performance issues, or audit database access patterns. The output includes connection timing, network transport details, authentication schemes, client information, and recent query activity.

        You can filter results by login name, hostname, program name, database, or specific session IDs to focus on particular processes of interest. This is especially useful for identifying connection leaks, monitoring specific applications, or investigating security concerns.

        Thanks to Michael J Swart at https://sqlperformance.com/2017/07/sql-performance/find-database-connection-leaks for the query to get the last executed SQL statement, minutesasleep and host process ID.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Spid
        Filters results to specific process IDs (SPIDs) you want to monitor. Also includes any processes that are blocked by the specified SPIDs.
        Use this when investigating specific connections or troubleshooting blocking issues where you need to see both the blocker and blocked processes.

    .PARAMETER Login
        Filters results to sessions connected with specific SQL Server login names or Windows authentication accounts.
        Use this to monitor connections from specific applications, service accounts, or users when investigating security concerns or connection patterns.

    .PARAMETER Hostname
        Filters results to sessions originating from specific client machines or server names.
        Use this when tracking connections from particular workstations, application servers, or investigating connection leaks from specific hosts.

    .PARAMETER Program
        Filters results to sessions created by specific client applications such as 'Microsoft SQL Server Management Studio' or custom application names.
        Use this to monitor connections from particular applications, identify connection patterns, or troubleshoot application-specific database issues.

    .PARAMETER Database
        Filters results to sessions currently connected to specific databases.
        Use this when monitoring activity on particular databases, investigating database-specific performance issues, or auditing access to sensitive databases.

    .PARAMETER ExcludeSpid
        Excludes specific process IDs (SPIDs) from the results, even if they match other filter criteria.
        Use this to remove known processes like monitoring tools, maintenance jobs, or your own session from the output. This filter is applied last, overriding all other inclusion filters.

    .PARAMETER ExcludeSystemSpids
        Excludes system processes (SPIDs 1-50) from the results to focus only on user connections and application processes.
        Use this when you want to see only actual user sessions and application connections, filtering out SQL Server internal processes like checkpoints, log writers, and system tasks.

    .PARAMETER Intersect
        If this switch is enabled, take the intersection of Spid, Login, Hostname, Program, and Database rather than the union.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Diagnostic, Process, Session, ActivityMonitor
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaProcess

    .OUTPUTS
        System.Data.DataRow

        Returns one object per active SQL Server process/session matching the specified filter criteria.

        Default display properties (via Select-DefaultView):
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - Spid: Session ID number of the process
        - Login: SQL Server login or Windows authentication account name
        - LoginTime: DateTime when the session logged in
        - Host: Client machine name/hostname
        - Database: Database currently connected to the session
        - BlockingSpid: Session ID of the process blocking this session (if blocked)
        - Program: Client application name that initiated the session
        - Status: Current status of the session (sleeping, running, etc.)
        - Command: T-SQL command currently being executed
        - Cpu: CPU time consumed in milliseconds
        - MemUsage: Memory usage in pages (8 KB per page)
        - LastRequestStartTime: DateTime when the last request started
        - LastRequestEndTime: DateTime when the last request completed
        - MinutesAsleep: Minutes elapsed since last request ended
        - ClientNetAddress: Client IP address
        - NetTransport: Network transport protocol (Named Pipes, TCP, Shared Memory)
        - EncryptOption: Encryption setting (Off, On, Required, Login)
        - AuthScheme: Authentication scheme used (NTLM, Kerberos, SQL, etc.)
        - NetPacketSize: Network packet size in bytes
        - ClientVersion: Client library version number
        - HostProcessId: Operating system process ID on the client machine
        - IsSystem: Boolean indicating if this is a system session
        - EndpointName: Name of the endpoint the connection is using
        - IsDac: Boolean indicating if this is a Dedicated Admin Connection (DAC)
        - LastQuery: The last T-SQL statement executed in this session

        Additional properties available (from SMO Process object):
        - Parent: Reference to the parent Server object
        - All other SMO process properties are accessible using Select-Object *

    .EXAMPLE
        PS C:\> Get-DbaProcess -SqlInstance sqlserver2014a -Login base\ctrlb, sa

        Shows information about the processes for base\ctrlb and sa on sqlserver2014a. Windows Authentication is used in connecting to sqlserver2014a.

    .EXAMPLE
        PS C:\> Get-DbaProcess -SqlInstance sqlserver2014a -SqlCredential $credential -Spid 56, 77

        Shows information about the processes for spid 56 and 57. Uses alternative (SQL or Windows) credentials to authenticate to sqlserver2014a.

    .EXAMPLE
        PS C:\> Get-DbaProcess -SqlInstance sqlserver2014a -Program 'Microsoft SQL Server Management Studio'

        Shows information about the processes that were created in Microsoft SQL Server Management Studio.

    .EXAMPLE
        PS C:\> Get-DbaProcess -SqlInstance sqlserver2014a -Host workstationx, server100

        Shows information about the processes that were initiated by hosts (computers/clients) workstationx and server 1000.

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [int[]]$Spid,
        [int[]]$ExcludeSpid,
        [string[]]$Database,
        [string[]]$Login,
        [string[]]$Hostname,
        [string[]]$Program,
        [switch]$ExcludeSystemSpids,
        [switch]$EnableException,
        [switch]$Intersect
    )

    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $sql = "SELECT DATEDIFF(MINUTE, s.last_request_end_time, GETDATE()) AS MinutesAsleep,
                s.session_id AS spid,
                s.host_process_id AS HostProcessId,
                t.text AS Query,
                s.login_time AS LoginTime,
                s.client_version AS ClientVersion,
                s.last_request_start_time AS LastRequestStartTime,
                s.last_request_end_time AS LastRequestEndTime,
                c.net_transport AS NetTransport,
                c.encrypt_option AS EncryptOption,
                c.auth_scheme AS AuthScheme,
                c.net_packet_size AS NetPacketSize,
                c.client_net_address AS ClientNetAddress,
                e.name AS EndpointName,
                e.is_admin_endpoint AS IsDac
            FROM sys.dm_exec_connections c
            JOIN sys.dm_exec_sessions s
                ON c.session_id = s.session_id
            JOIN sys.endpoints e
                ON c.endpoint_id = e.endpoint_id
            OUTER APPLY sys.dm_exec_sql_text(c.most_recent_sql_handle) t"

            if ($server.VersionMajor -gt 8) {
                $results = $server.Query($sql)
            } else {
                $results = $null
            }

            $allSessions = @()

            $processes = $server.EnumProcesses()

            if ($Intersect -eq $true) {
                $allSessions = $processes

                if ($Login) {
                    $allSessions = $allSessions | Where-Object { $_.Login -in $Login }
                }

                if ($Spid) {
                    $allSessions = $allSessions | Where-Object { $_.Spid -in $Spid -or $_.BlockingSpid -in $Spid }
                }

                if ($Hostname) {
                    $allSessions = $allSessions | Where-Object { $_.Host -in $Hostname }
                }

                if ($Program) {
                    $allSessions = $allSessions | Where-Object { $_.Program -in $Program }
                }

                if ($Database) {
                    $allSessions = $allSessions | Where-Object { $Database -contains $_.Database }
                }
            } else {
                if ($Login) {
                    $allSessions += $processes | Where-Object { $_.Login -in $Login -and $_.Spid -notin $allSessions.Spid }
                }

                if ($Spid) {
                    $allSessions += $processes | Where-Object { ($_.Spid -in $Spid -or $_.BlockingSpid -in $Spid) -and $_.Spid -notin $allSessions.Spid }
                }

                if ($Hostname) {
                    $allSessions += $processes | Where-Object { $_.Host -in $Hostname -and $_.Spid -notin $allSessions.Spid }
                }

                if ($Program) {
                    $allSessions += $processes | Where-Object { $_.Program -in $Program -and $_.Spid -notin $allSessions.Spid }
                }

                if ($Database) {
                    $allSessions += $processes | Where-Object { $Database -contains $_.Database -and $_.Spid -notin $allSessions.Spid }
                }
            }

            if (Test-Bound -not 'Login', 'Spid', 'ExcludeSpid', 'Hostname', 'Program', 'Database') {
                $allSessions = $processes
            }

            if ($ExcludeSystemSpids -eq $true) {
                $allSessions = $allSessions | Where-Object { $_.Spid -gt 50 }
            }

            if ($Exclude) {
                $allSessions = $allSessions | Where-Object { $Exclude -notcontains $_.SPID -and $_.Spid -notin $allSessions.Spid }
            }

            foreach ($session in $allSessions) {

                if ($session.Status -eq "") {
                    $status = "sleeping"
                } else {
                    $status = $session.Status
                }

                if ($session.Command -eq "") {
                    $command = "AWAITING COMMAND"
                } else {
                    $command = $session.Command
                }

                $row = $results | Where-Object { $_.Spid -eq $session.Spid }

                Add-Member -Force -InputObject $session -MemberType NoteProperty -Name Parent -value $server
                Add-Member -Force -InputObject $session -MemberType NoteProperty -Name ComputerName -value $server.ComputerName
                Add-Member -Force -InputObject $session -MemberType NoteProperty -Name InstanceName -value $server.ServiceName
                Add-Member -Force -InputObject $session -MemberType NoteProperty -Name SqlInstance -value $server.DomainInstanceName
                Add-Member -Force -InputObject $session -MemberType NoteProperty -Name Status -value $status
                Add-Member -Force -InputObject $session -MemberType NoteProperty -Name Command -value $command
                Add-Member -Force -InputObject $session -MemberType NoteProperty -Name HostProcessId -value $row.HostProcessId
                Add-Member -Force -InputObject $session -MemberType NoteProperty -Name MinutesAsleep -value $row.MinutesAsleep
                Add-Member -Force -InputObject $session -MemberType NoteProperty -Name LoginTime -value $row.LoginTime
                Add-Member -Force -InputObject $session -MemberType NoteProperty -Name ClientVersion -value $row.ClientVersion
                Add-Member -Force -InputObject $session -MemberType NoteProperty -Name LastRequestStartTime -value $row.LastRequestStartTime
                Add-Member -Force -InputObject $session -MemberType NoteProperty -Name LastRequestEndTime -value $row.LastRequestEndTime
                Add-Member -Force -InputObject $session -MemberType NoteProperty -Name NetTransport -value $row.NetTransport
                Add-Member -Force -InputObject $session -MemberType NoteProperty -Name EncryptOption -value $row.EncryptOption
                Add-Member -Force -InputObject $session -MemberType NoteProperty -Name AuthScheme -value $row.AuthScheme
                Add-Member -Force -InputObject $session -MemberType NoteProperty -Name NetPacketSize -value $row.NetPacketSize
                Add-Member -Force -InputObject $session -MemberType NoteProperty -Name ClientNetAddress -value $row.ClientNetAddress
                Add-Member -Force -InputObject $session -MemberType NoteProperty -Name LastQuery -value $row.Query
                Add-Member -Force -InputObject $session -MemberType NoteProperty -Name EndpointName -value $row.EndpointName
                Add-Member -Force -InputObject $session -MemberType NoteProperty -Name IsDac -value $row.IsDac

                Select-DefaultView -InputObject $session -Property ComputerName, InstanceName, SqlInstance, Spid, Login, LoginTime, Host, Database, BlockingSpid, Program, Status, Command, Cpu, MemUsage, LastRequestStartTime, LastRequestEndTime, MinutesAsleep, ClientNetAddress, NetTransport, EncryptOption, AuthScheme, NetPacketSize, ClientVersion, HostProcessId, IsSystem, EndpointName, IsDac, LastQuery
            }
        }
    }
}