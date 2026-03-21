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

    .OUTPUTS
        PSCustomObject

        Returns one object per connection on each SQL Server instance. Each object contains detailed information about the connection and its statistics.

        Properties:
        - ComputerName: The name of the computer where SQL Server is running
        - InstanceName: The SQL Server instance name (MSSQLSERVER for default instance)
        - SqlInstance: The full SQL Server instance name (ComputerName\InstanceName format)
        - SessionId: The session ID of the connection (integer)
        - MostRecentSessionId: The most recent session ID associated with this connection (integer)
        - ConnectTime: DateTime when the connection was established
        - Transport: The network transport protocol used (e.g., "Named pipes", "TCP/IP", "Shared memory")
        - ProtocolType: The protocol type used for the connection (e.g., "TSQL")
        - ProtocolVersion: The version of the protocol being used (integer)
        - EndpointId: The ID of the database mirroring endpoint (integer)
        - EncryptOption: Encryption status of the connection (e.g., "ENCRYPT_ON", "ENCRYPT_OFF")
        - AuthScheme: The authentication scheme used (e.g., "WINDOWS", "SQL")
        - NodeAffinity: The node affinity of the connection for non-uniform memory access (NUMA) systems (integer)
        - Reads: The number of read operations performed on this connection (integer)
        - Writes: The number of write operations performed on this connection (integer)
        - LastRead: DateTime of the most recent read operation on this connection
        - LastWrite: DateTime of the most recent write operation on this connection
        - PacketSize: The network packet size in bytes used for this connection (integer)
        - ClientNetworkAddress: The IP address or network address of the client connecting to SQL Server
        - ClientTcpPort: The TCP port used by the client to connect to SQL Server (integer)
        - ServerNetworkAddress: The IP address or network address of the server's network interface
        - ServerTcpPort: The TCP port on which SQL Server is listening (integer)
        - ConnectionId: The unique identifier for this connection (integer, GUID-based)
        - ParentConnectionId: The parent connection ID for connections that are part of a hierarchy (integer)
        - MostRecentSqlHandle: The SQL handle of the most recently executed statement (binary)

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
                            session_id AS SessionId, most_recent_session_id AS MostRecentSessionId, connect_time AS ConnectTime,
                            net_transport AS Transport, protocol_type AS ProtocolType, protocol_version AS ProtocolVersion,
                            endpoint_id AS EndpointId, encrypt_option AS EncryptOption, auth_scheme AS AuthScheme, node_affinity AS NodeAffinity,
                            num_reads AS Reads, num_writes AS Writes, last_read AS LastRead, last_write AS LastWrite,
                            net_packet_size AS PacketSize, client_net_address AS ClientNetworkAddress, client_tcp_port AS ClientTcpPort,
                            local_net_address AS ServerNetworkAddress, local_tcp_port AS ServerTcpPort, connection_id AS ConnectionId,
                            parent_connection_id AS ParentConnectionId, most_recent_sql_handle AS MostRecentSqlHandle
                            FROM sys.dm_exec_connections"
    }

    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
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