function Join-AdminUnc {
    <#
    .SYNOPSIS
    Internal function. Parses a path to make it an admin UNC.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$servername,
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$filepath

    )

    if (!$filepath) { return }
    if ($filepath.StartsWith("\\")) { return $filepath }

    $servername = $servername.Split("\")[0]

    if ($filepath.length -gt 0 -and $filepath -ne [System.DbNull]::Value) {
        $newpath = Join-Path "\\$servername\" $filepath.replace(':', '$')
        return $newpath
    } else { return }
}