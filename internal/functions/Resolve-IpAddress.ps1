function Resolve-IpAddress {
    # Uses the Beard's method to resolve IPs
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [Alias("ServerInstance", "SqlInstance", "ComputerName", "SqlServer")]
        [object]$Server
    )

    if ($Server.GetType() -eq [Microsoft.SqlServer.Management.Smo.Server]) {
        return $ipaddress = ((Test-Connection $Server.NetName -Count 1 -ErrorAction SilentlyContinue).Ipv4Address).IPAddressToString
    }
    else {
        return $ipaddress = ((Test-Connection $server.Split('\')[0] -Count 1 -ErrorAction SilentlyContinue).Ipv4Address).IPAddressToString
    }
}
