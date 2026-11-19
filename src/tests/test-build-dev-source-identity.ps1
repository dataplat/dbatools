<#
.SYNOPSIS
    Reproduces #1447: byte-skew alone cannot distinguish stale staging from unchanged source.
#>
[CmdletBinding()]
param(
    [string]$ScriptPath = (Join-Path $PSScriptRoot "../build/build-dev.ps1")
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "BuildDevTestSupport.ps1")

$resolved = (Resolve-Path $ScriptPath).Path
$originalPath = $env:PATH
$sandbox = New-BuildDevSandbox -ScriptSource $resolved
try {
    # The source tree in this sandbox is deliberately untouched.  Only the output differs, which
    # models an interrupted full build whose copy to the staged base was blocked by a loaded DLL.
    Set-Content -LiteralPath $sandbox.BuiltRuntime -Value "same-source newer compiler output" -Encoding Ascii -NoNewline
    $result = Invoke-BuildDev -Script $sandbox.Script -Switches @("-SkipRuntime") -WorkDir $sandbox.RunDir
    $accepted = $result.ExitCode -eq 0 -and $result.Output -match "current clean source identity"
    Write-Host "SOURCE_TREE_CHANGED=False"
    Write-Host "BUILT_AND_STAGED_BYTES_DIFFER=True"
    Write-Host "SKIPRUNTIME_ACCEPTED=$accepted"
    if (-not $accepted) { throw "Expected matching source identity to allow byte-different output." }

    Set-Content -LiteralPath $sandbox.SourceFile -Value "// dirty source" -Encoding Ascii
    $dirty = Invoke-BuildDev -Script $sandbox.Script -Switches @("-SkipRuntime") -WorkDir $sandbox.RunDir
    if ($dirty.ExitCode -ne 1 -or $dirty.Output -notmatch "DIFFERS from the staged base") { throw "Dirty source must retain the byte-mismatch refusal. exit=$($dirty.ExitCode) output=$($dirty.Output)" }
    Set-Content -LiteralPath $sandbox.SourceFile -Value "// committed sandbox source" -Encoding Ascii

    Remove-Item -LiteralPath "$($sandbox.StagedCore).source-identity.json" -Force
    $missing = Invoke-BuildDev -Script $sandbox.Script -Switches @("-SkipRuntime") -WorkDir $sandbox.RunDir
    if ($missing.ExitCode -ne 1 -or $missing.Output -notmatch "DIFFERS from the staged base") { throw "Missing marker must retain the byte-mismatch refusal." }
    @{ Version = 1; Tree = ('0' * 40) } | ConvertTo-Json -Compress | Set-Content -LiteralPath "$($sandbox.StagedCore).source-identity.json" -Encoding UTF8
    $wrong = Invoke-BuildDev -Script $sandbox.Script -Switches @("-SkipRuntime") -WorkDir $sandbox.RunDir
    if ($wrong.ExitCode -ne 1 -or $wrong.Output -notmatch "DIFFERS from the staged base") { throw "Wrong marker identity must retain the byte-mismatch refusal." }
    Write-Host "SOURCE_IDENTITY_CONTROLS=DIRTY_MISSING_AND_WRONG_REFUSED"
} finally {
    $env:PATH = $originalPath
    Remove-Item -LiteralPath $sandbox.RunDir -Recurse -Force -ErrorAction SilentlyContinue
}
