function Invoke-Command2 {
    <#
        .SYNOPSIS
            Wrapper function that calls Invoke-Command and gracefully handles credentials.

        .DESCRIPTION
            Wrapper function that calls Invoke-Command and gracefully handles credentials.

        .PARAMETER ComputerName
            Default: $env:COMPUTERNAME
            The computer to invoke the scriptblock on.

        .PARAMETER Credential
            The credentials to use.
            Can accept $null on older PowerShell versions, since it expects type object, not PSCredential

        .PARAMETER ScriptBlock
            The code to run on the targeted system

        .PARAMETER InputObject
            Object that could be used in the ScriptBlock as $Input.
            NOTE:
            The object will be de-serialized once passed through the remote pipeline.
            Some objects (like hashtables) do not support de-serialization.

        .PARAMETER Authentication
            Choose an authentication to use for the connection

        .PARAMETER ConfigurationName
            Name of the remote PSSessionConfiguration to use.
            Should be registered already using Register-PSSessionConfiguration or internal Register-RemoteSessionConfiguration.

        .PARAMETER UseSSL
            Enables SSL

        .PARAMETER ArgumentList
            Any arguments to pass to the scriptblock being run

        .PARAMETER Raw
            Passes through the raw return data, rather than prettifying stuff.

        .PARAMETER RequiredPSVersion
            Verifies that remote Powershell version is meeting specified requirements.

        .EXAMPLE
            PS C:\> Invoke-Command2 -ComputerName sql2014 -Credential $Credential -ScriptBlock { dir }

            Executes the scriptblock '{ dir }' on the computer sql2014 using the credentials stored in $Credential.
            If $Credential is null, no harm done.
    #>
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUsePSCredentialType", "")]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingPlainTextForPassword", "")]
    param (
        [DbaInstanceParameter]$ComputerName = $env:COMPUTERNAME,
        [object]$Credential,
        [scriptblock]$ScriptBlock,
        [object[]]$ArgumentList,
        [parameter(ValueFromPipeline)]
        [object[]]$InputObject,
        [ValidateSet('Default', 'Basic', 'Negotiate', 'NegotiateWithImplicitCredential', 'Credssp', 'Digest', 'Kerberos')]
        [string]$Authentication = 'Default',
        [string]$ConfigurationName,
        [switch]$UseSSL = (Get-DbatoolsConfigValue -FullName 'PSRemoting.PsSession.UseSSL' -Fallback $false),
        [switch]$Raw,
        [version]$RequiredPSVersion
    )
    <# Note: Credential stays as an object type for legacy reasons. #>

    $InvokeCommandSplat = @{ }
    if ($ArgumentList) {
        $InvokeCommandSplat["ArgumentList"] = $ArgumentList
    }
    if ($InputObject) {
        $InvokeCommandSplat["InputObject"] = $InputObject
    }
    if (-not $ComputerName.IsLocalHost) {
        $runspaceId = [System.Management.Automation.Runspaces.Runspace]::DefaultRunspace.InstanceId
        # sessions with different Authentication should have different session names
        if ($ConfigurationName) {
            $sessionName = "dbatools_$($Authentication)_$($ConfigurationName)_$runspaceId"
        } else {
            $sessionName = "dbatools_$($Authentication)_$runspaceId"
        }

        # Retrieve a session from the session cache, if available (it's unique per runspace)
        $currentSession = [Sqlcollaborative.Dbatools.Connection.ConnectionHost]::PSSessionGet($runspaceId, $ComputerName.ComputerName) | Where-Object { $_.State -Match "Opened|Disconnected" -and $_.Name -eq $sessionName }
        if (-not $currentSession) {
            Write-Message -Level Debug "Creating new $Authentication session [$sessionName] for $($ComputerName.ComputerName)"
            $psSessionSplat = @{
                ComputerName   = $ComputerName.ComputerName
                Authentication = $Authentication
                Name           = $sessionName
                ErrorAction    = 'Stop'
                UseSSL         = (Get-DbatoolsConfigValue -FullName 'PSRemoting.PsSession.UseSSL' -Fallback $false)
            }
            if (Test-Windows -NoWarn) {
                $psSessionOptionsSplat = @{
                    IdleTimeout      = (New-TimeSpan -Minutes 10).TotalMilliSeconds
                    IncludePortInSPN = (Get-DbatoolsConfigValue -FullName 'PSRemoting.PsSessionOption.IncludePortInSPN' -Fallback $false)
                }
                $sessionOption = New-PSSessionOption @psSessionOptionsSplat
                $psSessionSplat += @{ SessionOption = $sessionOption }
            }
            if ($Credential) {
                $psSessionSplat += @{ Credential = $Credential }
            }
            if ($ConfigurationName) {
                $psSessionSplat += @{ ConfigurationName = $ConfigurationName }
            }
            $currentSession = New-PSSession @psSessionSplat
            $InvokeCommandSplat["Session"] = $currentSession
        } else {
            Write-Message -Level Debug "Found an existing session $sessionName, reusing it"
            if ($currentSession.State -eq "Disconnected") {
                $null = $currentSession | Connect-PSSession -ErrorAction Stop
            }
            $InvokeCommandSplat["Session"] = $currentSession

            # Refresh the session registration if registered, to reset countdown until purge
            [Sqlcollaborative.Dbatools.Connection.ConnectionHost]::PSSessionSet($runspaceId, $ComputerName.ComputerName, $currentSession)
        }
    }
    if ($RequiredPSVersion) {
        $remoteVersion = Invoke-Command @InvokeCommandSplat -ScriptBlock { $PSVersionTable }
        if ($remoteVersion.PSVersion -and $remoteVersion.PSVersion -lt $RequiredPSVersion) {
            throw "Remote PS version $($remoteVersion.PSVersion) is less than defined requirement ($RequiredPSVersion)"
        }
    }

    $InvokeCommandSplat.ScriptBlock = $ScriptBlock
    if ($Raw) {
        Invoke-Command @InvokeCommandSplat
    } else {
        Invoke-Command @InvokeCommandSplat | Select-Object -Property * -ExcludeProperty PSComputerName, RunspaceId, PSShowComputerName
    }

    if (-not $ComputerName.IsLocalhost) {
        # Tell the system to clean up if the session expires
        [Sqlcollaborative.Dbatools.Connection.ConnectionHost]::PSSessionSet($runspaceId, $ComputerName.ComputerName, $currentSession)

        if (-not (Get-DbatoolsConfigValue -FullName 'PSRemoting.Sessions.Enable' -Fallback $true)) {
            $currentSession | Remove-PSSession
        }
    }
}