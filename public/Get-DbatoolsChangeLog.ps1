function Get-DbatoolsChangeLog {
    <#
    .SYNOPSIS
        Opens the link to our online change log

    .DESCRIPTION
        Opens the link to our online change log.

    .PARAMETER Local
        Once upon a time, there was a local changelog. This is not available anymore so a proper warning will be raised

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Module, ChangeLog
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbatoolsChangeLog

    .EXAMPLE
        Get-DbatoolsChangeLog

        Opens a browser to our online changelog

    #>
    [CmdletBinding()]
    param (
        [switch]$Local,
        [switch]$EnableException
    )

    try {
        if (-not $Local) {
            Start-Process "https://github.com/dataplat/dbatools/releases"
        } else {
            Write-Message -Level "Warning" -Message "Sorry, changelog is only available online"
        }
    } catch {
        Stop-Function -Message "Failure" -ErrorRecord $_
        return
    }
}