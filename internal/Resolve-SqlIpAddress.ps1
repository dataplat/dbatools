function Resolve-SqlIpAddress {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [Alias("ServerInstance", "SqlServer")]
        [object]$SqlInstance,
        [PSCredential]$SqlCredential
    )

    $server = Connect-SqlInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
    $servernetbios = $server.ComputerNamePhysicalNetBIOS
    $ipaddr = (Test-Connection $servernetbios -count 1).Ipv4Address
    return $ipaddr
}
