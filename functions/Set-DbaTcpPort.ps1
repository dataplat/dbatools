#ValidationTags#Messaging,FlowControl,Pipeline,CodeStyle#

Function Set-DbaTcpPort {
<#
    .SYNOPSIS
        Changes the TCP port used by the specified SQL Server.
    
    .DESCRIPTION
        This function changes the TCP port used by the specified SQL Server.
    
    .PARAMETER SqlInstance
        The SQL Server that you're connecting to.
    
    .PARAMETER Credential
        Credential object used to connect to the SQL Server as a different user
    
    .PARAMETER Port
        TCPPort that SQLService should listen on.
    
    .PARAMETER IPAddress
        Wich IPAddress should the portchange , if omitted allip (0.0.0.0) will be changed with the new portnumber.
    
    .PARAMETER Silent
        Replaces user friendly yellow warnings with bloody red exceptions of doom!
        Use this if you want the function to throw terminating errors you want to catch.
    
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
        Author: Hansson7707@gmail.com
        
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
        [DbaInstanceParameter[]]
        $SqlInstance,
        
        [Alias("SqlCredential")]
        [PsCredential]
        $Credential,
        
        [parameter(Mandatory = $true)]
        [ValidateRange(1, 65535)]
        [int]
        $Port,
        
        [ipaddress[]]
        $IpAddress,
        
        [switch]
        $Silent
    )
    
    begin {
        
        if ($ipaddress.Length -eq 0) {
            $ipaddress = '0.0.0.0'
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
                Stop-Function -Message "Failed to connect to: $instance" -Target $instance -ErrorRecord $_ -Continue
            }
            
            $wmiinstancename = $server.instanceName
            if ($wmiinstancename.length -eq 0) {
                $wmiinstancename = 'MSSqlInstance'
            }
            if ($server.IsClustered) {
                Write-Message -Level Verbose -Message "Instance is clustered fetching nodes..."
                $clusterquery = "select nodename from sys.dm_os_cluster_nodes where not nodename = '$($server.ComputerNamePhysicalNetBIOS)'"
                $clusterresult = $server.ConnectionContext.ExecuteWithResults("$clusterquery")
                foreach ($row in $clusterresult.tables[0].rows) { $ClusterNodes += $row.Item(0) + " " }
                Write-Warning "$instance is a clustered instance, portchanges will be reflected on other nodes ( $clusternodes) after a failover..."
            }
            $scriptblock = {
                $instance = $args[0]
                $wmiinstancename = $args[1]
                $port = $args[2]
                $ipaddress = $args[3]
                $wmi = New-Object Microsoft.SqlServer.Management.Smo.Wmi.ManagedComputer $instance
                $wmiinstance = $wmi.ServerInstances | Where-Object { $_.Name -eq $wmiinstancename }
                $tcp = $wmiinstance.ServerProtocols | Where-Object { $_.DisplayName -eq 'TCP/IP' }
                $ipaddress = $tcp.IPAddresses | where-object { $_.IPAddress -eq $ipaddress }
                $tcpport = $ipaddress.IPAddressProperties | Where-Object { $_.Name -eq 'TcpPort' }
                
                try {
                    $tcpport.value = $port
                    $tcp.Alter()
                }
                catch {
                    # Can't do a stop function because this is a remote session
                    return $_
                }
            }
            
            try {
                $computerName = $instance.ComputerName
                $resolved = Resolve-DbaNetworkName -ComputerName $computerName
                
                Write-Message -Level Verbose -Message "Writing TCPPort $port for $instance to $($resolved.FQDN)..."
                $setport = Invoke-ManagedComputerCommand -Server $resolved.FQDN -ScriptBlock $scriptblock -ArgumentList $Server.NetName, $wmiinstancename, $port, $ipaddress
                if ($setport.length -eq 0) {
                    if ($ipaddress -eq '0.0.0.0') {
                        Write-Message -Level Verbose -Message "SqlInstance: $instance IPADDRESS: ALLIP's PORT: $port"
                    }
                    else {
                        Write-Message -Level Verbose -Message "SqlInstance: $instance IPADDRESS: $ipaddress PORT: $port"
                    }
                }
                else {
                    if ($ipaddress -eq '0.0.0.0') {
                        Write-Message -Level Verbose -Message "SqlInstance: $instance IPADDRESS: ALLIP's PORT: $port"
                        Write-Message -Level Verbose -Message " FAILED!" -ForegroundColor Red
                    }
                    else {
                        Write-Message -Level Verbose -Message "SqlInstance: $instance IPADDRESS: $ipaddress PORT: $port"
                        Write-Message -Level Verbose -Message " FAILED!" -ForegroundColor Red
                    }
                }
            }
            catch {
                try {
                    Write-Message -Level Verbose -Message "Failed to write TCPPort $port for $instance to $($resolved.FQDN) trying computername $($server.ComputerNamePhysicalNetBIOS)...."
                    $setport = Invoke-ManagedComputerCommand -Server $server.ComputerNamePhysicalNetBIOS -ScriptBlock $scriptblock -ArgumentList $Server.NetName, $wmiinstancename, $port, $ipaddress
                    if ($setport.length -eq 0) {
                        if ($ipaddress -eq '0.0.0.0') {
                            Write-Message -Level Verbose -Message "SqlInstance: $instance IPADDRESS: ALLIP's PORT: $port"
                        }
                        else {
                            Write-Message -Level Verbose -Message "SqlInstance: $instance IPADDRESS: $ipaddress PORT: $port"
                        }
                    }
                    else {
                        if ($ipaddress -eq '0.0.0.0') {
                            Write-Message -Level Verbose -Message "SqlInstance: $instance IPADDRESS: ALLIP's PORT: $port"
                            Write-Message -Level Verbose -Message " FAILED!" -ForegroundColor Red
                        }
                        else {
                            Write-Message -Level Verbose -Message "SqlInstance: $instance IPADDRESS: $ipaddress PORT: $port"
                            Write-Message -Level Verbose -Message " FAILED!" -ForegroundColor Red
                        }
                    }
                }
                catch {
                    Stop-Function -Message "Could not write new TCPPort for $instance" -Continue -Target $instance -ErrorRecord $_
                }
            }
        }
    }
}