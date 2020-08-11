function Test-SqlSa {
    <#
    .SYNOPSIS
        Internal function. Ensures sysadmin account access on SQL Server.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [object]$SqlInstance,
        [PSCredential]$SqlCredential
    )

    try {

        if ($SqlInstance.GetType() -eq [Microsoft.SqlServer.Management.Smo.Server]) {
            return ($SqlInstance.ConnectionContext.FixedServerRoles -match "SysAdmin")
        }

        $server = Connect-SqlInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
        return ($server.ConnectionContext.FixedServerRoles -match "SysAdmin")
    } catch { return $false }
}