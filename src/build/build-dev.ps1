param(
    [switch]$IncludeDesktop,
    [switch]$SkipSatellites,
    [switch]$SkipRuntime
)
# Fast per-iteration dev build for the libmigration campaign (migration PHASE-0 row P0-004).
#
# WHY THIS EXISTS: build/build.ps1 -CoreOnly is NOT a fast path - by the time it returns it has
# already run dotnet clean, then dotnet publish --self-contained for net472 AND net8.0, then a
# release build of every satellite. That is minutes per iteration. This script instead REUSES the
# heavy dependency tree (SMO, SqlClient, DacFx, Bogus, native runtimes) already staged by a prior
# full build under artifacts/library, and recompiles only the two thin things a port
# iteration actually changes: the shared runtime dbatools.dll and the satellite cmdlet assemblies.
# An incremental dotnet build (no clean, no publish, no self-contained) rebuilds only what changed.
#
# DEFAULT is core-only (net8.0) for speed. Pass -IncludeDesktop to also refresh the net472 drop,
# which the acceptance check and any Windows PowerShell 5.1 gate need. Pass -SkipSatellites to
# refresh only the runtime dll (fastest; use only when you did not touch a satellite).
#
# -SkipRuntime is the inverse: refresh only the satellites, leaving the staged base dbatools.dll
# alone. Use it when you touched a satellite and NOT dbatools/ - the common case for a port
# iteration. It exists because the base drop cannot be re-staged at all while any live session has
# it loaded (see the holder check below), and that blocked satellite-only work that never needed
# the base refreshed (#849).
#
# It does NOT rely on anything downstream to catch skew, and an earlier version of this comment was
# wrong to say it did: every satellite csproj carries <ProjectReference Include="..\dbatools\
# dbatools.csproj" />, so building a satellite recompiles the runtime into artifacts/lib/Release/
# whether or not -SkipRuntime was passed - it is only the STAGING that is skipped. The gate's
# base-library parity guard hashes the two STAGED copies (guest vs host,
# migration/tools/Test-GateBaseLibraryPrecondition.ps1), and staging is exactly the step that did
# not run, so both sides read the same stale file and the guard passes on skewed bits (#854). The
# post-build content check at the bottom of this script is therefore the only thing that sees it.
#
# ACCEPTANCE (P0-004): after `build-dev.ps1 -IncludeDesktop`, Use-LocalDbatoolsLibrary -Validate is
# green (both editions import warning-clean) because the dependency tree is reused untouched and
# only dbatools.dll is refreshed.
#
# PREREQUISITE: a full drop must exist under artifacts/library (run build/build.ps1 once
# to seed it). This script deliberately does NOT rebuild the dependency tree - that is the whole
# source of its speed - so it fails fast and loud if the base drop is missing rather than silently
# emitting an unloadable runtime with no dependencies.

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$scriptroot = $PSScriptRoot
if (-not $scriptroot) {
    $scriptroot = Split-Path -Path $MyInvocation.MyCommand.Path
}
$root = Split-Path -Path $scriptroot
. (Join-Path -Path $scriptroot -ChildPath "BuildDevSourceIdentity.ps1")
$projectRoot = Join-Path -Path $root -ChildPath "project"
$artifactsDir = Join-Path -Path $root -ChildPath "artifacts"
$moduleDir = Join-Path -Path $artifactsDir -ChildPath "library"

$stopwatch = New-Object System.Diagnostics.Stopwatch
$stopwatch.Start()

# Editions to refresh. Core (net8.0) always; desktop (net472) only when asked.
$editions = @(
    [PSCustomObject]@{ Name = "core"; Framework = "net8.0" }
)
if ($IncludeDesktop) {
    $editions += [PSCustomObject]@{ Name = "desktop"; Framework = "net472" }
}

if ($SkipRuntime -and $SkipSatellites) {
    Write-Host "ERROR: -SkipRuntime and -SkipSatellites together leave nothing to build." -ForegroundColor Red
    exit 1
}

# Fail fast if the dependency base is not staged - see PREREQUISITE above. This applies to both
# paths: a satellite-only run still loads against the staged dependency tree.
foreach ($edition in $editions) {
    $baseDll = Join-Path -Path $moduleDir -ChildPath "$($edition.Name)/lib/dbatools.dll"
    if (-not (Test-Path -LiteralPath $baseDll)) {
        Write-Host "ERROR: base drop missing $baseDll - run build/build.ps1 once to seed the dependency tree before using build-dev.ps1." -ForegroundColor Red
        exit 1
    }
}

function Test-StagedDllWritable {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )
    try {
        $stream = [System.IO.File]::Open($Path, "Open", "ReadWrite", "None")
        $stream.Close()
        return $true
    } catch {
        return $false
    }
}

function Get-StagedDllHolder {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )
    foreach ($proc in (Get-Process -ErrorAction SilentlyContinue)) {
        # Do NOT skip $PID. Running this script from a shell that already imported the core drop out
        # of artifacts is the COMMON way to lock it, and skipping self reported zero holders, which
        # the caller then printed as "likely held under another user account" - the one diagnosis
        # that sends the reader looking at the wrong machine.
        # Both .Modules and .StartTime are unreadable for a process this session cannot open, or one
        # that exits mid-enumeration - both happen here, and one died mid-probe during the #849
        # investigation. PowerShell does NOT throw on a failing property getter: verified on pwsh 7
        # and 5.1, it returns $null silently even under $ErrorActionPreference = "Stop". So $null is
        # the case that has to be handled and the try blocks are only insurance. An unknown start
        # time is still a useful holder, so never drop the row over it.
        try {
            $loaded = @($proc.Modules | Where-Object { $_.FileName -eq $Path })
            if ($loaded.Count -eq 0) {
                continue
            }
            $started = "unknown"
            try {
                if ($proc.StartTime) {
                    $started = $proc.StartTime
                }
            } catch {
                # keep "unknown"
            }
        } catch {
            # Not attributable, and not a reason to call the file free - Test-StagedDllWritable
            # already decided that.
            continue
        }
        [PSCustomObject]@{
            Id      = $proc.Id
            Name    = $proc.ProcessName
            Started = $started
            IsSelf  = ($proc.Id -eq $PID)
        }
    }
}

# A .NET assembly is locked for the whole lifetime of any process that loaded it, and long-running
# campaign windows (regate side runs, full-suite runs, the editor's PowerShell host) import the
# core drop straight out of artifacts. So base staging fails whenever one of them is alive. That
# surfaced as a bare Copy-Item "used by another process" AFTER a multi-minute build and was read as
# an edit-lease conflict (#849) - the lease neither causes this nor can fix it. Check up front and
# name the holders, so the next reader gets an answer instead of filing an outage.
if (-not $SkipRuntime) {
    foreach ($edition in $editions) {
        $targetDll = Join-Path -Path $moduleDir -ChildPath "$($edition.Name)/lib/dbatools.dll"
        if (Test-StagedDllWritable -Path $targetDll) {
            continue
        }
        Write-Host "ERROR: cannot stage $($edition.Name)/lib/dbatools.dll - it is loaded by a live process:" -ForegroundColor Red
        $holders = @(Get-StagedDllHolder -Path $targetDll)
        if ($holders.Count -eq 0) {
            Write-Host "  no holder could be attributed - it is likely held under another user account." -ForegroundColor Red
        }
        foreach ($holder in $holders) {
            $selfNote = ""
            if ($holder.IsSelf) {
                $selfNote = "  <-- THIS shell: it imported the core drop out of artifacts; start a fresh shell to build"
            }
            Write-Host "  $($holder.Name) pid=$($holder.Id) started=$($holder.Started)$selfNote" -ForegroundColor Red
        }
        Write-Host "  This is NOT the library edit lease. Do not kill these - a peer gate or regate run may be live." -ForegroundColor Yellow
        Write-Host "  If you did not change dbatools/ source, re-run with -SkipRuntime to refresh satellites only." -ForegroundColor Yellow
        exit 1
    }
}

$pendingStage = @()
Push-Location -Path $projectRoot
try {
    # Refresh the shared runtime dbatools.dll per requested edition (incremental Release build).
    foreach ($edition in $editions) {
        if ($SkipRuntime) {
            Write-Host "Skipping runtime dbatools.dll ($($edition.Name)) - -SkipRuntime; the staged base is unchanged." -ForegroundColor Yellow
            continue
        }
        Write-Host "Building runtime dbatools.dll ($($edition.Framework), Release)..." -ForegroundColor Cyan
        dotnet build dbatools/dbatools.csproj --configuration Release --framework $edition.Framework --nologo | Out-String -OutVariable runtimeBuild
        if ($LASTEXITCODE -ne 0) {
            Write-Host "ERROR: runtime build ($($edition.Framework)) failed with exit code $LASTEXITCODE" -ForegroundColor Red
            exit $LASTEXITCODE
        }
        # dbatools.csproj redirects Release output to artifacts/lib/Release/<tfm>/ (custom OutputPath),
        # NOT the default bin/ - so read the freshly built runtime dll from there.
        $builtDll = Join-Path -Path $artifactsDir -ChildPath "lib/Release/$($edition.Framework)/dbatools.dll"
        if (-not (Test-Path -LiteralPath $builtDll)) {
            Write-Host "ERROR: expected build output not found: $builtDll" -ForegroundColor Red
            exit 1
        }
        $targetDll = Join-Path -Path $moduleDir -ChildPath "$($edition.Name)/lib/dbatools.dll"
        Copy-Item -Path $builtDll -Destination $targetDll -Force
        $identity = Get-BuildDevSourceIdentity -Root $root
        if ($null -eq $identity) {
            Write-Host "ERROR: cannot record source identity for $($edition.Name) runtime staging." -ForegroundColor Red
            exit 1
        }
        Write-BuildDevSourceIdentity -StagedDll $targetDll -Identity $identity
        Write-Host "Staged runtime: $($edition.Name)/lib/dbatools.dll" -ForegroundColor Green
    }

    # Refresh the satellite cmdlet assemblies. These ship inside each satellite package, staged to
    # artifacts/modules/dbatools.<module>/{core,desktop}/ exactly as build/build.ps1 does, so
    # Ship-Satellite.ps1 pushes the freshly built cmdlet dll on the next gate. Branch 30's
    # build-dev staged dbatools.dll ONLY, which left a runtime with no commands - this closes that.
    #
    # BUILD here, STAGE after the skew check below. Copying on the way through would leave satellites
    # built against a new runtime sitting beside the old staged base every time that check rejects,
    # and exit 1 does not undo it: Ship-Satellite.ps1 reads the staged tree, not this script's exit
    # code, so the mismatch ships on the next gate with the one thing that noticed it long gone.
    if (-not $SkipSatellites) {
        $satelliteProjects = Get-ChildItem -Path $projectRoot -Directory -Filter "dbatools.*" | Where-Object {
            $_.Name -ne "dbatools" -and $_.Name -ne "dbatools.Tests" -and (Test-Path (Join-Path $_.FullName "$($_.Name).csproj"))
        }
        foreach ($satellite in $satelliteProjects) {
            $satelliteName = $satellite.Name
            $moduleStage = Join-Path -Path $artifactsDir -ChildPath "modules/$satelliteName"
            foreach ($edition in $editions) {
                Write-Host "Building satellite $satelliteName ($($edition.Framework), Release)..." -ForegroundColor Cyan
                dotnet build "$satelliteName/$satelliteName.csproj" --configuration Release --framework $edition.Framework --nologo | Out-String -OutVariable satelliteBuild
                if ($LASTEXITCODE -ne 0) {
                    Write-Host "ERROR: satellite build ($satelliteName, $($edition.Framework)) failed with exit code $LASTEXITCODE" -ForegroundColor Red
                    exit $LASTEXITCODE
                }
                $builtSat = Join-Path -Path $projectRoot -ChildPath "$satelliteName/bin/Release/$($edition.Framework)/$satelliteName.dll"
                if (-not (Test-Path -LiteralPath $builtSat)) {
                    Write-Host "ERROR: expected satellite output not found: $builtSat" -ForegroundColor Red
                    exit 1
                }
                $pendingStage += [PSCustomObject]@{
                    Satellite   = $satelliteName
                    Source      = $builtSat
                    Destination = Join-Path -Path $moduleStage -ChildPath $edition.Name
                }
            }
            # dll-Help.xml (MAML) is generated only from the net8.0 build (CmdletHelp.props) but
            # is target-framework independent, so the one file is staged beside the assembly in
            # every edition. Mirrors the same step in build/build.ps1.
            $helpFile = Join-Path -Path $projectRoot -ChildPath "$satelliteName/bin/Release/net8.0/$satelliteName.dll-Help.xml"
            if (Test-Path -LiteralPath $helpFile) {
                foreach ($edition in $editions) {
                    $pendingStage += [PSCustomObject]@{
                        Satellite   = $satelliteName
                        Source      = $helpFile
                        Destination = Join-Path -Path $moduleStage -ChildPath $edition.Name
                    }
                }
            }
        }
    }
} finally {
    Pop-Location
}

# ABI-skew check for -SkipRuntime, per the note at the top. The satellites just compiled against
# whatever the ProjectReference produced, and the staged base is a byte copy of that same file from
# some earlier run - so CONTENT equality is the question, and a timestamp is the wrong instrument in
# both directions: a rebuild that reproduces identical bytes reds on a newer mtime, and a staged copy
# that came from a different build passes on an older one.
#
# This does not fire on the case -SkipRuntime exists for, and not because the compiler is
# deterministic: when dbatools/ source is unchanged, dotnet's up-to-date check does not rewrite the
# runtime AT ALL, so the file still hashes to the copy that was staged from it.
if ($SkipRuntime -and -not $SkipSatellites) {
    $skewed = @()
    foreach ($edition in $editions) {
        $builtDll = Join-Path -Path $artifactsDir -ChildPath "lib/Release/$($edition.Framework)/dbatools.dll"
        $stagedDll = Join-Path -Path $moduleDir -ChildPath "$($edition.Name)/lib/dbatools.dll"
        if (-not (Test-Path -LiteralPath $builtDll)) {
            # Every satellite references dbatools.csproj, so this file must exist after a satellite
            # build. Missing means the comparison could not be made - never treat that as agreement.
            Write-Host "ERROR: cannot check base skew for $($edition.Name) - expected $builtDll after the satellite build, and it is not there." -ForegroundColor Red
            exit 1
        }
        # The staged base is normally held by a live process - that is the whole reason -SkipRuntime
        # exists - but a loaded .NET assembly is mapped FileShare.Read, so hashing it works. A holder
        # that denies reads too leaves the comparison unmade, and an unmade comparison is not a pass.
        try {
            $builtHash = (Get-FileHash -LiteralPath $builtDll -Algorithm SHA256).Hash
            $stagedHash = (Get-FileHash -LiteralPath $stagedDll -Algorithm SHA256).Hash
        } catch {
            Write-Host "ERROR: cannot verify base skew for $($edition.Name) - $stagedDll could not be read: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "  Something is holding it without sharing reads. Skew is UNKNOWN, not absent - find the holder before trusting this build." -ForegroundColor Yellow
            exit 1
        }
        if ($builtHash -ne $stagedHash) {
            $skewed += [PSCustomObject]@{
                Edition = $edition.Name
                Built   = $builtHash
                Staged  = $stagedHash
            }
        }
    }
    if ($skewed.Count -gt 0) {
        $identity = Get-BuildDevSourceIdentity -Root $root
        $verified = @($skewed | Where-Object { Test-BuildDevSourceIdentity -StagedDll (Join-Path -Path $moduleDir -ChildPath "$($_.Edition)/lib/dbatools.dll") -CurrentIdentity $identity })
        if ($verified.Count -eq $skewed.Count) {
            Write-Host "-SkipRuntime accepts byte-different runtime output: staged bases match the current clean source identity." -ForegroundColor Green
        } else {
        Write-Host "ERROR: -SkipRuntime staged satellites built against a runtime that DIFFERS from the staged base dbatools.dll:" -ForegroundColor Red
        foreach ($skew in $skewed) {
            Write-Host "  $($skew.Edition): built $($skew.Built.Substring(0, 16))..., staged $($skew.Staged.Substring(0, 16))..." -ForegroundColor Red
        }
        Write-Host "  You changed dbatools/ source, so -SkipRuntime is not safe here - the satellites and the base disagree." -ForegroundColor Yellow
        Write-Host "  The gate will NOT catch this: its parity guard hashes the two staged copies, and staging is what was skipped (#854)." -ForegroundColor Yellow
        Write-Host "  Free the holder named above and re-run without -SkipRuntime." -ForegroundColor Yellow
        Write-Host "  Nothing was staged - the satellites built above are still only in project/*/bin/." -ForegroundColor Yellow
        exit 1
        }
    }
}

$stagedNames = @()
foreach ($item in $pendingStage) {
    $null = New-Item -ItemType Directory -Path $item.Destination -Force
    Copy-Item -Path $item.Source -Destination $item.Destination -Force
    if ($stagedNames -notcontains $item.Satellite) {
        $stagedNames += $item.Satellite
    }
}
foreach ($name in $stagedNames) {
    Write-Host "Staged satellite: $name" -ForegroundColor Green
}

$stopwatch.Stop()
Write-Host "Dev build complete in $([math]::Round($stopwatch.Elapsed.TotalSeconds, 1))s: $moduleDir" -ForegroundColor Green
Write-Host "Validate with: Use-LocalDbatoolsLibrary.ps1 -Validate" -ForegroundColor Green
