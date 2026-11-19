function Copy-LockedArtifact {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Source,
        [Parameter(Mandatory)]
        [string]$Destination,
        [switch]$IgnoreMissingSource
    )

    if ($IgnoreMissingSource -and -not (Test-Path -LiteralPath $Source -PathType Leaf)) {
        return
    }

    $destinationDirectory = Split-Path -Parent $Destination
    $null = New-Item -ItemType Directory -Path $destinationDirectory -Force
    if (-not (Test-Path -LiteralPath $Destination)) {
        Copy-Item -LiteralPath $Source -Destination $Destination -Force -ErrorAction Stop
        return
    }

    try {
        Copy-Item -LiteralPath $Source -Destination $Destination -Force -ErrorAction Stop
        return
    } catch {
        # A mapped assembly cannot be replaced in place, but Windows permits moving its name aside.
    }

    $backup = "$Destination.locked-$([guid]::NewGuid().ToString("N"))"
    Rename-Item -LiteralPath $Destination -NewName (Split-Path -Leaf $backup) -ErrorAction Stop
    try {
        Copy-Item -LiteralPath $Source -Destination $Destination -Force -ErrorAction Stop
        if ((Get-FileHash -LiteralPath $Source -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash) {
            throw "Copied artifact hash does not match source: $Destination"
        }
    } catch {
        Remove-Item -LiteralPath $Destination -Force -ErrorAction SilentlyContinue
        Rename-Item -LiteralPath $backup -NewName (Split-Path -Leaf $Destination) -ErrorAction SilentlyContinue
        throw
    }

    # A mapped predecessor can remain open after its original path is replaced. Leave this
    # uniquely named backup for the next holder-free clean rather than turning a good stage red.
}

function Copy-LockedArtifactTree {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Source,
        [Parameter(Mandatory)]
        [string]$Destination
    )

    Get-ChildItem -LiteralPath $Source -File -Recurse | ForEach-Object {
        $relativePath = $_.FullName.Substring($Source.TrimEnd([char[]]@("\", "/")).Length).TrimStart([char[]]@("\", "/"))
        Copy-LockedArtifact -Source $_.FullName -Destination (Join-Path $Destination $relativePath)
    }
}
