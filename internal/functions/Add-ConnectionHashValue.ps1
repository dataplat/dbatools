function Add-ConnectionHashValue {
    param(
        [Parameter(Mandatory)]
        $Key,
        [Parameter(Mandatory)]
        $Value
    )
    Write-Message -Level Debug -Message "Adding to connection hash"
    if (-not $script:connectionhash[$Key]) {
        $script:connectionhash[$Key] = @( )
    }
    $script:connectionhash[$Key] += $Value
}