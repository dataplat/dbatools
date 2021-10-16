function Restart-WinRMService {
    <#
    .SYNOPSIS
        Restarts WinRM service on a remote machine and waits for it to get back up
    .DESCRIPTION
        Restarts WinRM service on a remote machine and waits for it to get back up by attempting to establish a WinRM session.
    #>

    [CmdletBinding(SupportsShouldProcess)]
    Param (
        [Parameter(Mandatory)]
        $ComputerName,
        [pscredential]$Credential,
        [int]$Timeout = 30
    )
    begin {

    }
    process {
        if ($PSCmdlet.ShouldProcess($ComputerName, "Restarting WinRm service")) {
            $restartService = {
                $null = Get-Service -Name WinRM -ErrorAction Stop | Restart-Service -ErrorAction Stop
            }
            try {
                $null = Invoke-Command2 -ComputerName $ComputerName -Credential $Credential -ScriptBlock $restartService -Raw -ErrorAction Stop
            } catch [System.Management.Automation.Remoting.PSRemotingTransportException] {
                Write-Message -Level Debug "Expected exception - the pipe was disconnected | $($_.Exception.Message)"
            } catch {
                Write-Message -Level Warning "Failed to restart WinRM service on $ComputerName"
            }
            Write-Message -Level Debug "Removing existing local sessions to $ComputerName - they are no longer valid"
            $runspaceId = [System.Management.Automation.Runspaces.Runspace]::DefaultRunspace.InstanceId
            # Retrieve a session from the session cache, if available (it's unique per runspace)
            [array]$currentSessions = [Sqlcollaborative.Dbatools.Connection.ConnectionHost]::PSSessionGet($runspaceId, $ComputerName)
            Write-Message -Level Debug -Message "Removing $($currentSessions.Count) sessions from $ComputerName in runspace $runspaceId"
            $currentSessions | Remove-PSSession
            Write-Message -Level Debug "Waiting for the WinRM service to restart on $ComputerName"
            $waitCounter = 0
            while ($waitCounter -lt $Timeout * 5) {
                try {
                    $available = Invoke-Command2 -ComputerName $ComputerName -Credential $Credential -ScriptBlock { $true } -Raw -ErrorAction Stop
                } catch {
                    Write-Message -Level Debug -Message "Still waiting for the WinRM service to restart on $ComputerName"
                }
                if ($available) { break }
                Start-Sleep -Milliseconds 200
                $waitCounter++
            }
        }
        Write-Message -Level Debug -Message "WinRM restart comlete on $ComputerName"
    }
}