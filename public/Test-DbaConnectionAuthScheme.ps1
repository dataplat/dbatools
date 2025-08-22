function Test-DbaConnectionAuthScheme {
    <#
    .SYNOPSIS
        Tests and reports authentication scheme and transport protocol details for SQL Server connections

    .DESCRIPTION
        This command queries sys.dm_exec_connections to retrieve authentication and transport details for your current SQL Server session. By default, it returns key connection properties including ServerName, Transport protocol, and AuthScheme (Kerberos or NTLM).

        This is particularly valuable for troubleshooting authentication issues when you expect Kerberos but are getting NTLM instead. The ServerName returned shows what SQL Server reports as its @@SERVERNAME, which must match your connection name for proper SPN registration and Kerberos authentication.

        When used with -Kerberos or -Ntlm switches, the command returns simple $true/$false results to verify specific authentication methods. This makes it ideal for automated checks and scripts that need to validate authentication schemes across multiple servers.

        Common scenarios include diagnosing SPN configuration problems, security auditing of connection protocols, and verifying that domain authentication is working as expected in your environment.

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
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
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
                    Result       = ($results.AuthScheme -eq $auth)
                } | Select-DefaultView -Property SqlInstance, Result
            } else {
                Select-DefaultView -InputObject $results -Property ComputerName, InstanceName, SqlInstance, Transport, AuthScheme
            }
        }
    }
}