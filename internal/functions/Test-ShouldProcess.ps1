function Test-ShouldProcess {
    <#
    .SYNOPSIS
        Internal function. To use instead of $PSCmdlet.ShouldProcess($x, "Message") as
        Test-ShouldProcess -Context $PSCmdlet -Target $x -Action "Message"
    #>
    param (
        $Context,
        [string]$Target,
        [string]$Action
    )

    $Context.ShouldProcess($Target, $Action)
}