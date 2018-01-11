#ValidationTags#Messaging,FlowControl,Pipeline,CodeStyle#

function Set-DbaTcpPort {
    <#
    .SYNOPSIS
        Changes the TCP port used by the specified SQL Server.

    .DESCRIPTION
        This function changes the TCP port used by the specified SQL Server.

    .PARAMETER SqlInstance
        The SQL Server that you're connecting to.

     .PARAMETER SqlCredential
        Credential object used to connect to the SQL Server instance as a different user

    .PARAMETER Credential
        Credential object used to connect to the Windows server itself as a different user

    .PARAMETER Port
        TCPPort that SQLService should listen on.

    .PARAMETER IpAddress
        Wich IpAddress should the portchange , if omitted allip (0.0.0.0) will be changed with the new portnumber.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .EXAMPLE
        Set-DbaTcpPort -SqlInstance SqlInstance2014a -Port 1433

        Sets the port number 1433 for allips on the default instance on SqlInstance2014a

    .EXAMPLE
        Set-DbaTcpPort -SqlInstance winserver\sqlexpress -IpAddress 192.168.1.22 -Port 1433

        Sets the port number 1433 for IP 192.168.1.22 on the sqlexpress instance on winserver

    .EXAMPLE
        Set-DbaTcpPort -SqlInstance 'SQLDB2014A' ,'SQLDB2016B' -port 1337

        Sets the port number 1337 for ALLIP's on SqlInstance SQLDB2014A and SQLDB2016B

    .NOTES
        Author: Hansson7707@gmail.com, @H0s0n77

        Website: https://dbatools.io
        Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
        License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

    .LINK
        https://dbatools.io/Set-DbaTcpPort
#>
    [CmdletBinding(ConfirmImpact = "High")]
    Param (
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [PSCredential]$Credential,
        [parameter(Mandatory = $true)]
        [ValidateRange(1, 65535)]
        [int]$Port,
        [IpAddress[]]$IpAddress,
        [switch][Alias('Silent')]$EnableException
    )

    begin {

        if ($IpAddress.Length -eq 0) {
            $IpAddress = '0.0.0.0'
        }
        else {
            if ($SqlInstance.count -gt 1) {
                Stop-Function -Message "-IpAddress switch cannot be used with a collection of serveraddresses" -Target $SqlInstance
                return
            }
        }
    }

    process {
        if (Test-FunctionInterrupt) { return }

        foreach ($instance in $SqlInstance) {

            try {
                Write-Message -Level Verbose -Message "Connecting to $instance"
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $wmiinstancename = $server.ServiceName


            if ($server.IsClustered) {
                Write-Message -Level Verbose -Message "Instance is clustered fetching nodes..."
                $clusternodes = (Get-DbaClusterActiveNode -SqlInstance $server -Detailed).NodeName -join ", "

                Write-Message -Level Output -Message "$instance is a clustered instance, portchanges will be reflected on all nodes ($clusternodes) after a failover"
            }

            $scriptblock = {
                $instance = $args[0]
                $wmiinstancename = $args[1]
                $port = $args[2]
                $IpAddress = $args[3]
                $sqlinstanceName = $args[4]

                $wmi = New-Object Microsoft.SqlServer.Management.Smo.Wmi.ManagedComputer $instance
                $wmiinstance = $wmi.ServerInstances | Where-Object { $_.Name -eq $wmiinstancename }
                $tcp = $wmiinstance.ServerProtocols | Where-Object { $_.DisplayName -eq 'TCP/IP' }
                $IpAddress = $tcp.IpAddresses | where-object { $_.IpAddress -eq $IpAddress }
                $tcpport = $IpAddress.IpAddressProperties | Where-Object { $_.Name -eq 'TcpPort' }

                $oldport = $tcpport.Value
                try {
                    $tcpport.value = $port
                    $tcp.Alter()
                    [pscustomobject]@{
                        ComputerName  = $env:COMPUTERNAME
                        InstanceName  = $wmiinstancename
                        SqlInstance   = $sqlinstanceName
                        OldPortNumber = $oldport
                        PortNumber    = $Port
                        Status        = "Success"
                    }
                }
                catch {
                    [pscustomobject]@{
                        ComputerName  = $env:COMPUTERNAME
                        InstanceName  = $wmiinstancename
                        SqlInstance   = $sqlinstanceName
                        OldPortNumber = $oldport
                        PortNumber    = $Port
                        Status        = "Failed: $_"
                    }
                }
            }

            try {
                $computerName = $instance.ComputerName
                $resolved = Resolve-DbaNetworkName -ComputerName $computerName

                Write-Message -Level Verbose -Message "Writing TCPPort $port for $instance to $($resolved.FQDN)..."
                Invoke-ManagedComputerCommand -ComputerName $resolved.FQDN -ScriptBlock $scriptblock -ArgumentList $Server.NetName, $wmiinstancename, $port, $IpAddress, $server.DomainInstanceName -Credential $Credential

            }
            catch {
                Invoke-ManagedComputerCommand -ComputerName $server.ComputerNamePhysicalNetBIOS -ScriptBlock $scriptblock -ArgumentList $Server.NetName, $wmiinstancename, $port, $IpAddress, $server.DomainInstanceName -Credential $Credential
            }
        }
    }
}