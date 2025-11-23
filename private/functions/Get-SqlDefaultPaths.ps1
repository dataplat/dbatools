function Get-SqlDefaultPaths {
    <#
    .SYNOPSIS
        Internal function. Returns the default data and log paths for SQL Server. Needed because SMO's server.defaultpath is sometimes null.
    #>
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseSingularNouns", "")]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [object]$SqlInstance,
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$filetype,
        [PSCredential]$SqlCredential
    )

    try {
        if ($SqlInstance -isnot [Microsoft.SqlServer.Management.Smo.SqlSmoObject]) {
            $Server = Connect-DbaInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
        } else {
            $server = $SqlInstance
        }
    } catch {
        Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $SqlInstance
        return
    }
    switch ($filetype) { "mdf" { $filetype = "data" } "ldf" { $filetype = "log" } }

    if ($filetype -eq "log") {
        # First attempt
        $filepath = $server.DefaultLog
        # Second attempt
        if ($filepath.Length -eq 0) { $filepath = $server.Information.MasterDbLogPath }
        # Third attempt
        if ($filepath.Length -eq 0) {
            $sql = "SELECT SERVERPROPERTY('InstanceDefaultLogPath') AS physical_name"
            $filepath = $server.ConnectionContext.ExecuteScalar($sql)
        }
    } else {
        # First attempt
        $filepath = $server.DefaultFile
        # Second attempt
        if ($filepath.Length -eq 0) { $filepath = $server.Information.MasterDbPath }
        # Third attempt
        if ($filepath.Length -eq 0) {
            $sql = "SELECT SERVERPROPERTY('InstanceDefaultDataPath') AS physical_name"
            $filepath = $server.ConnectionContext.ExecuteScalar($sql)
        }
    }

    if ($filepath.Length -eq 0) { throw "Cannot determine the required directory path" }
    $filepath = $filepath.TrimEnd("\")
    return $filepath
}