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
    param (
        [DbaInstanceParameter]$ComputerName = $env:COMPUTERNAME,
        [object]$Credential,
        [scriptblock]$ScriptBlock,
        [object[]]$ArgumentList,
        [switch]$Raw
    )

    $InvokeCommandSplat = @{
        ScriptBlock = $ScriptBlock
    }
    if ($ArgumentList) { $InvokeCommandSplat["ArgumentList"] = $ArgumentList }
    if (-not $ComputerName.IsLocalhost) { $InvokeCommandSplat["ComputerName"] = $ComputerName.ComputerName }
    if ($Credential) { $InvokeCommandSplat["Credential"] = $Credential }

    if ($Raw) { Invoke-Command @InvokeCommandSplat }
    else { Invoke-Command @InvokeCommandSplat | Select-Object -Property * -ExcludeProperty PSComputerName, RunspaceId, PSShowComputerName }
}