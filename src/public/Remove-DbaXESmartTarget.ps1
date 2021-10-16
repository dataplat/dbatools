function Remove-DbaXESmartTarget {
    <#
    .SYNOPSIS
        Removes XESmartTarget PowerShell jobs.

    .DESCRIPTION
        Removes XESmartTarget PowerShell jobs.

    .PARAMETER InputObject
        Specifies one or more XESmartTarget job objects as output by Get-DbaXESmartTarget.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: ExtendedEvent, XE, XEvent
        Author: Chrissy LeMaire (@cl) | SmartTarget by Gianluca Sartori (@spaghettidba)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        https://github.com/spaghettidba/XESmartTarget/wiki

    .LINK
        https://dbatools.io/Remove-DbaXESmartTarget

    .EXAMPLE
        PS C:\> Get-DbaXESmartTarget | Remove-DbaXESmartTarget

        Removes all XESmartTarget jobs.

    .EXAMPLE
        PS C:\> Get-DbaXESmartTarget | Where-Object Id -eq 2 | Remove-DbaXESmartTarget

        Removes a specific XESmartTarget job.

    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [object[]]$InputObject,
        [switch]$EnableException
    )
    process {
        if ($Pscmdlet.ShouldProcess("localhost", "Removing job $id")) {
            try {
                $id = $InputObject.Id
                Write-Message -Level Output -Message "Removing job $id, this may take a couple minutes."
                Get-Job -ID $InputObject.Id | Remove-Job -Force
                Write-Message -Level Output -Message "Successfully removed $id."
            } catch {
                Stop-Function -Message "Failure" -ErrorRecord $_
            }
        }
    }
}