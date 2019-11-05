function Start-DbaRunspace {
    <#
    .SYNOPSIS
        Starts a managed runspace

    .DESCRIPTION
        Starts a runspace that was registered to dbatools
        Simply registering does not automatically start a given runspace. Only by executing this function will it take effect.

    .PARAMETER Name
        The name of the registered runspace to launch

    .PARAMETER Runspace
        The runspace to launch. Returned by Get-DbaRunspace

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .EXAMPLE
        PS C:\> Start-DbaRunspace -Name 'mymodule.maintenance'

        Starts the runspace registered under the name 'mymodule.maintenance'
    #>
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline)]
        [string[]]
        $Name,

        [Parameter(ValueFromPipeline)]
        [Sqlcollaborative.Dbatools.Runspace.RunspaceContainer[]]
        $Runspace,

        [switch]$EnableException
    )

    process {
        foreach ($item in $Name) {
            # Ignore all output from Get-DbaRunspace - it'll be handled by the second loop
            if ($item -eq "Sqlcollaborative.Dbatools.Runspace.runspacecontainer") { continue }

            if ([Sqlcollaborative.Dbatools.Runspace.RunspaceHost]::Runspaces.ContainsKey($item.ToLowerInvariant())) {
                try {
                    Write-Message -Level Verbose -Message "Starting runspace: $($item.ToLowerInvariant())" -Target $item.ToLowerInvariant()
                    [Sqlcollaborative.Dbatools.Runspace.RunspaceHost]::Runspaces[$item.ToLowerInvariant()].Start()
                } catch {
                    Stop-Function -Message "Failed to start runspace: $($item.ToLowerInvariant())" -EnableException $EnableException -Target $item.ToLowerInvariant() -Continue
                }
            } else {
                Stop-Function -Message "Failed to start runspace: $($item.ToLowerInvariant()) | No runspace registered under this name." -EnableException $EnableException -Category InvalidArgument -Tag "fail", "argument", "runspace", "start" -Target $item.ToLowerInvariant() -Continue
            }
        }

        foreach ($item in $Runspace) {
            try {
                Write-Message -Level Verbose -Message "Starting runspace: $($item.Name.ToLowerInvariant())" -Target $item
                $item.Start()
            } catch {
                Stop-Function -Message "Failed to start runspace: $($item.Name.ToLowerInvariant())" -EnableException $EnableException -Target $item -Continue
            }
        }
    }
}