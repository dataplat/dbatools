function Get-DbatoolsLog {
    <#
    .SYNOPSIS
    Returns log entries for dbatools

    .DESCRIPTION
    Returns log entries for dbatools. Handy when debugging or developing for it. Also used when preparing a support package.

    .PARAMETER Errors
    Instead of log entries, the error entries will be retrieved

    .PARAMETER Silent
    Replaces user friendly yellow warnings with bloody red exceptions of doom!
    Use this if you want the function to throw terminating errors you want to catch.

    .NOTES
	Original Author: Fred Weinmann (@FredWeinmann)
	Tags: Debug

	Website: https://dbatools.io
	Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
	License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

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
        $Errors,

        [switch]
        $Silent
    )

    BEGIN {
        Write-Message -Level InternalComment -Message "Starting"
        Write-Message -Level Verbose -Message "Bound parameters: $($PSBoundParameters.Keys -join ", ")"
    }

    PROCESS {
        if ($Errors) { return [Sqlcollective.Dbatools.dbaSystem.DebugHost]::GetErrors() }
        else { return [Sqlcollective.Dbatools.dbaSystem.DebugHost]::GetLog() }
    }

    END {
        Write-Message -Level InternalComment -Message "Ending"
    }
}
