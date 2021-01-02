function Test-SqlAgent {
    <#
    .SYNOPSIS
        Internal function. Checks to see if SQL Server Agent is running on a server.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [object]$SqlInstance,
        [PSCredential]$SqlCredential
    )

    if ($SqlInstance.GetType() -ne [Microsoft.SqlServer.Management.Smo.Server]) {
        $SqlInstance = Connect-SqlInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
    }

    if ($null -eq $SqlInstance.JobServer) { return $false }
    try { $null = $SqlInstance.JobServer.script(); return $true }
    catch { return $false }
}