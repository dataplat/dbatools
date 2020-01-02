function Get-SqlSaLogin {
    <#
        .SYNOPSIS
            Internal function. Gets the name of the sa login in case someone changed it.
        .PARAMETER SqlInstance
            The SQL Server instance.
        .PARAMETER SqlCredential
            Allows you to login to servers using SQL Logins instead of Windows Authentication (AKA Integrated or Trusted).
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]$SqlInstance,
        [PSCredential]$SqlCredential
    )
    $server = Connect-SqlInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
    $sa = $server.Logins | Where-Object Id -eq 1
    return $sa.Name
}