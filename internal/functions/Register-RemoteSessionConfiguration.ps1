function Register-RemoteSessionConfiguration {
    <#
    .SYNOPSIS
        Registers a PSSessionConfiguration on a remote machine
    .DESCRIPTION
        Registers a session with a custom credentials on a remote machine through WinRM.
        Designed to overcome the double-hop issue and as an alternative to CredSSP protocol.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingConvertToSecureStringWithPlainText", "")]
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
            $output = [pscustomobject]@{ 'Name' = $Name; 'Status' = $null ; Successful = $false }
            if ($PSVersionTable.PSVersion -le '2.0') {
                $output.Status = "Current version of Powershell $($PSVersionTable.PSVersion) does not support SessionConfiguration with custom credentials. Minimum requirement is 3.0"
                return $output
            }
            $credential = New-Object System.Management.Automation.PSCredential @($user, (ConvertTo-SecureString -Force -AsPlainText $pwd))
            try {
                $existing = Get-PSSessionConfiguration -Name $Name -ErrorAction Stop 2>$null
            } catch {
                $null = 1
            }
            try {
                if ($null -eq $existing) {
                    $null = Register-PSSessionConfiguration -Name $Name -RunAsCredential $credential -Force -ErrorAction Stop -NoServiceRestart 3>$null
                    $output.Status = 'Created'
                    $output.Successful = $true
                    return $output
                } else {
                    Set-PSSessionConfiguration -Name $Name -RunAsCredential $credential -Force -ErrorAction Stop -NoServiceRestart 3>$null
                    $output.Status = 'Updated'
                    $output.Successful = $true
                    return $output
                }
            } catch {
                $output.Status = "Failed`: $($_.Exception.Message)"
                return $output
            }
        }
        try {
            $registerIt = Invoke-Command2 -ComputerName $ComputerName -Credential $Credential -ScriptBlock $createRunasSession -ArgumentList @(
                $Name,
                $RunAsCredential.UserName,
                $RunAsCredential.GetNetworkCredential().Password
            ) -Raw
        } catch {
            Stop-Function -Message "Failure during remote session configuration execution" -ErrorRecord $_ -EnableException $true
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