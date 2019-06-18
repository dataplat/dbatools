function Test-Windows {
    <#
        .SYNOPSIS
            Internal tool, used to detect non-Windows platforms

        .DESCRIPTION
            Some things don't work with Windows, this is an easy way to detect

        .EXAMPLE
            if (-not (Test-Windows)) { return }

            The calling function will stop if this function returns true.
    #>
    [CmdletBinding()]
    param (
        [switch]$NoWarn
    )

    if (($PSVersionTable.Keys -contains "Platform") -and $psversiontable.Platform -ne "Win32NT") {
        if (-not $NoWarn) {
            Write-Message -Level Warning -Message "This command is not supported on non-Windows platforms :("
        }
        return $false
    }

    return $true
}