function Resolve-SqlIpAddress {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [Alias("ServerInstance", "SqlServer")]
        [object]$SqlInstance,
        [PSCredential]$SqlCredential
    )

    $server = Connect-SqlInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
    $servernetbios = $server.ComputerNamePhysicalNetBIOS
    $ipaddr = (Resolve-DbaNetworkName -ComputerName $servernetbios -Turbo).IPAddress
    return $ipaddr
}