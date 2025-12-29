function Get-DbaNetworkActivity {
    <#
    .SYNOPSIS
        Retrieves real-time network traffic statistics for all network interfaces on SQL Server host computers.

    .DESCRIPTION
        Retrieves current network activity metrics including bytes received, sent, and total throughput per second for every network interface on target computers. This function helps DBAs monitor network performance and identify bandwidth bottlenecks that could impact SQL Server performance, especially during large data transfers, backup operations, or heavy replication traffic.

        The function queries Windows performance counters via CIM/WMI and displays bandwidth utilization alongside interface capacity (10Gb, 1Gb, 100Mb, etc.) to quickly identify saturated network links. Essential for troubleshooting connectivity issues, monitoring backup network performance, or validating network capacity before major data migration operations.

        Requires Local Admin rights on destination computer(s).

    .PARAMETER ComputerName
        Specifies the computer names or SQL Server instances to monitor network activity.
        Function extracts the computer name from full instance names and resolves them to fully qualified domain names.
        Defaults to the local computer when not specified.

    .PARAMETER Credential
        Credential object used to connect to the computer as a different user.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Server, Management, Network
        Author: Klaas Vandenberghe (@PowerDBAKlaas)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .OUTPUTS
        Win32_PerfFormattedData_Tcpip_NetworkInterface

        Returns one object per network interface found on the target computer(s).

        Default display properties (via Select-DefaultView):
        - ComputerName: The name of the computer containing the network interface
        - NIC: The name of the network interface (alias for Name property)
        - BytesReceivedPersec: Bytes received per second on this interface (numeric value)
        - BytesSentPersec: Bytes sent per second on this interface (numeric value)
        - BytesTotalPersec: Total bytes per second (received + sent) on this interface (numeric value)
        - Bandwidth: Human-readable interface bandwidth capacity (10Gb, 1Gb, 100Mb, 10Mb, 1Mb, 100Kb, or Low)

        Additional properties available (from Win32_PerfFormattedData_Tcpip_NetworkInterface):
        - CurrentBandwidth: Numeric bandwidth in bits per second (used to calculate display Bandwidth)
        - OutputQueueLength: Queue length for outbound data
        - PacketsReceivedPersec: Number of packets received per second
        - PacketsSentPersec: Number of packets sent per second
        - PacketsOutboundErrors: Number of transmission errors
        - PacketsReceivedErrors: Number of receive errors
        - PacketsReceivedDiscarded: Number of received packets discarded
        - PacketsOutboundDiscarded: Number of transmitted packets discarded

        All properties from the base WMI object are accessible using Select-Object *.

    .LINK
        https://dbatools.io/Get-DbaNetworkActivity

    .EXAMPLE
        PS C:\> Get-DbaNetworkActivity -ComputerName sqlserver2014a

        Gets the Current traffic on every Network Interface on computer sqlserver2014a.

    .EXAMPLE
        PS C:\> 'sql1','sql2','sql3' | Get-DbaNetworkActivity

        Gets the Current traffic on every Network Interface on computers sql1, sql2 and sql3.

    .EXAMPLE
        PS C:\> Get-DbaNetworkActivity -ComputerName sql1,sql2

        Gets the Current traffic on every Network Interface on computers sql1 and sql2.
    #>
    [CmdletBinding()]
    param (
        [parameter(ValueFromPipeline)]
        [Alias("cn", "host", "Server")]
        [string[]]$ComputerName = $env:COMPUTERNAME,
        [PSCredential] $Credential,
        [switch]$EnableException
    )

    begin {
        $ComputerName = $ComputerName | ForEach-Object { $_.split("\")[0] } | Select-Object -Unique
        $sessionoption = New-CimSessionOption -Protocol DCom
    }
    process {
        foreach ($computer in $ComputerName) {
            $Server = Resolve-DbaNetworkName -ComputerName $Computer -Credential $credential
            if ( $Server.FullComputerName ) {
                $Computer = $server.FullComputerName
                Write-Message -Level Verbose -Message "Creating CIMSession on $computer over WSMan"
                $CIMsession = New-CimSession -ComputerName $Computer -ErrorAction SilentlyContinue -Credential $Credential
                if ( -not $CIMSession ) {
                    Write-Message -Level Verbose -Message "Creating CIMSession on $computer over WSMan failed. Creating CIMSession on $computer over DCom"
                    $CIMsession = New-CimSession -ComputerName $Computer -SessionOption $sessionoption -ErrorAction SilentlyContinue -Credential $Credential
                }
                if ( $CIMSession ) {
                    Write-Message -Level Verbose -Message "Getting properties for Network Interfaces on $computer"
                    $NICs = Get-CimInstance -CimSession $CIMSession -ClassName Win32_PerfFormattedData_Tcpip_NetworkInterface
                    $NICs | Add-Member -Force -MemberType ScriptProperty -Name ComputerName -Value { $computer }
                    $NICs | Add-Member -Force -MemberType ScriptProperty -Name Bandwith -Value { switch ( $this.CurrentBandWidth ) { 10000000000 { '10Gb' } 1000000000 { '1Gb' } 100000000 { '100Mb' } 10000000 { '10Mb' } 1000000 { '1Mb' } 100000 { '100Kb' } default { 'Low' } } }
                    foreach ( $NIC in $NICs ) { Select-DefaultView -InputObject $NIC -Property 'ComputerName', 'Name as NIC', 'BytesReceivedPersec', 'BytesSentPersec', 'BytesTotalPersec', 'Bandwidth' }
                } #if CIMSession
                else {
                    Write-Message -Level Warning -Message "Can't create CIMSession on $computer"
                }
            } #if computername
            else {
                Write-Message -Level Warning -Message "can't connect to $computer"
            }
        } #foreach computer
    } #PROCESS
} #function