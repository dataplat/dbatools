function Add-ConnectionHashValue {
    param(
        [Parameter(Mandatory)]
        $Key,
        [Parameter(Mandatory)]
        $Value
    )
    Write-Message -Level Debug -Message "Adding to connection hash"

    # The cache is created at module import (dbatools.psm1), but under a Pester 5 run the
    # module script scope resolves without it and every integration test dies here with
    # "Cannot index into a null array" before reaching its assertions. Re-create it lazily:
    # worst case the cache starts empty and connections are simply not reused.
    if ($null -eq $script:connectionhash) {
        $script:connectionhash = @{ }
    }

    if ($Value.ConnectionContext.NonPooledConnection -or $Value.NonPooledConnection) {
        if (-not $script:connectionhash["$Key"]) {
            $script:connectionhash["$Key"] = @( )
        }
        $script:connectionhash["$Key"] += @($Value)
    } else {
        $script:connectionhash["$Key"] = @($Value)
    }
}