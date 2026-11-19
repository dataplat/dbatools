function Get-BuildDevSourceIdentity {
    param(
        [Parameter(Mandatory)]
        [string]$Root
    )

    try {
        $tree = (& git -C $Root rev-parse "HEAD:project/dbatools" 2>$null).Trim()
        if ($LASTEXITCODE -ne 0 -or $tree -notmatch '^[0-9a-f]{40}$') { return $null }
        # Not --ignored: the runtime build itself leaves project/dbatools/obj/ behind, and counting
        # that as a source change made the identity unrecordable on every box that had ever built.
        $changes = @(& git -C $Root status --porcelain -- project/dbatools 2>$null)
        if ($LASTEXITCODE -ne 0 -or $changes.Count -ne 0) { return $null }
        return [PSCustomObject]@{ Version = 1; Tree = $tree }
    } catch {
        return $null
    }
}

function Write-BuildDevSourceIdentity {
    param(
        [Parameter(Mandatory)] [string]$StagedDll,
        [Parameter(Mandatory)] $Identity
    )
    $Identity | ConvertTo-Json -Compress | Set-Content -LiteralPath "$StagedDll.source-identity.json" -Encoding UTF8
}

function Test-BuildDevSourceIdentity {
    param(
        [Parameter(Mandatory)] [string]$StagedDll,
        $CurrentIdentity
    )
    if ($null -eq $CurrentIdentity) { return $false }
    try {
        $marker = Get-Content -LiteralPath "$StagedDll.source-identity.json" -Raw | ConvertFrom-Json -ErrorAction Stop
        return $marker.Version -eq 1 -and $marker.Tree -eq $CurrentIdentity.Tree
    } catch {
        return $false
    }
}
