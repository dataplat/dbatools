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
    # P0-010c cache unification (W1-001): the registry now lives in the process-wide
    # [Dataplat.Dbatools.Connection.ConnectionHost]::ActiveConnections so PS functions and the
    # compiled Connect-DbaInstance cmdlet share one connection state. The static always
    # exists, which also retires the lazy re-creation described above.
    $connections = [Dataplat.Dbatools.Connection.ConnectionHost]::ActiveConnections

    if ($Value.ConnectionContext.NonPooledConnection -or $Value.NonPooledConnection) {
        if (-not $connections["$Key"]) {
            $connections["$Key"] = @( )
        }
        $connections["$Key"].Add($Value)
    } else {
        $connections["$Key"] = @($Value)
    }
}