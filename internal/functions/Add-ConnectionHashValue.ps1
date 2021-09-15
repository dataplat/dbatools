function Add-ConnectionHashValue {
    param(
        [Parameter(Mandatory)]
        $Key,
        [Parameter(Mandatory)]
        $Value
    )
    Write-Message -Level Debug -Message "Adding to connection hash"

    if ($Value.ConnectionContext.NonPooledConnection -or $Value.NonPooledConnection) {
        if (-not $script:connectionhash[$Key]) {
            $script:connectionhash[$Key] = @( )
        }
        $script:connectionhash[$Key] += $Value
    } else {
        $script:connectionhash[$Key] = $Value
    }
}