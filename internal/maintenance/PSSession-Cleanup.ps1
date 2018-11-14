$scriptBlock = {
    while ([Sqlcollaborative.Dbatools.Connection.ConnectionHost]::PSSessionCountExpired -gt 0) {
        $session = $null
        $session = [Sqlcollaborative.Dbatools.Connection.ConnectionHost]::PSSessionPurgeExpired()
        if ($null -ne $session) { $session | Remove-PSSession }
    }
}
Register-DbaMaintenanceTask -Name "pssession_cleanup" -ScriptBlock $scriptBlock -Delay (New-TimeSpan -Minutes 1) -Priority Low -Interval (New-TimeSpan -Minutes 1)

# Cleans up local references in the current runspace. All actual termination logic is handled by the task above
$script:pssession_cleanup_timer = New-Object System.Timers.TImer
$script:pssession_cleanup_timer.Interval = 60000
$null = Register-ObjectEvent -InputObject $script:pssession_cleanup_timer -EventName elapsed -SourceIdentifier dbatools_Timer -Action { Get-PSSession | Where-Object State -Like Closed | Remove-PSSession } -ErrorAction Ignore
$script:pssession_cleanup_timer.Start()