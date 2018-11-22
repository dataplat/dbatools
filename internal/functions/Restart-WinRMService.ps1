function Restart-WinRMService {
    <#
    Restarts WinRM service on a remote machine and waits for it to get back up
    #>
    [CmdletBinding(SupportsShouldProcess)]
    Param (
        [Parameter(Mandatory)]
        $ComputerName,
        [pscredential]$Credential
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
            Write-Message -Level Debug "Waiting for the WinRM service to restart on $ComputerName"
            $waitCounter = 0
            while ($waitCounter -lt 30 * 5) {
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
    }
}