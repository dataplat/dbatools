function Unregister-RemoteSessionConfiguration {
    <#
    .SYNOPSIS
        Unregisters a PSSessionConfiguration on a remote machine
    .DESCRIPTION
        Unregisters a session previously created with Register-RemoteSessionConfiguration through WinRM.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    Param (
        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        $ComputerName,
        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,
        [pscredential]$Credential
    )
    begin {

    }
    process {
        $removeRunasSession = {
            Param (
                $Name
            )
            $existing = Get-PSSessionConfiguration -Name $Name -ErrorAction SilentlyContinue
            if ($null -eq $existing) {
                return [pscustomobject]@{ 'Name' = $Name ; 'Status' = 'Not found'; Successful = $true }
            } else {
                try {
                    Unregister-PSSessionConfiguration -Name $Name -ErrorAction Stop -NoServiceRestart -Confirm:$false 3>$null
                    [pscustomobject]@{ 'Name' = $Name; 'Status' = 'Unregistered' ; Successful = $true }
                } catch {
                    return [pscustomobject]@{ 'Name' = $Name ; 'Status' = $_  ; Successful = $false }
                }
            }
        }
        if ($PSCmdlet.ShouldProcess($ComputerName, "Unregistering session configuration $Name")) {
            try {
                $unregisterIt = Invoke-Command2 -ComputerName $ComputerName -Credential $Credential -ScriptBlock $removeRunasSession -ArgumentList @($Name) -Raw -RequiredPSVersion 3.0
            } catch {
                Stop-Function -Message "Failure during remote session configuration execution" -ErrorRecord $_ -EnableException $true
            }
        }
        if ($unregisterIt) {
            Write-Message -Level Debug -Message "Configuration attempt returned the following status`: $($unregisterIt.Status)"
            if ($unregisterIt.Status -eq 'Unregistered') {
                Write-Message -Level Verbose -Message "Restarting WinRm service on $ComputerName"
                Restart-WinRMService -ComputerName $ComputerName -Credential $Credential
            }
            return $unregisterIt
        }
    }
}