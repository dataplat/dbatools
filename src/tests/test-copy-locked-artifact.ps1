$ErrorActionPreference = "Stop"
. "$PSScriptRoot/../build/Copy-LockedArtifact.ps1"

$root = Join-Path ([System.IO.Path]::GetTempPath()) ("dbatools-locked-artifact-" + [guid]::NewGuid().ToString("N"))
$source = [System.Text.Json.JsonDocument].Assembly.Location
$oldSource = [System.Management.Automation.PSObject].Assembly.Location
$destination = Join-Path $root "artifacts/dbatools.library/core/lib/locked.dll"
$lock = $null

try {
    $null = New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force
    Copy-Item -LiteralPath $oldSource -Destination $destination -Force
    $oldHash = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash
    $newHash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
    if ($oldHash -eq $newHash) { throw "fixture sources must differ" }

    $lock = [System.IO.File]::Open($destination, "Open", "Read", ([System.IO.FileShare]::Read -bor [System.IO.FileShare]::Delete))
    $directFailed = $false
    try { Copy-Item -LiteralPath $source -Destination $destination -Force -ErrorAction Stop } catch { $directFailed = $true }
    if (-not $directFailed) { throw "direct copy unexpectedly succeeded" }
    Copy-LockedArtifact -Source $source -Destination $destination
    if ((Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash -ne $newHash) { throw "locked replacement did not write new bytes" }
    if (@(Get-ChildItem -LiteralPath (Split-Path -Parent $destination) -Filter "locked.dll.locked-*" -File).Count -ne 1) { throw "locked replacement did not retain backup" }
    $lock.Dispose(); $lock = $null

    $unlocked = Join-Path $root "artifacts/dbatools.library/core/lib/unlocked.dll"
    Copy-LockedArtifact -Source $source -Destination $unlocked
    if ((Get-FileHash -LiteralPath $unlocked -Algorithm SHA256).Hash -ne $newHash) { throw "unlocked copy failed" }
    if (@(Get-ChildItem -LiteralPath (Split-Path -Parent $unlocked) -Filter "unlocked.dll.locked-*" -File).Count -ne 0) { throw "unlocked copy retained backup" }

    $optionalDestination = Join-Path $root "artifacts/dbatools.library/optional/LICENSE"
    Copy-LockedArtifact -Source (Join-Path $root "missing-LICENSE") -Destination $optionalDestination -IgnoreMissingSource
    if (Test-Path -LiteralPath $optionalDestination) { throw "missing optional source unexpectedly created a destination" }

    $rollbackDestination = Join-Path $root "artifacts/dbatools.library/core/lib/rollback.dll"
    $rollbackSource = Join-Path $root "locked-source.dll"
    Copy-Item -LiteralPath $oldSource -Destination $rollbackDestination -Force
    Copy-Item -LiteralPath $source -Destination $rollbackSource -Force
    $rollbackLock = [System.IO.File]::Open($rollbackDestination, "Open", "Read", ([System.IO.FileShare]::Read -bor [System.IO.FileShare]::Delete))
    $sourceLock = [System.IO.File]::Open($rollbackSource, "Open", "Read", [System.IO.FileShare]::None)
    try {
        $rollbackFailed = $false
        try { Copy-LockedArtifact -Source $rollbackSource -Destination $rollbackDestination } catch { $rollbackFailed = $true }
        if (-not $rollbackFailed) { throw "rollback fixture unexpectedly copied a source locked against reads" }
        if ((Get-FileHash -LiteralPath $rollbackDestination -Algorithm SHA256).Hash -ne $oldHash) { throw "rollback did not restore predecessor bytes" }
        if (@(Get-ChildItem -LiteralPath (Split-Path -Parent $rollbackDestination) -Filter "rollback.dll.locked-*" -File).Count -ne 0) { throw "rollback left a backup behind" }
    } finally {
        $sourceLock.Dispose()
        $rollbackLock.Dispose()
    }

    "LOCKED_REPLACEMENT=True"
    "UNLOCKED_COPY=True"
    "MISSING_OPTIONAL_SOURCE_IGNORED=True"
    "ROLLBACK_RESTORED=True"
} finally {
    if ($lock) { $lock.Dispose() }
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
