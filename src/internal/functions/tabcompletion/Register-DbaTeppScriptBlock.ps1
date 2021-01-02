function Register-DbaTeppScriptblock {
    <#
        .SYNOPSIS
            Registers a scriptblock under name, to later be available for TabExpansion.

        .DESCRIPTION
            Registers a scriptblock under name, to later be available for TabExpansion.

        .PARAMETER ScriptBlock
            The scriptblock to register.

        .PARAMETER Name
            The name under which the scriptblock should be registered.

        .EXAMPLE
            Register-DbaTeppScriptblock -ScriptBlock $scriptBlock -Name MyFirstTeppScriptBlock

            Stores the scriptblock stored in $scriptBlock under the name "MyFirstTeppScriptBlock"
       #>
    [CmdletBinding()]
    param (
        [System.Management.Automation.ScriptBlock]
        $ScriptBlock,

        [string]
        $Name
    )

    $scp = New-Object Sqlcollaborative.Dbatools.TabExpansion.ScriptContainer
    $scp.Name = $Name.ToLowerInvariant()
    $scp.ScriptBlock = $ScriptBlock
    $scp.LastDuration = New-TimeSpan -Seconds -1

    [Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::Scripts[$Name.ToLowerInvariant()] = $scp
}