function Resolve-SqlIpAddress {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]$SqlInstance,
        [PSCredential]$SqlCredential
    )

    $server = Connect-SqlInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
    $servernetbios = $server.ComputerNamePhysicalNetBIOS
    $ipaddr = (Resolve-DbaNetworkName -ComputerName $servernetbios -Turbo).IPAddress
    return $ipaddr
}