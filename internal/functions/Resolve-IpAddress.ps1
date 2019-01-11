function Resolve-IpAddress {
    # Uses the Beard's method to resolve IPs
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [Alias("ServerInstance", "SqlInstance", "ComputerName", "SqlServer")]
        [object]$Server
    )
    $ping = New-Object System.Net.NetworkInformation.Ping
    $timeout = 1000 #milliseconds
    if ($Server.GetType() -eq [Microsoft.SqlServer.Management.Smo.Server]) {
        return $ping.Send($Server.ComputerName, $timeout).Address.IPAddressToString
    } else {
        return $ping.Send($server.Split('\')[0], $timeout).Address.IPAddressToString
    }
}