function Initialize-CredSSP {
    <#
    .SYNOPSIS
        Configure local and remote computers to use Credssp protocol

    .DESCRIPTION
        Enables both local and remote machine to participate in a Credssp session.
        Local computer will be told to trust the Delegate (remote) computer.
        Remote computer will be configured to act as a server and accept client connections from local computer.

        This function can be disabled by setting the value of configuration item "commands.initialize-credssp.bypass" to $true.
        Configuration of CredSSP can and will be done by this command only from an elevated PowerShell session.

    .PARAMETER ComputerName
        Remote computer name

    .PARAMETER Credential
        PSCredential object used for authentication

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .EXAMPLE
        PS C:\> Initialize-CredSSP MyRemoteComputer
        # Configure CredSSP protocol to connect to remote computer MyRemoteComputer
    .EXAMPLE
        PS C:\> $cred = Get-Credential
        PS C:\> Initialize-CredSSP -ComputerName PC2 -Credential $cred
        # Configure CredSSP protocol to connect to remote computer with custom credentials
#>

    Param (
        [Parameter(Mandatory, Position = 1)]
        [string]$ComputerName,
        [pscredential]$Credential,
        [bool]$EnableException
    )

    # Check to see if this function is bypassed
    if (Get-DbatoolsConfigValue -FullName 'commands.initialize-credssp.bypass') {
        Write-Message -Level Verbose -Message "CredSSP initialization bypass (commands.initialize-credssp.bypass) is set to $true"
        return
    }

    # Configure local machine
    # Start local WinRM service
    if ((Get-Service WinRM).Status -ne 'Running') {
        $null = Get-Service WinRM -ErrorAction Stop | Start-Service -ErrorAction Stop
        Start-Sleep -Seconds 1
    }

    # The command Get-WSManCredSSP can only run in an elevated PowerShell session, so we test that to be able to fail with a suitable message
    $isElevated = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isElevated) {
        Stop-Function -Message "Failed to configure CredSSP because the PowerShell session is not elevated"
        return
    }

    # Get current config
    try {
        $sspList = Get-WSManCredSSP -ErrorAction Stop
    } catch {
        Stop-Function -Message "Failed to get a list of CredSSP hosts" -ErrorRecord $_
        return
    }

    # Enable delegation to a remote server if not declared already
    if ($sspList -and $sspList[0] -notmatch "wsman\/$([regex]::Escape($ComputerName))[\,$]") {
        Write-Message -Level Verbose -Message "Configuring local host to use CredSSP"
        try {
            # Enable client SSP on local machine
            $null = Enable-WSManCredSSP -Role Client -DelegateComputer $ComputerName -Force -ErrorAction Stop
        } catch {
            Stop-Function -Message "Failed to configure local CredSSP as a client" -ErrorRecord $_
        }
    }

    # Configure remote machine
    Write-Message -Level Verbose -Message "Configuring remote host to use CredSSP"
    try {
        Invoke-Command2 -ComputerName $ComputerName -Credential $Credential -Raw -RequiredPSVersion 3.0 -ScriptBlock {
            $sspList = Get-WSManCredSSP -ErrorAction Stop
            if ($sspList[1] -ne 'This computer is configured to receive credentials from a remote client computer.') {
                $null = Enable-WSManCredSSP -Role Server -Force -ErrorAction Stop
            }
        }
    } catch {
        Stop-Function -Message "Failed to configure remote CredSSP on $ComputerName as a server" -ErrorRecord $_
    }
}