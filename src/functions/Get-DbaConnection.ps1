function Get-DbaConnection {
    <#
    .SYNOPSIS
        Returns a bunch of information from dm_exec_connections.

    .DESCRIPTION
        Returns a bunch of information from dm_exec_connections which, according to Microsoft:
        "Returns information about the connections established to this instance of SQL Server and the details of each connection. Returns server wide connection information for SQL Server. Returns current database connection information for SQL Database."

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. Server(s) must be SQL Server 2005 or higher.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Connection
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaConnection

    .EXAMPLE
        PS C:\> Get-DbaConnection -SqlInstance sql2016, sql2017

        Returns client connection information from sql2016 and sql2017

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [Alias("Credential", "Cred")]
        [PSCredential]$SqlCredential,
        [switch]$EnableException
    )

    begin {
        $sql = "SELECT  SERVERPROPERTY('MachineName') AS ComputerName,
                            ISNULL(SERVERPROPERTY('InstanceName'), 'MSSQLSERVER') AS InstanceName,
                            SERVERPROPERTY('ServerName') AS SqlInstance,
                            session_id as SessionId, most_recent_session_id as MostRecentSessionId, connect_time as ConnectTime,
                            net_transport as Transport, protocol_type as ProtocolType, protocol_version as ProtocolVersion,
                            endpoint_id as EndpointId, encrypt_option as EncryptOption, auth_scheme as AuthScheme, node_affinity as NodeAffinity,
                            num_reads as Reads, num_writes as Writes, last_read as LastRead, last_write as LastWrite,
                            net_packet_size as PacketSize, client_net_address as ClientNetworkAddress, client_tcp_port as ClientTcpPort,
                            local_net_address as ServerNetworkAddress, local_tcp_port as ServerTcpPort, connection_id as ConnectionId,
                            parent_connection_id as ParentConnectionId, most_recent_sql_handle as MostRecentSqlHandle
                            FROM sys.dm_exec_connections"
    }

    process {
        foreach ($instance in $SqlInstance) {

            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            Write-Message -Level Debug -Message "Getting results for the following query: $sql."
            try {
                $server.Query($sql)
            } catch {
                Stop-Function -Message "Failure" -Target $server -Exception $_ -Continue
            }
        }
    }
}