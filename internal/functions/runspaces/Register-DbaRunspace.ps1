function Register-DbaRunspace {
    <#
    .SYNOPSIS
        Registers a scriptblock to run in the background.

    .DESCRIPTION
        This function registers a scriptblock to run in separate runspace.
        This is different from most runspace solutions, in that it is designed for permanent background tasks that need to be done.
        It guarantees a single copy of the task to run within the powershell process, even when running the same module in many runspaces in parallel.

        Updating:
        If this function is called multiple times, targeting the same name, it will update the scriptblock.
        - If that scriptblock is the same as the previous scriptblock, nothing changes
        - If that scriptblock is different from the previous ones, it will be registered, but will not be executed right away!
          Only after stopping and starting the runspace will it operate under the new scriptblock.

    .PARAMETER ScriptBlock
        The scriptblock to run in a dedicated runspace

    .PARAMETER Name
        The name to register the scriptblock under.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .EXAMPLE
        PS C:\> Register-DbaRunspace -ScriptBlock $scriptBlock -Name 'mymodule.maintenance'

        Registers the script defined in $scriptBlock under the name 'mymodule.maintenance'
        It does not start the runspace yet. If it already exists, it will overwrite the scriptblock without affecting the running script.

    .EXAMPLE
        PS C:\> Register-DbaRunspace -ScriptBlock $scriptBlock -Name 'mymodule.maintenance'
        PS C:\> Start-DbaRunspace -Name 'mymodule.maintenance'

        Registers the script defined in $scriptBlock under the name 'mymodule.maintenance'
        Then it starts the runspace, running the registered $scriptBlock
    #>
    [CmdletBinding(PositionalBinding = $false)]
    param
    (
        [Parameter(Mandatory)]
        [Scriptblock]
        $ScriptBlock,

        [Parameter(Mandatory)]
        [String]
        $Name,

        [switch]$EnableException
    )

    if ([Sqlcollaborative.Dbatools.Runspace.RunspaceHost]::Runspaces.ContainsKey($Name.ToLowerInvariant())) {
        Write-Message -Level Verbose -Message "Updating runspace: $($Name.ToLowerInvariant())" -Target $Name.ToLowerInvariant()
        [Sqlcollaborative.Dbatools.Runspace.RunspaceHost]::Runspaces[$Name.ToLowerInvariant()].SetScript($ScriptBlock)
    } else {
        Write-Message -Level Verbose -Message "Registering runspace: $($Name.ToLowerInvariant())" -Target $Name.ToLowerInvariant()
        [Sqlcollaborative.Dbatools.Runspace.RunspaceHost]::Runspaces[$Name.ToLowerInvariant()] = New-Object Sqlcollaborative.Dbatools.Runspace.RunspaceContainer($Name.ToLowerInvariant(), $ScriptBlock)
    }
}