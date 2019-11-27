function Get-DbatoolsChangeLog {
    <#
    .SYNOPSIS
        Opens the link to our online change log

    .DESCRIPTION
        Opens the link to our online change log. To see the local changelog instead, use the Local parameter.

    .PARAMETER Local
        Return the local change log to the console

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

    .EXAMPLE
        Get-DbatoolsChangeLog -Local

        Returns the content from changelog.md
    #>
    [CmdletBinding()]
    param (
        [switch]$Local,
        [switch]$EnableException
    )

    try {
        if (-not $Local) {
            Start-Process "https://github.com/sqlcollaborative/dbatools/blob/development/changelog.md"
        } else {
            $releasenotes = Get-Content $script:PSModuleRoot\changelog.md -Raw

            if ($Local) {
                ($releasenotes -Split "##Local")[0]
            } else {
                $releasenotes
            }
        }
    } catch {
        Stop-Function -Message "Failure" -ErrorRecord $_
        return
    }
}