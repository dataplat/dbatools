# Only needed on Windows Core (pwsh 6+ on .NET), where SqlClient defaults to the native SNI.dll.
# On Linux/macOS, SqlClient already uses managed networking; on Windows Desktop (PS 5.1),
# this switch has no effect because it uses System.Data.SqlClient. The guard makes it clear
# we're setting this only where native SNI could otherwise cause connection issues.

if ($IsWindows) {
    try {
        [System.AppContext]::SetSwitch(
            "Switch.Microsoft.Data.SqlClient.UseManagedNetworkingOnWindows",
            $true
        )
        Write-Verbose "dbatools: Using managed networking for SqlClient (no native SNI)."
    } catch {
        Write-Verbose "dbatools: Could not set managed networking switch: $_"
    }
}
