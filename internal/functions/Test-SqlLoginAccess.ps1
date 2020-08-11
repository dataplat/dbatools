function Test-SqlLoginAccess {
    <#
    .SYNOPSIS
        Internal function. Ensures login has access on SQL Server.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [object]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string]$Login
        #[switch]$Detailed - can return if its a login or just has access
    )

    if ($SqlInstance.GetType() -ne [Microsoft.SqlServer.Management.Smo.Server]) {
        $SqlInstance = Connect-SqlInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
    }

    if (($SqlInstance.Logins.Name) -notcontains $Login) {
        try {
            $rows = $SqlInstance.ConnectionContext.ExecuteScalar("EXEC xp_logininfo '$Login'")

            if (($rows | Measure-Object).Count -eq 0) {
                return $false
            }
        } catch {
            return $false
        }
    }
    return $true
}