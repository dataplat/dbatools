function Unregister-RemoteSessionConfiguration {
    <#
    Unregisters a session previously created with Register-RemoteSessionConfiguration through WinRM.
    #>
    [CmdletBinding()]
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
                    Unregister-PSSessionConfiguration -Name $Name -Force -ErrorAction Stop -NoServiceRestart 3>$null
                    [pscustomobject]@{ 'Name' = $Name; 'Status' = 'Unregistered' ; Successful = $true }
                } catch {
                    return [pscustomobject]@{ 'Name' = $Name ; 'Status' = $_  ; Successful = $false}
                }
            }
        }

        $unregisterIt = Invoke-Command2 -ComputerName $ComputerName -Credential $Credential -ScriptBlock $removeRunasSession -ArgumentList @($Name)

        Write-Message -Level Verbose -Message "Restarting WinRm service on $ComputerName"
        try {
            $null = Get-Service -ComputerName $ComputerName -Name WinRM -ErrorAction Stop | Restart-Service -ErrorAction Stop
        } catch {
            Write-Message -Level Warning "Failed to restart WinRM service on a remote machine, authentication might fail to work as expected"
        }

        return $unregisterIt
    }
}