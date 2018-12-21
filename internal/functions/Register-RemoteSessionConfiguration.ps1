function Register-RemoteSessionConfiguration {
    <#
    .SYNOPSIS
        Registers a PSSessionConfiguration on a remote machine
    .DESCRIPTION
        Registers a session with a custom credentials on a remote machine through WinRM.
        Designed to overcome the double-hop issue and as an alternative to CredSSP protocol.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingConvertToSecureStringWithPlainText", "")]
    [CmdletBinding(SupportsShouldProcess)]
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
            $output = [pscustomobject]@{ 'Name' = $Name; 'Status' = $null ; Successful = $false }
            $credential = New-Object System.Management.Automation.PSCredential @($user, (ConvertTo-SecureString -Force -AsPlainText $pwd))
            try {
                $existing = Get-PSSessionConfiguration -Name $Name -ErrorAction Stop 2>$null
            } catch {
                $null = 1
            }
            try {
                if ($null -eq $existing) {
                    $null = Register-PSSessionConfiguration -Name $Name -RunAsCredential $credential -ErrorAction Stop -NoServiceRestart -Confirm:$false 3>$null
                    $output.Status = 'Created'
                    $output.Successful = $true
                    return $output
                } else {
                    Set-PSSessionConfiguration -Name $Name -RunAsCredential $credential -ErrorAction Stop -NoServiceRestart -Confirm:$false 3>$null
                    $output.Status = 'Updated'
                    $output.Successful = $true
                    return $output
                }
            } catch {
                $output.Status = "Failed`: $($_.Exception.Message)"
                return $output
            }
        }
        Write-Message -Level Debug -Message "Registering new session configuration $Name on $ComputerName"
        if ($PSCmdlet.ShouldProcess($ComputerName, "Registering new session configuration $Name")) {
            try {
                $registerIt = Invoke-Command2 -ComputerName $ComputerName -Credential $Credential -ScriptBlock $createRunasSession -ArgumentList @(
                    $Name,
                    $RunAsCredential.UserName,
                    $RunAsCredential.GetNetworkCredential().Password
                ) -Raw -RequiredPSVersion 3.0 -ErrorAction Stop
            } catch {
                Stop-Function -Message "Failure during remote session configuration execution" -ErrorRecord $_ -EnableException $true
            }
        }
        if ($registerIt) {
            Write-Message -Level Debug -Message "Configuration attempt returned the following status`: $($registerIt.Status)"
            if ($registerIt.Status -in 'Updated', 'Created') {
                Write-Message -Level Verbose -Message "Restarting WinRm service on $ComputerName"
                Restart-WinRMService -ComputerName $ComputerName -Credential $Credential
            }
            return $registerIt
        }
    }
}