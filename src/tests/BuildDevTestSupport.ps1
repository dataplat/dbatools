<#
.SYNOPSIS
    Shared scaffolding for test-build-dev-skipruntime.ps1 - leg reporting, sandboxed invocation, and
    sandbox construction.

.DESCRIPTION
    Split out of the test itself only to keep both files under the repo's 400-line limit
    (.claude/hooks/stop-file-length.sh). It holds no assertions: every leg stays in the test, so a
    reader still finds the whole argument in one place. Dot-source it - it defines functions and
    returns nothing on its own.

.OUTPUTS
    None. Defines Write-Leg, Invoke-BuildDev and New-BuildDevSandbox in the caller's scope.

.NOTES
    Author: the dbatools team + Claude
#>

function Write-Leg {
    param(
        [Parameter(Mandatory)]
        [bool]$Ok,
        [Parameter(Mandatory)]
        [string]$Message
    )
    if ($Ok) {
        Write-Host "ok   $Message"
        $script:pass++
    } else {
        Write-Host "FAIL $Message"
        $script:fail++
    }
}

# Run the sandboxed script and return exit code plus BOTH streams merged. Both matter: the guard
# messages go to stdout, while binding failures and terminating errors go to stderr, and a
# stdout-only read would let legs pass against a script that never had the parameter at all.
function Invoke-BuildDev {
    param(
        [Parameter(Mandatory)]
        [string]$Script,
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]$Switches,
        [Parameter(Mandatory)]
        [string]$WorkDir
    )
    $outPath = Join-Path -Path $WorkDir -ChildPath "run.out"
    $errPath = Join-Path -Path $WorkDir -ChildPath "run.err"
    $splatRun = @{
        FilePath               = "pwsh"
        ArgumentList           = @("-NoProfile", "-File", $Script) + $Switches
        Wait                   = $true
        PassThru               = $true
        NoNewWindow            = $true
        RedirectStandardOutput = $outPath
        RedirectStandardError  = $errPath
    }
    $proc = Start-Process @splatRun
    $text = (Get-Content -Path $outPath -Raw -ErrorAction SilentlyContinue) +
        (Get-Content -Path $errPath -Raw -ErrorAction SilentlyContinue)
    Remove-Item -Path $outPath, $errPath -ErrorAction SilentlyContinue
    [PSCustomObject]@{
        ExitCode = $proc.ExitCode
        Output   = [string]$text
    }
}

# A compiled stand-in for a process this session cannot open. PowerShell swallows a failing property
# getter and hands back $null - verified on pwsh 7 and 5.1, even under $ErrorActionPreference =
# "Stop" - so this reproduces an inaccessible real process exactly: the sweep sees $null, not an
# exception. Compiled rather than Add-Member because a ScriptProperty that throws does not reproduce
# it. The test injects instances of this through a local Get-Process, which outranks the cmdlet.
function Initialize-FakeHolderType {
    if ("FakeHolderProcess" -as [type]) {
        return
    }
    Add-Type -TypeDefinition @"
public class FakeHolderProcess {
    public int Id { get; set; }
    public string ProcessName { get; set; }
    public object[] Modules { get; set; }
    public System.DateTime StartTime {
        get { throw new System.ComponentModel.Win32Exception(5, "Access is denied"); }
    }
}
"@
}

# Build the disposable tree the legs run against, and hand back every path they assert on. Prepends a
# fake dotnet to $env:PATH as a side effect - the caller restores it, and removes RunDir in a finally.
function New-BuildDevSandbox {
    param(
        [Parameter(Mandatory)]
        [string]$ScriptSource
    )
    # Unique per run - this box is shared by many windows, and a fixed name lets concurrent runs
    # overwrite and delete each other's files.
    $RunDir = Join-Path ([System.IO.Path]::GetTempPath()) ("build-dev-test-" + [System.IO.Path]::GetRandomFileName())
    $null = New-Item -ItemType Directory -Path $RunDir -Force
    # The sandbox only has to satisfy what the script inspects before it would build: a script
    # directory whose parent holds artifacts/dbatools.library/<edition>/lib/dbatools.dll. The DLL is
    # a dummy - the preflight opens the file, it never loads it as an assembly.
    $sandboxBuild = Join-Path -Path $RunDir -ChildPath "build"
    $null = New-Item -ItemType Directory -Path $sandboxBuild -Force
    $stagedCore = Join-Path -Path $RunDir -ChildPath "artifacts/dbatools.library/core/lib/dbatools.dll"
    $stagedDesktop = Join-Path -Path $RunDir -ChildPath "artifacts/dbatools.library/desktop/lib/dbatools.dll"
    foreach ($staged in @($stagedCore, $stagedDesktop)) {
        $null = New-Item -ItemType Directory -Path (Split-Path -Path $staged) -Force
        Set-Content -Path $staged -Value "not a real assembly" -Encoding Ascii
    }
    $sandboxScript = Join-Path -Path $sandboxBuild -ChildPath "build-dev.ps1"
    Copy-Item -Path $ScriptSource -Destination $sandboxScript -Force
    Copy-Item -Path (Join-Path (Split-Path $ScriptSource) "BuildDevSourceIdentity.ps1") -Destination $sandboxBuild -Force

    # A fake dotnet on PATH plus a minimal project tree. Without them the script cannot get past
    # Push-Location, so a -SkipRuntime leg could only assert "no lock error" - which passes just as
    # readily when the run dies one line later for an unrelated reason. With them the run completes
    # and the leg asserts what actually matters: satellites built, runtime not.
    $fakeBin = Join-Path -Path $RunDir -ChildPath "fakebin"
    $null = New-Item -ItemType Directory -Path $fakeBin -Force
    Set-Content -Path (Join-Path -Path $fakeBin -ChildPath "dotnet.cmd") -Value "@echo off`r`necho   fake dotnet %*`r`nexit /b 0" -Encoding Ascii
    if (-not $IsWindows) {
        $shim = Join-Path -Path $fakeBin -ChildPath "dotnet"
        Set-Content -Path $shim -Value "#!/bin/sh`necho `"  fake dotnet `$@`"`nexit 0" -Encoding Ascii
        chmod +x $shim
    }
    $env:PATH = $fakeBin + [System.IO.Path]::PathSeparator + $env:PATH

    $sandboxProject = Join-Path -Path $RunDir -ChildPath "project"
    foreach ($proj in @("dbatools", "dbatools.fake")) {
        $projDir = Join-Path -Path $sandboxProject -ChildPath $proj
        $null = New-Item -ItemType Directory -Path $projDir -Force
        Set-Content -Path (Join-Path -Path $projDir -ChildPath "$proj.csproj") -Value "<Project />" -Encoding Ascii
    }
    $sourceFile = Join-Path -Path $sandboxProject -ChildPath "dbatools/source.cs"
    Set-Content -Path $sourceFile -Value "// committed sandbox source" -Encoding Ascii
    # Ignored build output under the runtime project, exactly as a real dotnet build leaves it. The
    # source identity must still be recordable with it present, or no box that has ever built can
    # stage the runtime.
    $objDir = Join-Path -Path $sandboxProject -ChildPath "dbatools/obj"
    $null = New-Item -ItemType Directory -Path $objDir -Force
    Set-Content -Path (Join-Path -Path $objDir -ChildPath "project.assets.json") -Value "{}" -Encoding Ascii
    Set-Content -Path (Join-Path -Path $RunDir -ChildPath ".gitignore") -Value "obj/" -Encoding Ascii
    & git -C $RunDir init --quiet
    & git -C $RunDir config user.email "build-dev-test@example.invalid"
    & git -C $RunDir config user.name "build-dev test"
    & git -C $RunDir add .gitignore project/dbatools
    & git -C $RunDir commit --quiet -m "sandbox source"
    if ($LASTEXITCODE -ne 0) { throw "Could not initialize disposable Git repository." }
    $tree = (& git -C $RunDir rev-parse "HEAD:project/dbatools").Trim()
    foreach ($staged in @($stagedCore, $stagedDesktop)) {
        @{ Version = 1; Tree = $tree } | ConvertTo-Json -Compress | Set-Content -LiteralPath "$staged.source-identity.json" -Encoding UTF8
    }
    # The script verifies each build's output exists before staging it, so a fake compiler that
    # writes nothing needs these seeded in the exact locations the real projects emit to.
    $builtRuntime = Join-Path -Path $RunDir -ChildPath "artifacts/lib/Release/net8.0/dbatools.dll"
    $builtSatellite = Join-Path -Path $sandboxProject -ChildPath "dbatools.fake/bin/Release/net8.0/dbatools.fake.dll"
    foreach ($built in @($builtRuntime, $builtSatellite)) {
        $null = New-Item -ItemType Directory -Path (Split-Path -Path $built) -Force
        Set-Content -Path $built -Value "built by the fake dotnet" -Encoding Ascii
    }

    [PSCustomObject]@{
        RunDir          = $RunDir
        Build           = $sandboxBuild
        Script          = $sandboxScript
        StagedCore      = $stagedCore
        BuiltRuntime    = $builtRuntime
        BuiltSatellite  = $builtSatellite
        StagedSatellite = Join-Path -Path $RunDir -ChildPath "artifacts/modules/dbatools.fake/core/dbatools.fake.dll"
        SourceFile      = $sourceFile
    }
}
