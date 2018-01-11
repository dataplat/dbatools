function Get-DbaProcess {
    <#
        .SYNOPSIS
            This command displays SQL Server processes.

        .DESCRIPTION
            This command displays processes associated with a spid, login, host, program or database.

            Thanks to Michael J Swart at https://sqlperformance.com/2017/07/sql-performance/find-database-connection-leaks for the query to get the last executed SQL statement, minutesasleep and host process ID.

        .PARAMETER SqlInstance
            The SQL Server instance to connect to.

        .PARAMETER SqlCredential
            Allows you to login to servers using SQL Logins instead of Windows Authentication (AKA Integrated or Trusted). To use:

            $scred = Get-Credential, then pass $scred object to the -SqlCredential parameter.

            Windows Authentication will be used if SqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials.

            To connect as a different Windows user, run PowerShell as that user.

        .PARAMETER Spid
            Specifies one or more process IDs (Spid) to be displayed. Options for this parameter are auto-populated from the server.

        .PARAMETER Login
            Specifies one or more Login names with active processes to look for. Options for this parameter are auto-populated from the server.

        .PARAMETER Hostname
            Specifies one or more hostnames with active processes to look for. Options for this parameter are auto-populated from the server.

        .PARAMETER Program
            Specifies one or more program names with active processes to look for. Options for this parameter are auto-populated from the server.

        .PARAMETER Database
            Specifies one or more databases with active processes to look for. Options for this parameter are auto-populated from the server.

        .PARAMETER ExcludeSpid
            Specifies one ore more process IDs to exclude from display. Options for this parameter are auto-populated from the server.

            This is the last filter to run, so even if a Spid matches another filter, it will be excluded by this filter.

        .PARAMETER NoSystemSpid
            If this switch is enabled, system Spids will be ignored.

        .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Tags:
            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

        .LINK
            https://dbatools.io/Get-DbaProcess

        .EXAMPLE
            Get-DbaProcess -SqlInstance sqlserver2014a -Login base\ctrlb, sa

            Shows information about the processes for base\ctrlb and sa on sqlserver2014a. Windows Authentication is used in connecting to sqlserver2014a.

        .EXAMPLE
            Get-DbaProcess -SqlInstance sqlserver2014a -SqlCredential $credential -Spid 56, 77

            Shows information about the processes for spid 56 and 57. Uses alternative (SQL or Windows) credentials to authenticate to sqlserver2014a.

        .EXAMPLE
            Get-DbaProcess -SqlInstance sqlserver2014a -Program 'Microsoft SQL Server Management Studio'

            Shows information about the processes that were created in Microsoft SQL Server Management Studio.

        .EXAMPLE
            Get-DbaProcess -SqlInstance sqlserver2014a -Host workstationx, server100

            Shows information about the processes that were initiated by hosts (computers/clients) workstationx and server 1000.
    #>
    [CmdletBinding()]
    Param (
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [Alias("Credential")]
        [PSCredential]$SqlCredential,
        [int[]]$Spid,
        [int[]]$ExcludeSpid,
        [string[]]$Database,
        [string[]]$Login,
        [string[]]$Hostname,
        [string[]]$Program,
        [switch]$NoSystemSpid,
        [switch][Alias('Silent')]$EnableException
    )

    process {
        foreach ($instance in $sqlinstance) {

            Write-Message -Message "Attempting to connect to $instance." -Level Verbose
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            }
            catch {
                Stop-Function -Message "Could not connect to Sql Server instance $instance : $_" -Target $instance -ErrorRecord $_ -Continue
            }

            $sql = "SELECT datediff(minute, s.last_request_end_time, getdate()) as MinutesAsleep, s.session_id as spid, s.host_process_id as HostProcessId, t.text as Query,
                    s.login_time as LoginTime,s.client_version as ClientVersion, s.last_request_start_time as LastRequestStartTime, s.last_request_end_time as LastRequestEndTime,
                    c.net_transport as NetTransport, c.encrypt_option as EncryptOption, c.auth_scheme as AuthScheme, c.net_packet_size as NetPacketSize, c.client_net_address as ClientNetAddress
                    FROM sys.dm_exec_connections c join sys.dm_exec_sessions s on c.session_id = s.session_id cross apply sys.dm_exec_sql_text(c.most_recent_sql_handle) t"

            if ($server.VersionMajor -gt 8) {
                $results = $server.Query($sql)
            }
            else {
                $results = $null
            }

            $allsessions = @()

            $processes = $server.EnumProcesses()

            if ($Login) {
                $allsessions += $processes | Where-Object { $_.Login -in $Login -and $_.Spid -notin $allsessions.Spid }
            }

            if ($Spid) {
                $allsessions += $processes | Where-Object { ($_.Spid -in $Spid -or $_.BlockingSpid -in $Spid) -and $_.Spid -notin $allsessions.Spid }
            }

            if ($Hostname) {
                $allsessions += $processes | Where-Object { $_.Host -in $Hostname -and $_.Spid -notin $allsessions.Spid }
            }

            if ($Program) {
                $allsessions += $processes | Where-Object { $_.Program -in $Program -and $_.Spid -notin $allsessions.Spid }
            }

            if ($Database) {
                $allsessions += $processes | Where-Object { $Database -contains $_.Database -and $_.Spid -notin $allsessions.Spid }
            }

            if (Test-Bound -not 'Login', 'Spid', 'ExcludeSpid', 'Hostname', 'Program', 'Database') {
                $allsessions = $processes
            }

            if ($NoSystemSpid -eq $true) {
                $allsessions = $allsessions | Where-Object { $_.Spid -gt 50 }
            }

            if ($Exclude) {
                $allsessions = $allsessions | Where-Object { $Exclude -notcontains $_.SPID -and $_.Spid -notin $allsessions.Spid }
            }

            foreach ($session in $allsessions) {

                if ($session.Status -eq "") {
                    $status = "sleeping"
                }
                else {
                    $status = $session.Status
                }

                if ($session.Command -eq "") {
                    $command = "AWAITING COMMAND"
                }
                else {
                    $command = $session.Command
                }

                $row = $results | Where-Object { $_.Spid -eq $session.Spid }

                Add-Member -Force -InputObject $session -MemberType NoteProperty -Name Parent -value $server
                Add-Member -Force -InputObject $session -MemberType NoteProperty -Name ComputerName -value $server.NetName
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

                Select-DefaultView -InputObject $session -Property ComputerName, InstanceName, SqlInstance, Spid, Login, LoginTime, Host, Database, BlockingSpid, Program, Status, Command, Cpu, MemUsage, LastRequestStartTime, LastRequestEndTime, MinutesAsleep, ClientNetAddress, NetTransport, EncryptOption, AuthScheme, NetPacketSize, ClientVersion, HostProcessId, IsSystem, LastQuery
            }
        }
    }
}