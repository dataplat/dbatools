#ValidationTags#Messaging,FlowControl,Pipeline,CodeStyle#
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

        .PARAMETER Authentication
            Choose an authentication to use for the connection

        .PARAMETER ConfigurationName
            Name of the remote PSSessionConfiguration to use. Should be registered already using Register-RemoteSessionConfiguration

        .PARAMETER ArgumentList
            Any arguments to pass to the scriptblock being run

        .PARAMETER Raw
            Passes through the raw return data, rather than prettifying stuff.

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
        [switch]$Raw
    )
    <# Note: Credential stays as an object type for legacy reasons. #>

    $InvokeCommandSplat = @{
        ScriptBlock = $ScriptBlock
    }
    if ($ArgumentList) {
        $InvokeCommandSplat["ArgumentList"] = $ArgumentList
    }
    if ($InputObject) {
        $InvokeCommandSplat["InputObject"] = $InputObject
    }
    if (-not $ComputerName.IsLocalHost) {
        $runspaceId = [System.Management.Automation.Runspaces.Runspace]::DefaultRunspace.InstanceId
        $sessionName = "dbatools_$($Authentication)_$runspaceId"

        # Retrieve a session from the session cache, if available (it's unique per runspace)
        $currentSession = [Sqlcollaborative.Dbatools.Connection.ConnectionHost]::PSSessionGet($runspaceId, $ComputerName.ComputerName) | Where-Object { $_.State -Match "Opened|Disconnected" -and $_.Name -eq $sessionName }
        # Checking if current configuration name is different - session should be recreated in this case
        if ($currentSession -and ($ConfigurationName -or $currentSession.ConfigurationName -notin '', 'Microsoft.PowerShell') -and $currentSession.ConfigurationName -ne $ConfigurationName) {
            Write-Message -Level Debug "Removing session $sessionName with Configuration [$($currentSession.ConfigurationName)] - need to redefine configuration name to [$ConfigurationName]"
            $currentSession | Remove-PSSession
            $currentSession = $null
        }
        if (-not $currentSession) {
            Write-Message -Level Debug "Creating new $Authentication session [$sessionName] for $($ComputerName.ComputerName)"
            $timeout = New-PSSessionOption -IdleTimeout (New-TimeSpan -Minutes 10).TotalMilliSeconds
            $psSessionSplat = @{
                ComputerName   = $ComputerName.ComputerName
                Authentication = $Authentication
                Name           = $sessionName
                SessionOption  = $timeout
                ErrorAction    = 'Stop'
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