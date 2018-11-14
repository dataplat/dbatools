function Get-DbaPathSep {
    <#
    Gets the instance path separator, if exists, or return the default one
    #>
    [CmdletBinding()]
    param (
        [object]$Server
    )

    $pathSep = $Server.PathSeparator
    if ($pathSep.Length -eq 0) {
        $pathSep = '\'
    }
    return $pathSep
}