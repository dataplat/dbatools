function Remove-SqlDatabase {
    <#
    .SYNOPSIS
    Internal function. Uses SMO's KillDatabase to drop all user connections then drop a database. $server is
    an SMO server object.
    THIS FUNCTION IS HERE BECAUSE OF LEGACY REQUIREMENTS. (Copy-DbaDatabase, Test-DbaLastBackup, Remove-DbaDatabaseSafely)
#>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseShouldProcessForStateChangingFunctions", "")]
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [Alias("ServerInstance", "SqlServer")]
        [object]$SqlInstance,
        [Parameter(Mandatory = $true)]
        [string]$DBName,
        [PSCredential]$SqlCredential
    )

    $escapedname = "[$dbname]"

    try {
        $server = Connect-SqlInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
        $server.KillDatabase($dbname)
        $server.Refresh()
        return "Successfully dropped $dbname on $($server.name)"
    }
    catch {
        try {
            $null = $server.Query("DROP DATABASE $escapedname")
            return "Successfully dropped $dbname on $($server.name)"
        }
        catch {
            try {
                $server.databases[$dbname].Drop()
                $server.Refresh()
                return "Successfully dropped $dbname on $($server.name)"
            }
            catch {
                return $_
            }
        }
    }
}
