function Get-DbatoolsChangeLog {
    <#
    .SYNOPSIS
        Opens the dbatools release changelog in your default browser

    .DESCRIPTION
        Launches your default browser to view the dbatools release changelog on GitHub. This provides access to version history, new features, bug fixes, and breaking changes for the dbatools PowerShell module. Useful for staying current with module updates or troubleshooting issues that may be related to recent changes.

    .PARAMETER Local
        Attempts to display a local changelog file instead of opening the online version. This functionality has been deprecated and will display a warning message directing users to the online changelog.

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

    .OUTPUTS
        None

        This command does not return any objects. It opens the dbatools release changelog in your default browser or displays a message for unsupported options.

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