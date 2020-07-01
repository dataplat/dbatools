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
    $destComputer=$null
    if ($Server.GetType() -eq [Microsoft.SqlServer.Management.Smo.Server]) {
        if($server.computername){
            $destComputer=$server.Computername
        }elseif($server.name){
            $destComputer=$server.name
        }
    } else {
        $destComputer=$server.Split('\')[0]
    }
    return $ping.Send($destComputer, $timeout).Address.IPAddressToString
}
