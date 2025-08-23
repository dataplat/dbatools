function Get-DbaTcpPort {
    <#
    .SYNOPSIS
        Returns the TCP port used by the specified SQL Server.

    .DESCRIPTION
        By default, this function returns just the TCP port used by the specified SQL Server.

        If -All is specified, the server name, IPAddress (ipv4 and ipv6), port number and an indicator of whether or not the port assignment is static are returned.

        Remote sqlwmi is used by default. If this doesn't work, then remoting is used. If neither work, it defaults to T-SQL which can provide only the port.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Allows you to connect to servers using alternate Windows credentials

        $scred = Get-Credential, then pass $scred object to the -SqlCredential parameter.

    .PARAMETER Credential
        Credential object used to connect to the Computer as a different user

    .PARAMETER All
        Returns comprehensive network configuration details including server name, IP addresses (IPv4 and IPv6), port numbers, and whether the port assignment is static.
        Use this when troubleshooting connectivity issues or when you need complete network configuration information instead of just the port number.

    .PARAMETER ExcludeIpv6
        Excludes IPv6 addresses from the output when used with the All parameter, showing only IPv4 network configurations.
        Use this in environments where IPv6 is disabled or when you only need to focus on IPv4 connectivity for troubleshooting.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Network, Connection, TCP, SQLWMI
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaTcpPort

    .EXAMPLE
        PS C:\> Get-DbaTcpPort -SqlInstance sqlserver2014a

        Returns just the port number for the default instance on sqlserver2014a.

    .EXAMPLE
        PS C:\> Get-DbaTcpPort -SqlInstance winserver\sqlexpress, sql2016

        Returns an object with server name and port number for the sqlexpress on winserver and the default instance on sql2016.

    .EXAMPLE
        PS C:\> Get-DbaTcpPort -SqlInstance sqlserver2014a, sql2016 -All

        Returns an object with server name, IPAddress (ipv4 and ipv6), port and static ($true/$false) for sqlserver2014a and sql2016.

        Remote sqlwmi is used by default. If this doesn't work, then remoting is used. If neither work, it defaults to T-SQL which can provide only the port.

    .EXAMPLE
        PS C:\> Get-DbaRegServer -SqlInstance sql2014 | Get-DbaTcpPort -ExcludeIpv6 -All

        Returns an object with server name, IPAddress (just ipv4), port and static ($true/$false) for every server listed in the Central Management Server on sql2014.

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [PSCredential]$Credential,
        [switch]$All,
        [Alias("Ipv4")]
        [switch]$ExcludeIpv6,
        [switch]$EnableException
    )
    process {
        foreach ($instance in $SqlInstance) {
            if ($All) {
                try {
                    $netConf = Get-DbaNetworkConfiguration -SqlInstance $instance -Credential $Credential -OutputType Full -EnableException
                } catch {
                    Stop-Function -Message "Failed to collect network configuration from $($instance.ComputerName) for instance $($instance.InstanceName)." -Target $instance -ErrorRecord $_ -Continue
                }

                $someIps = foreach ($ip in $netConf.TcpIpAddresses) {
                    # A setting is only used if either ListenAll is active and it is IPAll or if ListenAll is not active and the IPn is enabled.
                    $isIPAll = $netConf.TcpIpProperties.ListenAll -and $ip.Name -eq 'IPAll'
                    $isIPnEnabled = -not $netConf.TcpIpProperties.ListenAll -and $ip.Enabled
                    $isUsed = $isIPAll -or $isIPnEnabled
                    [PSCustomObject]@{
                        ComputerName    = $netConf.ComputerName
                        InstanceName    = $netConf.InstanceName
                        SqlInstance     = $netConf.SqlInstance
                        Name            = $ip.Name
                        Active          = $ip.Active
                        Enabled         = $ip.Enabled
                        IpAddress       = $ip.IpAddress
                        TcpDynamicPorts = $ip.TcpDynamicPorts
                        TcpPort         = $ip.TcpPort
                        IsUsed          = $isUsed
                    }
                }

                $results = $someIps | Sort-Object IPAddress

                if ($ExcludeIpv6) {
                    $octet = '(?:0?0?[0-9]|0?[1-9][0-9]|1[0-9]{2}|2[0-5][0-5]|2[0-4][0-9])'
                    [regex]$ipv4 = "^(?:$octet\.){3}$octet$"
                    $results = $results | Where-Object { $_.IPAddress -match $ipv4 }
                }

                $results
            }
            #Default Execution of Get-DbaTcpPort
            if (-not $All -or ($All -and ($null -eq $someIps))) {
                try {
                    # Using "-NetworkProtocol TcpIp" does not work if $instance is a Server SMO - so we have to use a string to force a new connection:
                    $server = Connect-DbaInstance -SqlInstance "TCP:$instance" -SqlCredential $SqlCredential -MinimumVersion 9
                } catch {
                    Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
                }

                # WmiComputer can be unreliable :( Use T-SQL
                $sql = "SELECT local_net_address,local_tcp_port FROM sys.dm_exec_connections WHERE session_id = @@SPID"
                $port = $server.Query($sql)

                [PSCustomObject]@{
                    ComputerName = $server.ComputerName
                    InstanceName = $server.ServiceName
                    SqlInstance  = $server.DomainInstanceName
                    IPAddress    = $port.local_net_address
                    Port         = $port.local_tcp_port
                    Static       = $true
                    Type         = "Normal"
                } | Select-DefaultView -Property ComputerName, InstanceName, SqlInstance, IPAddress, Port
            }
        }
    }
}