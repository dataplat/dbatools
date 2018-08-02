function Resolve-NetBiosName {
    <#
.SYNOPSIS
Internal function. Takes a best guess at the NetBIOS name of a server.
 #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [Alias("ServerInstance", "SqlServer")]
        [object]$SqlInstance,
        [PSCredential]$SqlCredential
    )
    $server = Connect-SqlInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
    $server.ComputerName
}