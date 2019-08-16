function Test-DbaConnectionAuthScheme {
    <#
    .SYNOPSIS
        Returns the transport protocol and authentication scheme of the connection. This is useful to determine if your connection is using Kerberos.

    .DESCRIPTION
        By default, this command will return the ConnectName, ServerName, Transport and AuthScheme of the current connection.

        ConnectName is the name you used to connect. ServerName is the name that the SQL Server reports as its @@SERVERNAME which is used to register its SPN. If you were expecting a Kerberos connection and got NTLM instead, ensure ConnectName and ServerName match.

        If -Kerberos or -Ntlm is specified, the $true/$false results of the test will be returned. Returns $true or $false by default for one server. Returns Server name and Results for more than one server.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. Server(s) must be SQL Server 2005 or higher.

    .PARAMETER Kerberos
        If this switch is enabled, checks will be made for Kerberos authentication.

    .PARAMETER Ntlm
        If this switch is enabled, checks will be made for NTLM authentication.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: SPN, Kerberos
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Test-DbaConnectionAuthScheme

    .EXAMPLE
        PS C:\> Test-DbaConnectionAuthScheme -SqlInstance sqlserver2014a, sql2016

        Returns ConnectName, ServerName, Transport and AuthScheme for sqlserver2014a and sql2016.

    .EXAMPLE
        PS C:\> Test-DbaConnectionAuthScheme -SqlInstance sqlserver2014a -Kerberos

        Returns $true or $false depending on if the connection is Kerberos or not.

    .EXAMPLE
        PS C:\> Test-DbaConnectionAuthScheme -SqlInstance sqlserver2014a | Select-Object *

        Returns the results of "SELECT * from sys.dm_exec_connections WHERE session_id = @@SPID"

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [Alias("Credential", "Cred")]
        [PSCredential]$SqlCredential,
        [switch]$Kerberos,
        [switch]$Ntlm,
        [switch]$EnableException
    )

    begin {
        $sql = "SELECT  SERVERPROPERTY('MachineName') AS ComputerName,
                            ISNULL(SERVERPROPERTY('InstanceName'), 'MSSQLSERVER') AS InstanceName,
                            SERVERPROPERTY('ServerName') AS SqlInstance,
                            session_id as SessionId, most_recent_session_id as MostRecentSessionId, connect_time as ConnectTime,
                            net_transport as Transport, protocol_type as ProtocolType, protocol_version as ProtocolVersion,
                            endpoint_id as EndpointId, encrypt_option as EncryptOption, auth_scheme as AuthScheme, node_affinity as NodeAffinity,
                            num_reads as NumReads, num_writes as NumWrites, last_read as LastRead, last_write as LastWrite,
                            net_packet_size as PacketSize, client_net_address as ClientNetworkAddress, client_tcp_port as ClientTcpPort,
                            local_net_address as ServerNetworkAddress, local_tcp_port as ServerTcpPort, connection_id as ConnectionId,
                            parent_connection_id as ParentConnectionId, most_recent_sql_handle as MostRecentSqlHandle
                            FROM sys.dm_exec_connections WHERE session_id = @@SPID"
    }

    process {
        foreach ($instance in $SqlInstance) {

            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            Write-Message -Level Verbose -Message "Getting results for the following query: $sql."
            try {
                $results = $server.Query($sql)
            } catch {
                Stop-Function -Message "Failure" -Target $server -ErrorRecord $_ -Continue
            }

            # sorry, standards!
            if ($Kerberos -or $Ntlm) {
                if ($Ntlm) {
                    $auth = 'NTLM'
                } else {
                    $auth = 'Kerberos'
                }
                [PSCustomObject]@{
                    ComputerName = $results.ComputerName
                    InstanceName = $results.InstanceName
                    SqlInstance  = $results.SqlInstance
                    Result       = ($server.AuthScheme -eq $auth)
                } | Select-DefaultView -Property SqlInstance, Result
            } else {
                Select-DefaultView -InputObject $results -Property ComputerName, InstanceName, SqlInstance, Transport, AuthScheme
            }
        }
    }
}