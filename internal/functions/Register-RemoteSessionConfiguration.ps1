function Register-RemoteSessionConfiguration {
    <#
    Registers a session with a custom credentials on a remote machine through WinRM.
    Designed to overcome the double-hop issue and as an alternative to CredSSP protocol.
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory)]
        $ComputerName,
        [ValidateNotNullOrEmpty()]
        [string]$Name = "dbatools_remotesession",
        [Parameter(Mandatory)]
        [pscredential]$Credential,
        [pscredential]$RunAsCredential = $Credential
    )
    begin {

    }
    process {
        $createRunasSession = {
            Param (
                $Name,
                $user,
                $pwd
            )
            $credential = New-Object System.Management.Automation.PSCredential @($user, (ConvertTo-SecureString -Force -AsPlainText $pwd))
            $existing = Get-PSSessionConfiguration -Name $Name -ErrorAction SilentlyContinue
            if ($null -eq $existing) {
                try {
                    $null = Register-PSSessionConfiguration -Name $Name -RunAsCredential $credential -Force -ErrorAction Stop -NoServiceRestart 3>$null
                    return [pscustomobject]@{ 'Name' = $Name; 'Status' = 'Created' ; Successful = $true }
                } catch {
                    return [pscustomobject]@{ 'Name' = $Name ; 'Status' = $_.Exception.Message ; Successful = $false }
                }
            } else {
                try {
                    Set-PSSessionConfiguration -Name $Name -RunAsCredential $credential -Force -ErrorAction Stop -NoServiceRestart 3>$null
                    [pscustomobject]@{ 'Name' = $Name; 'Status' = 'Updated' ; Successful = $true }
                } catch {
                    return [pscustomobject]@{ 'Name' = $Name ; 'Status' = $_.Exception.Message ; Successful = $false }
                }
            }
        }

        $registerIt = Invoke-Command2 -ComputerName $ComputerName -Credential $Credential -ScriptBlock $createRunasSession -ArgumentList @(
            $Name,
            $RunAsCredential.UserName,
            $RunAsCredential.GetNetworkCredential().Password
        )

        Write-Message -Level Verbose -Message "Restarting WinRm service on $ComputerName"
        Restart-WinRMService -ComputerName $ComputerName -Credential $Credential

        return $registerIt
    }
}