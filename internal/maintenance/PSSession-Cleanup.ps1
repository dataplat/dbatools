$scriptBlock = {
    while ([Sqlcollaborative.Dbatools.Connection.ConnectionHost]::PSSessionCountExpired -gt 0) {
        $session = $null
        $session = [Sqlcollaborative.Dbatools.Connection.ConnectionHost]::PSSessionPurgeExpired()
        if ($null -ne $session) { $session | Remove-PSSession }
    }
}
Register-DbaMaintenanceTask -Name "pssession_cleanup" -ScriptBlock $scriptBlock -Delay (New-TimeSpan -Minutes 1) -Priority Low -Interval (New-TimeSpan -Minutes 1)