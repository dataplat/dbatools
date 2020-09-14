function Test-ShouldProcess {
    param (
        $Context,
        [string]$Target,
        [string]$Action
    )

    $Context.ShouldProcess($Target, $Action)
}