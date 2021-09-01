function Test-HostOSLinux {
    param (
        [object]$SqlInstance,
        [object]$SqlCredential
    )

    $server = Connect-DbaInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
    $server.ConnectionContext.ExecuteScalar("SELECT @@VERSION") -match "Linux"
}