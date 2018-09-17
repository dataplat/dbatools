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
        [switch]$Raw
    )
    <# Note: Credential stays as an object type for legacy reasons. #>

    $InvokeCommandSplat = @{
        ScriptBlock = $ScriptBlock
    }
    if ($ArgumentList) {
        $InvokeCommandSplat["ArgumentList"] = $ArgumentList
    }
    if (-not $ComputerName.IsLocalHost) {
        $runspaceId = [System.Management.Automation.Runspaces.Runspace]::DefaultRunspace.InstanceId
        $sessionName = "dbatools_$runspaceId"

        # Retrieve a session from the session cache, if available (it's unique per runspace)
        if (-not ($currentSession = [Sqlcollaborative.Dbatools.Connection.ConnectionHost]::PSSessionGet($runspaceId, $ComputerName.ComputerName) | Where-Object State -Match "Opened|Disconnected")) {
            $timeout = New-PSSessionOption -IdleTimeout (New-TimeSpan -Minutes 10).TotalMilliSeconds
            if ($Credential) {
                $InvokeCommandSplat["Session"] = (New-PSSession -ComputerName $ComputerName.ComputerName -Name $sessionName -SessionOption $timeout -Credential $Credential -ErrorAction Stop)
            }
            else {
                $InvokeCommandSplat["Session"] = (New-PSSession -ComputerName $ComputerName.ComputerName -Name $sessionName -SessionOption $timeout -ErrorAction Stop)
            }
            $currentSession = $InvokeCommandSplat["Session"]
        }
        else {
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
    }
    else {
        Invoke-Command @InvokeCommandSplat | Select-Object -Property * -ExcludeProperty PSComputerName, RunspaceId, PSShowComputerName
    }

    if (-not $ComputerName.IsLocalhost) {
        # Tell the system to clean up if the session expires
        [Sqlcollaborative.Dbatools.Connection.ConnectionHost]::PSSessionSet($runspaceId, $ComputerName.ComputerName, $currentSession)

        if (-not (Get-DbaConfigValue -FullName 'PSRemoting.Sessions.Enable' -Fallback $true)) {
            $currentSession | Remove-PSSession
        }
    }
}