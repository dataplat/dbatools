function Join-SomePath {
    <#
    An internal command that does not require the local path to exist

    Boo, this does not work, but keeping it for future ref.
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