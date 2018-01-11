function Update-SqlDbReadOnly {
    <#
    .SYNOPSIS
        Internal function. Updates specified database to read-only or read-write. Necessary because SMO doesn't appear to support NO_WAIT.
#>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseShouldProcessForStateChangingFunctions", "")]
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [Alias("ServerInstance", "SqlServer")]
        [object]$SqlInstance,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$dbname,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [bool]$readonly
    )

    if ($readonly) {
        Stop-DbaProcess -SqlInstance $SqlInstance -Database $dbname
        $sql = "ALTER DATABASE [$dbname] SET READ_ONLY WITH NO_WAIT"
    }
    else {
        $sql = "ALTER DATABASE [$dbname] SET READ_WRITE WITH NO_WAIT"
    }

    try {
        $server = Connect-SqlInstance -SqlInstance $SqlInstance
        $null = $server.Query($sql)
        Write-Message -Level Verbose -Message "Changed ReadOnly status to $readonly for $dbname on $($server.name)"
        return $true
    }
    catch {
        Write-Message -Level Warning "Could not change readonly status for $dbname on $($server.name)"
        return $false
    }
}
