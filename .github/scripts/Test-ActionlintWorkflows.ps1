[CmdletBinding()]
param(
    [string]$WorkflowPath = ".github/workflows",
    [string]$Version = "1.7.12",
    [string]$ToolPath
)

$ErrorActionPreference = "Stop"

# Checksums come from the actionlint release page:
# https://github.com/rhysd/actionlint/releases/download/v<Version>/actionlint_<Version>_checksums.txt
# Update both $Version and this table together when bumping actionlint.
$knownChecksums = @{
    "1.7.12" = @{
        "darwin_amd64"  = "5b44c3bc2255115c9b69e30efc0fecdf498fdb63c5d58e17084fd5f16324c644"
        "darwin_arm64"  = "aba9ced2dee8d27fecca3dc7feb1a7f9a52caefa1eb46f3271ea66b6e0e6953f"
        "linux_386"     = "72a44b32c2d032700e6d0c23ca2f540b67519ec68db098ddfcfa96059e61f723"
        "linux_amd64"   = "8aca8db96f1b94770f1b0d72b6dddcb1ebb8123cb3712530b08cc387b349a3d8"
        "linux_arm64"   = "325e971b6ba9bfa504672e29be93c24981eeb1c07576d730e9f7c8805afff0c6"
        "linux_armv6"   = "ae4a0a5227578e66f5d00ee02788d5c64fdae1fa6484ab88ceaeee9359c28fa4"
        "windows_386"   = "cdc8643b2c8dc890c76ad16095da97e75f86572805cc3573cc13f31ea0f19127"
        "windows_amd64" = "6e7241b51e6817ea6a047693d8e6fed13b31819c9a0dd6c5a726e1592d22f6e9"
        "windows_arm64" = "cadcf7ea4efe3a68728893813643cebe1185e5b1d4be5b96245f65c9a4d5ea41"
    }
}

$resolvedWorkflowPath = Resolve-Path -LiteralPath $WorkflowPath
$workflowFiles = Get-ChildItem -LiteralPath $resolvedWorkflowPath -Recurse -File |
    Where-Object { $PSItem.Extension -in ".yml", ".yaml" }

if (-not $workflowFiles) {
    throw "No GitHub Actions workflow files found under $WorkflowPath"
}

function Get-ActionlintPlatform {
    # $IsWindows only exists on PowerShell 6+. Anything older is Windows PowerShell,
    # which only ever runs on Windows.
    if ($PSVersionTable.PSVersion.Major -lt 6) {
        $osName = "windows"
    } elseif ($IsWindows) {
        $osName = "windows"
    } elseif ($IsMacOS) {
        $osName = "darwin"
    } else {
        $osName = "linux"
    }

    $architecture = "$([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture)".ToLowerInvariant()

    switch ($architecture) {
        "x64" { $archName = "amd64" }
        "arm64" { $archName = "arm64" }
        "x86" { $archName = "386" }
        "arm" { $archName = "armv6" }
        default { throw "Unsupported processor architecture for actionlint: $architecture" }
    }

    [pscustomobject]@{
        Os        = $osName
        Arch      = $archName
        Moniker   = "${osName}_${archName}"
        Extension = if ($osName -eq "windows") { "zip" } else { "tar.gz" }
        Binary    = if ($osName -eq "windows") { "actionlint.exe" } else { "actionlint" }
    }
}

function Install-Actionlint {
    param(
        [Parameter(Mandatory)]
        [string]$Version
    )

    $platform = Get-ActionlintPlatform
    $cacheRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "dbatools-actionlint/$Version/$($platform.Moniker)"
    $binaryPath = Join-Path -Path $cacheRoot -ChildPath $platform.Binary

    if (Test-Path -LiteralPath $binaryPath) {
        Write-Verbose "Reusing cached actionlint at $binaryPath"
        return $binaryPath
    }

    $versionChecksums = $knownChecksums[$Version]
    if ($versionChecksums) {
        $expectedChecksum = $versionChecksums[$platform.Moniker]
    }

    if (-not $expectedChecksum) {
        throw "No known checksum for actionlint $Version on $($platform.Moniker). Add it to the `$knownChecksums table in this script, copying the value from https://github.com/rhysd/actionlint/releases/download/v$Version/actionlint_${Version}_checksums.txt"
    }

    $archiveName = "actionlint_${Version}_$($platform.Moniker).$($platform.Extension)"
    $downloadUri = "https://github.com/rhysd/actionlint/releases/download/v$Version/$archiveName"

    $null = New-Item -Path $cacheRoot -ItemType Directory -Force
    $archivePath = Join-Path -Path $cacheRoot -ChildPath $archiveName

    Write-Host "Downloading actionlint $Version for $($platform.Moniker)"

    $splatDownload = @{
        Uri             = $downloadUri
        OutFile         = $archivePath
        UseBasicParsing = $true
        ErrorAction     = "Stop"
    }
    Invoke-WebRequest @splatDownload

    $actualChecksum = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash
    if ($actualChecksum -ne $expectedChecksum) {
        Remove-Item -LiteralPath $archivePath -Force -ErrorAction SilentlyContinue
        throw "Checksum mismatch for $archiveName. Expected $expectedChecksum but got $actualChecksum."
    }

    if ($platform.Extension -eq "zip") {
        Expand-Archive -LiteralPath $archivePath -DestinationPath $cacheRoot -Force
    } else {
        & tar -xzf $archivePath -C $cacheRoot
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to extract $archivePath"
        }
    }

    Remove-Item -LiteralPath $archivePath -Force -ErrorAction SilentlyContinue

    if (-not (Test-Path -LiteralPath $binaryPath)) {
        throw "actionlint binary was not found at $binaryPath after extraction."
    }

    if ($platform.Os -ne "windows") {
        & chmod +x $binaryPath
    }

    $binaryPath
}

if ($ToolPath) {
    if (-not (Test-Path -LiteralPath $ToolPath)) {
        throw "actionlint was not found at $ToolPath"
    }
    $actionlint = (Resolve-Path -LiteralPath $ToolPath).Path
} else {
    $actionlint = Install-Actionlint -Version $Version
}

# Wrap in @() so a single workflow file stays an array. Splatting a bare string
# passes it one character at a time, which makes actionlint try to read "." as a file.
$relativeFiles = @(
    foreach ($file in $workflowFiles) {
        Resolve-Path -LiteralPath $file.FullName -Relative
    }
)

# Rules actionlint gets wrong for this repository. Each entry needs a reason so we
# can retire it once the linter (or the workflow) catches up. These are regular
# expressions matched against the message text, so "." stands in for the literal
# double quotes actionlint puts around the offending key.
$ignoredPatterns = @(
    # GitHub added "queue" to the concurrency block in May 2026 so a group can hold
    # up to 100 pending runs. ci-azure.yml relies on it for AppVeyor-style FIFO
    # lanes. actionlint 1.7.12 predates the key. Drop this once actionlint knows it.
    "unexpected key .queue. for .concurrency. section",
    # integration-tests.yml intentionally parks the windows-tests job behind
    # "if: false" rather than deleting it, so the constant condition is deliberate.
    "constant expression .false. in condition"
)

$ignoreArguments = @(
    foreach ($pattern in $ignoredPatterns) {
        "-ignore"
        $pattern
    }
)

Write-Host "Running actionlint against $($workflowFiles.Count) workflow file(s)"

# -color is disabled so the output stays readable in CI logs and when redirected.
$output = & $actionlint -no-color -oneline @ignoreArguments @relativeFiles 2>&1
$actionlintExitCode = $LASTEXITCODE

if ($output) {
    $output | ForEach-Object { Write-Host $PSItem }
}

if ($actionlintExitCode -ne 0) {
    throw "actionlint reported problems in the GitHub Actions workflows."
}

Write-Host "All GitHub Actions workflows passed actionlint."
