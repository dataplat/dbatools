function Get-DbatoolsLog {
    <#
    .SYNOPSIS
    Returns log entries for dbatools

    .DESCRIPTION
    Returns log entries for dbatools. Handy when debugging or developing for it. Also used when preparing a support package.

    .PARAMETER Errors
    Instead of log entries, the error entries will be retrieved

    .NOTES
    Author: Fred Weinmann (@FredWeinmann)
    Tags: Debug

    Website: https://dbatools.io
    Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
    License: MIT https://opensource.org/licenses/MIT

    .LINK
    https://dbatools.io/Get-DbatoolsLog

    .EXAMPLE
    Get-DbatoolsLog

    Returns all log entries currently in memory.
    #>
    [CmdletBinding()]
    param
    (
        [switch]
        $Errors
    )

    BEGIN {
        # No Write-Message, since that would clutter the very log you want to retrieve
    }

    PROCESS {
        if ($Errors) { return [Sqlcollaborative.Dbatools.dbaSystem.DebugHost]::GetErrors() }
        else { return [Sqlcollaborative.Dbatools.dbaSystem.DebugHost]::GetLog() }
    }

    END {

    }
}
