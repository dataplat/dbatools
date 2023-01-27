if ($isLinux -or $IsMacOs) {
    # Create a fake unblock-file
    function Unblock-File {
        [CmdletBinding()]
        param(
            [Parameter(ValueFromPipeline)]
            [string[]]$Path
        )
        # do nothing
    }
}