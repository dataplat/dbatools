function Get-DbaTcpPort {
    <#
        .SYNOPSIS
            Returns the TCP port used by the specified SQL Server.

        .DESCRIPTION
            By default, this function returns just the TCP port used by the specified SQL Server.

            If -Detailed is specified, the server name, IPAddress (ipv4 and ipv6), port number and an indicator of whether or not the port assignment is static are returned.

            Remote sqlwmi is used by default. If this doesn't work, then remoting is used. If neither work, it defaults to T-SQL which can provide only the port.

        .PARAMETER SqlInstance
            The SQL Server that you're connecting to.

        .PARAMETER SqlCredential
            Allows you to connect to servers using alternate Windows credentials

            $scred = Get-Credential, then pass $scred object to the -SqlCredential parameter.

        .PARAMETER Detailed
            If this switch is enabled, an object with server name, IPAddress (ipv4 and ipv6), port and static ($true/$false) for one or more SQL Servers is returned.

        .PARAMETER ExcludeIpv6
            If this switch is enabled, IPv6 information is excluded from detailed output.

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Tags: SQLWMI, tcp

            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

        .LINK
            https://dbatools.io/Get-DbaTcpPort

        .EXAMPLE
            Get-DbaTcpPort -SqlInstance sqlserver2014a

            Returns just the port number for the default instance on sqlserver2014a.

        .EXAMPLE
            Get-DbaTcpPort -SqlInstance winserver\sqlexpress, sql2016

            Returns an object with server name and port number for the sqlexpress on winserver and the default instance on sql2016.

        .EXAMPLE
            Get-DbaTcpPort -SqlInstance sqlserver2014a, sql2016 -Detailed

            Returns an object with server name, IPAddress (ipv4 and ipv6), port and static ($true/$false) for sqlserver2014a and sql2016.

            Remote sqlwmi is used by default. If this doesn't work, then remoting is used. If neither work, it defaults to T-SQL which can provide only the port.

        .EXAMPLE
            Get-DbaRegisteredServer -SqlInstance sql2014 | Get-DbaTcpPort -ExcludeIpv6 -Detailed

            Returns an object with server name, IPAddress (just ipv4), port and static ($true/$false) for every server listed in the Central Management Server on sql2014.
    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [Alias("Credential")]
        [PSCredential]$SqlCredential,
        [switch]$Detailed,
        [Alias("Ipv4")]
        [switch]$ExcludeIpv6,
        [switch][Alias('Silent')]$EnableException
    )

    process {
        foreach ($instance in $SqlInstance) {
            if ($detailed -eq $true) {
                try {
                    $scriptblock = {
                        $instance = $args[0]

                        Add-Type -AssemblyName Microsoft.VisualBasic

                        foreach ($servername in $wmi.ServerInstances) {
                            $instanceName = $servername.Name
                            $wmiinstance = $wmi.Services | Where-Object { $_.DisplayName -eq "SQL Server ($instanceName)" }
                            $vsname = ($wmiinstance.AdvancedProperties | Where-Object { $_ -match 'VSNAME' }).Value

                            if ($vsname.length -eq 0) {
                                $vsname = "$instance\$instanceName"
                            }

                            $vsname = $vsname.Replace("\MSSQLSERVER", "")

                            try {
                                $regroot = ($wmiinstance.AdvancedProperties | Where-Object { $_ -match 'REGROOT' }).Value
                                $dacport = (Get-ItemProperty "HKLM:\$regroot\MSSQLServer\SuperSocketNetLib\AdminConnection\Tcp").TcpDynamicPorts

                                [PsCustomObject]@{
                                    ComputerName = $instance
                                    InstanceName = $instanceName
                                    SqlInstance  = $vsname
                                    IPAddress    = "0.0.0.0"
                                    Port         = $dacport
                                    Static       = $false
                                    Type         = "DAC"
                                }
                            }
                            catch {
                                # it's just not our day
                            }

                            $tcp = $servername.ServerProtocols | Where-Object Name -eq Tcp
                            $ips = $tcp.IPAddresses

                            # This is a remote command so do not use Write-message
                            Write-Verbose "Parsing information for $($ips.count) IP addresses."
                            foreach ($ip in $ips) {
                                $props = $ip.IPAddressProperties | Where-Object { $_.Name -eq "TcpPort" -or $_.Name -eq "TcpDynamicPorts" }

                                foreach ($prop in $props) {
                                    if ([Microsoft.VisualBasic.Information]::IsNumeric($prop.value)) {
                                        $port = $prop.value
                                        if ($prop.name -eq 'TcpPort') {
                                            $static = $true
                                        }
                                        else {
                                            $static = $false
                                        }
                                        break
                                    }
                                }

                                [PsCustomObject]@{
                                    ComputerName = $instance
                                    InstanceName = $instanceName
                                    SqlInstance  = $vsname
                                    IPAddress    = $ip.IPAddress.IPAddressToString
                                    Port         = $port
                                    Static       = $static
                                    Type         = "Normal"
                                }
                            }
                        }
                    }

                    $computer = $instance.ComputerName
                    $resolved = Resolve-DbaNetworkName -ComputerName $instance -Verbose:$false
                    $computername = $resolved.FullComputerName

                    try {
                        Write-Message -Level Verbose -Message "Trying with ComputerName ($computer)."
                        $someIps = Invoke-ManagedComputerCommand -ComputerName $computer -ArgumentList $computer -ScriptBlock $scriptblock
                    }
                    catch {
                        Write-Message -Level Verbose -Message "Trying with FullComputerName because ComputerName failed."
                        $someIps = Invoke-ManagedComputerCommand -ComputerName $computername -ArgumentList $fqdn -ScriptBlock $scriptblock
                    }
                }
                catch {
                    Stop-Function -Message "Could not get detailed information." -Target $instance -ErrorRecord $_
                }

                $cleanedUp = $someIps | Sort-Object IPAddress

                if ($ExcludeIpv6) {
                    $octet = '(?:0?0?[0-9]|0?[1-9][0-9]|1[0-9]{2}|2[0-5][0-5]|2[0-4][0-9])'
                    [regex]$ipv4 = "^(?:$octet\.){3}$octet$"
                    $cleanedUp = $cleanedUp | Where-Object { $_.IPAddress -match $ipv4 }
                }

                $cleanedUp
            }

            if ($Detailed -eq $false -or ($Detailed -eq $true -and $null -eq $someIps)) {
                try {
                    $server = Connect-SqlInstance -SqlInstance "TCP:$instance" -SqlCredential $SqlCredential -MinimumVersion 9
                }
                catch {
                    Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $servername -Continue
                }

                # WmiComputer can be unreliable :( Use T-SQL
                $sql = "SELECT local_tcp_port FROM sys.dm_exec_connections WHERE session_id = @@SPID"
                $port = $server.Query($sql)

                [PSCustomObject]@{
                    ComputerName = $server.NetName
                    InstanceName = $server.ServiceName
                    SqlInstance  = $server.DomainInstanceName
                    Port         = $port.local_tcp_port
                }
            }
        }
    }
}
