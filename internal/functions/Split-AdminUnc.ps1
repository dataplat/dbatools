function Split-AdminUnc {
    <#
    .SYNOPSIS
    Internal function. Splits a path to a server name and local path.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Filepath
    )

    if (!$Filepath) { return }

    if ($Filepath -match '^[A-Z]:\\') {
        [PSCustomObject]@{
            ServerName = $null
            FilePath   = $Filepath
        }
    }

    if ($Filepath -match '^\\\\(.*?)\\([A-Z])\$\\(.*)$') {
        [PSCustomObject]@{
            ServerName = $matches[1]
            FilePath   = $matches[2] + ':\' + $matches[3]
        }
    }
}