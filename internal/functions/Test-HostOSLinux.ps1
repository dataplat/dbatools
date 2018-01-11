function Test-HostOSLinux {
    param (
        [object]$SqlInstance,
        [object]$sqlcredential
    )

    $server = Connect-SqlInstance -SqlInstance $SqlInstance -SqlCredential $sqlcredential
    $server.ConnectionContext.ExecuteScalar("SELECT @@VERSION") -match "Linux"
}
