function Join-Path {
    <#
    An internal command that does not require the local path to exist
    #>
    [CmdletBinding()]
    param (
        [string]$Path,
        [string]$ChildPath
    )
    process {
        [IO.Path]::Combine($Path, $ChildPath)
    }
}