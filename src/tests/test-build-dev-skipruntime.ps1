<#
.SYNOPSIS
    Covers build-dev.ps1's -SkipRuntime switch, its mutual exclusion with -SkipSatellites, and the
    DLL-lock preflight added in 7b3fe811 (#849).

.DESCRIPTION
    The preflight exists because the staged base dbatools.dll cannot be replaced while any live
    process has it loaded, and long-lived pwsh 7 windows import the core drop straight out of
    artifacts. That failure used to surface as a bare Copy-Item error AFTER a multi-minute build and
    was misread as a library-edit-lease conflict, which it never was.

    Everything runs against a disposable sandbox built by BuildDevTestSupport.ps1 (scaffolding only,
    no assertions). That is what makes the important leg possible - the real script invoked with the
    staged DLL genuinely locked, asserted to abort before any dotnet invocation - without touching
    the shared artifacts drop.

    Every lock assertion checks BOTH directions. A check that can only answer "locked" is as broken
    as one that can only answer "free".

    -IncludeBuild adds the end-to-end leg against the REAL tree. It compiles every satellite and
    writes into artifacts: TAKE THE LIBRARY EDIT LEASE FIRST, or it races a gate and both results
    become meaningless.

.EXAMPLE
    PS C:\> pwsh -NoProfile -File tests/test-build-dev-skipruntime.ps1

    Runs the hermetic legs. Exit 0 = green.

.EXAMPLE
    PS C:\> pwsh -NoProfile -File tests/test-build-dev-skipruntime.ps1 -IncludeBuild

    Adds the end-to-end -SkipRuntime build. Hold the library edit lease when you use this.

.OUTPUTS
    None. Writes leg results to the host; exit code 0 = all legs green.

.NOTES
    Author: the dbatools team + Claude
#>
[CmdletBinding()]
param(
    [string]$ScriptPath = (Join-Path $PSScriptRoot "../build/build-dev.ps1"),
    [switch]$IncludeBuild
)

$ErrorActionPreference = "Stop"
$pass = 0
$fail = 0

. (Join-Path -Path $PSScriptRoot -ChildPath "BuildDevTestSupport.ps1")

$resolved = (Resolve-Path -Path $ScriptPath).Path
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($resolved, [ref]$null, [ref]$errors)
if ($errors) {
    Write-Leg -Ok $false -Message "parse: $($errors[0].Message)"
    exit 1
}
$scriptText = Get-Content -Path $resolved -Raw

$originalPath = $env:PATH
$sandbox = New-BuildDevSandbox -ScriptSource $resolved
$runDir = $sandbox.RunDir

try {
    $sandboxScript = $sandbox.Script
    $stagedCore = $sandbox.StagedCore
    $builtRuntime = $sandbox.BuiltRuntime
    $stagedSatellite = $sandbox.StagedSatellite

    # 1. Mutual exclusion. This path exits before any dotnet invocation, so it stays hermetic.
    #    The exit code alone proves nothing - the guard, a binding failure against a script with no
    #    -SkipRuntime parameter, and the base-drop precondition ALL exit 1, and an earlier control
    #    passed this leg on the wrong one of those. The message is the assertion.
    $splatConflict = @{
        Script   = $sandboxScript
        Switches = @("-SkipRuntime", "-SkipSatellites")
        WorkDir  = $runDir
    }
    $conflict = Invoke-BuildDev @splatConflict
    Write-Leg -Ok ($conflict.ExitCode -eq 1 -and $conflict.Output -match "nothing to build") -Message "-SkipRuntime with -SkipSatellites exits 1 naming the conflict (got $($conflict.ExitCode))"
    Write-Leg -Ok ($conflict.Output -notmatch "base drop missing|A parameter cannot be found|ParameterBindingException") -Message "it failed on the guard, not on a precondition or a binding error"
    Write-Leg -Ok ($conflict.Output -notmatch "Building runtime|Building satellite") -Message "the conflict is caught BEFORE any dotnet build runs"

    # 2. THE BEHAVIOURAL LEG. The real script, a genuinely locked staged DLL, and the assertion that
    #    matters: it aborts before dotnet. Structural checks cannot establish this.
    $lock = [System.IO.File]::Open($stagedCore, "Open", "ReadWrite", "None")
    try {
        $splatLocked = @{
            Script   = $sandboxScript
            Switches = @()
            WorkDir  = $runDir
        }
        $locked = Invoke-BuildDev @splatLocked
        Write-Leg -Ok ($locked.ExitCode -eq 1) -Message "a locked staged DLL aborts the run (exit $($locked.ExitCode))"
        Write-Leg -Ok ($locked.Output -match "cannot stage") -Message "the abort names the lock rather than failing obscurely"
        Write-Leg -Ok ($locked.Output -notmatch "Building runtime|Building satellite") -Message "it aborts BEFORE dotnet build - the whole point of the preflight"
        Write-Leg -Ok ($locked.Output -match "NOT the library edit lease") -Message "the message rules out the lease, which is what #849 was misdiagnosed as"
    } finally {
        $lock.Close()
    }

    # 3. The other direction, at the same level: unlocked, the preflight must NOT block - and the run
    #    must reach BOTH build paths. That second half is what gives the -SkipRuntime leg below any
    #    meaning: in a sandbox that could never build a runtime, "no runtime build ran" proves
    #    nothing at all.
    $splatFree = @{
        Script   = $sandboxScript
        Switches = @()
        WorkDir  = $runDir
    }
    $free = Invoke-BuildDev @splatFree
    Write-Leg -Ok ($free.Output -notmatch "cannot stage") -Message "with the DLL released the preflight lets the run proceed - not a blanket refusal"
    Write-Leg -Ok ($free.ExitCode -eq 0) -Message "a full default run completes in the sandbox (exit $($free.ExitCode))"
    Write-Leg -Ok ($free.Output -match "Building runtime dbatools.dll") -Message "the default run DOES build the runtime - the positive control for -SkipRuntime"
    Write-Leg -Ok ($free.Output -match "Staged satellite: dbatools.fake") -Message "the default run also builds and stages satellites"

    # 4. The lock helpers themselves, lifted from the shipped script - never re-implemented here, so
    #    deleting or weakening them there makes this stop finding them.
    foreach ($name in @("Test-StagedDllWritable", "Get-StagedDllHolder")) {
        $found = $ast.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name
            }.GetNewClosure(), $true)
        if (-not $found) {
            Write-Leg -Ok $false -Message "$name is gone from build-dev.ps1 - the preflight cannot work"
            Write-Host ""
            Write-Host "$pass passed, $fail failed"
            exit 1
        }
        . ([scriptblock]::Create($found[0].Extent.Text))
    }

    $probe = Join-Path -Path $runDir -ChildPath "lock-probe.bin"
    Set-Content -Path $probe -Value "probe" -Encoding Ascii
    Write-Leg -Ok (Test-StagedDllWritable -Path $probe) -Message "an unlocked file reads as writable - the check can say YES"
    $held = [System.IO.File]::Open($probe, "Open", "ReadWrite", "None")
    try {
        Write-Leg -Ok (-not (Test-StagedDllWritable -Path $probe)) -Message "a locked file reads as NOT writable - the check can say NO"

        # A plain file lock is deliberately NOT attributable: Get-StagedDllHolder enumerates loaded
        # ASSEMBLIES, so it finds the case the preflight is really about (a process that imported
        # the drop) and correctly finds nothing here. That asymmetry is why the shipped code prints
        # a distinct "no holder could be attributed" line instead of claiming the file is free.
        $holders = @(Get-StagedDllHolder -Path $probe)
        Write-Leg -Ok ($holders.Count -eq 0) -Message "a non-assembly lock yields no attributable holder, and does not throw"
    } finally {
        $held.Close()
    }
    Write-Leg -Ok (Test-StagedDllWritable -Path $probe) -Message "the same file reads writable again once released - not a latched NO"

    # Holder enumeration must still name a process whose StartTime is unreadable - one that exited
    # mid-scan, or that this session cannot open. That is the case the diagnostic exists for, so
    # losing the row (or printing a blank time) defeats it.
    #
    # Injected, never observed: sweeping the real process table only exercises this if a holder
    # happens to be dying at that instant, so it would pass whether or not the bug was present -
    # which is the same as not testing it. A local function outranks a cmdlet in PowerShell's
    # command precedence, so this is what the dot-sourced Get-StagedDllHolder resolves. The stand-in's
    # StartTime getter throws and PowerShell hands back $null - see Initialize-FakeHolderType - and
    # that $null is what the fallback has to convert into a usable "unknown".
    Initialize-FakeHolderType
    function Get-Process {
        param(
            [Parameter(ValueFromRemainingArguments)]
            $Rest
        )
        $fake = New-Object -TypeName FakeHolderProcess
        $fake.Id = -1
        $fake.ProcessName = "fake-holder"
        $fake.Modules = @([PSCustomObject]@{ FileName = $stagedCore })
        , @($fake)
    }

    $injected = @(Get-StagedDllHolder -Path $stagedCore)
    Write-Leg -Ok ($injected.Count -eq 1) -Message "a holder with an unreadable StartTime is still reported, not dropped (got $($injected.Count))"
    Write-Leg -Ok ($injected.Count -eq 1 -and $injected[0].Started -eq "unknown") -Message "its start time reads `"unknown`" rather than printing blank"
    Write-Leg -Ok ($injected.Count -eq 1 -and $injected[0].Id -eq -1 -and $injected[0].Name -eq "fake-holder") -Message "the pid and name - the whole point of the diagnostic - survive"

    # SELF-HOLDER. Running build-dev from a shell that already imported the core drop is the ordinary
    # way to lock it, and the sweep used to skip $PID - so it found nothing and the caller printed
    # "likely held under another user account", pointing the reader at a different machine.
    function Get-Process {
        param(
            [Parameter(ValueFromRemainingArguments)]
            $Rest
        )
        $self = New-Object -TypeName FakeHolderProcess
        $self.Id = $PID
        $self.ProcessName = "pwsh"
        $self.Modules = @([PSCustomObject]@{ FileName = $stagedCore })
        , @($self)
    }
    $selfHeld = @(Get-StagedDllHolder -Path $stagedCore)
    Write-Leg -Ok ($selfHeld.Count -eq 1) -Message "the invoking process is reported when it is itself the holder (got $($selfHeld.Count))"
    Write-Leg -Ok ($selfHeld.Count -eq 1 -and $selfHeld[0].IsSelf) -Message "it is flagged IsSelf, so the caller can say which shell to restart"

    # Control: the pre-fix shape skipped $PID outright. It must report ZERO here - otherwise the leg
    # above passes with or without the fix.
    $holderSource = ($ast.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq "Get-StagedDllHolder"
            }, $true))[0].Extent.Text
    $selfSkipping = $holderSource -replace "function Get-StagedDllHolder", "function Get-StagedDllHolderSkipSelf"
    $selfSkipping = $selfSkipping -replace "(?ms)(foreach \(\`$proc in \(Get-Process[^\r\n]*\r?\n)", "`$1        if (`$proc.Id -eq `$PID) { continue }`r`n"
    if ($selfSkipping -notmatch "Get-StagedDllHolderSkipSelf" -or $selfSkipping -notmatch "\-eq \`$PID") {
        Write-Leg -Ok $false -Message "self control: could not reconstruct the pre-fix skip - THE CONTROL IS VOID, do not trust the two legs above"
    } else {
        . ([scriptblock]::Create($selfSkipping))
        $skipped = @(Get-StagedDllHolderSkipSelf -Path $stagedCore)
        Write-Leg -Ok ($skipped.Count -eq 0) -Message "self control: the pre-fix sweep reports $($skipped.Count) holders - the legs above detect the regression"
    }

    # And the control: the same injection against the pre-fix shape, which assigned StartTime
    # unconditionally. It must yield a BLANK start time - if it still says "unknown", the fallback is
    # not what produces that and the leg above cannot fail.
    $holderText = ($ast.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq "Get-StagedDllHolder"
            }, $true))[0].Extent.Text
    $unguarded = $holderText -replace "(?ms)if \(\`$proc\.StartTime\) \{\r?\n\s*(\`$started = \`$proc\.StartTime)\r?\n\s*\}", "`$1"
    $unguarded = $unguarded -replace "function Get-StagedDllHolder", "function Get-StagedDllHolderUnguarded"
    if ($unguarded -eq $holderText -or $unguarded -notmatch "Get-StagedDllHolderUnguarded") {
        Write-Leg -Ok $false -Message "control: could not reconstruct the pre-fix holder sweep - THE CONTROL IS VOID, do not trust the legs above"
    } else {
        . ([scriptblock]::Create($unguarded))
        $controlHolders = @(Get-StagedDllHolderUnguarded -Path $stagedCore)
        if ($controlHolders.Count -ne 1) {
            Write-Leg -Ok $false -Message "control: reported $($controlHolders.Count) holders, so it failed before reaching StartTime - THE CONTROL IS VOID"
        } else {
            Write-Leg -Ok ([string]::IsNullOrEmpty([string]$controlHolders[0].Started)) -Message "control: without the fallback the start time comes back blank - the leg above detects the regression"
        }
    }
    Remove-Item -Path Function:\Get-Process -ErrorAction SilentlyContinue

    # 5. -SkipRuntime must skip both the staging loop and the preflight.
    $runtimeSkip = $ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.IfStatementAst] -and
            $node.Clauses[0].Item1.Extent.Text -match "SkipRuntime" -and
            $node.Clauses[0].Item2.Extent.Text -match "continue"
        }, $true)
    Write-Leg -Ok ([bool]$runtimeSkip) -Message "-SkipRuntime short-circuits the runtime staging loop"

    # Behavioural, not structural: with the DLL locked, -SkipRuntime must get past the preflight AND
    # go on to do the work it exists for. "No lock error" on its own is not that assertion - it also
    # holds when the run dies immediately afterwards, which is how this leg first passed.
    Remove-Item -Path $stagedSatellite -Force -ErrorAction SilentlyContinue
    $baseBefore = (Get-FileHash -Path $stagedCore -Algorithm SHA256).Hash
    # FileShare.Read, because that is how a live process actually holds this file: a loaded .NET
    # assembly is mapped shared-read, so staging is refused (the preflight opens ReadWrite/None and
    # is denied) while reads still succeed. An exclusive lock here would model a holder that does not
    # occur in the #849 scenario, and it hid a real defect: the skew check hashes the staged copy, and
    # under an exclusive lock it died instead of comparing. The unreadable case has its own leg below.
    $lock2 = [System.IO.File]::Open($stagedCore, "Open", "Read", "Read")
    try {
        $splatSkip = @{
            Script   = $sandboxScript
            Switches = @("-SkipRuntime")
            WorkDir  = $runDir
        }
        $skipLocked = Invoke-BuildDev @splatSkip
    } finally {
        $lock2.Close()
    }
    $baseAfter = (Get-FileHash -Path $stagedCore -Algorithm SHA256).Hash
    Write-Leg -Ok ($skipLocked.Output -notmatch "cannot stage") -Message "-SkipRuntime proceeds even with the staged DLL locked - the #849 unblock"
    Write-Leg -Ok ($skipLocked.ExitCode -eq 0) -Message "-SkipRuntime runs to completion with the base DLL locked (exit $($skipLocked.ExitCode))"
    Write-Leg -Ok ($skipLocked.Output -match "Skipping runtime dbatools.dll") -Message "it says it skipped the runtime rather than skipping silently"
    Write-Leg -Ok ($skipLocked.Output -notmatch "Building runtime dbatools.dll") -Message "no runtime build ran - and leg 3 proved this sandbox CAN run one"
    Write-Leg -Ok ($skipLocked.Output -match "Staged satellite: dbatools.fake") -Message "satellites still built and staged - -SkipRuntime is not a no-op"
    Write-Leg -Ok (Test-Path -LiteralPath $stagedSatellite) -Message "the satellite assembly really landed in the module stage"
    Write-Leg -Ok ($baseBefore -eq $baseAfter) -Message "the locked staged base is byte-identical after the run"
    Write-Leg -Ok ($skipLocked.Output -notmatch "NEWER runtime") -Message "and it does NOT cry skew when dbatools/ source was untouched - the case -SkipRuntime is for"

    # 5b. ABI SKEW. Every satellite csproj ProjectReferences dbatools.csproj, so a satellite build
    #     recompiles the runtime even under -SkipRuntime; only the staging is skipped. The gate cannot
    #     see the result - its parity guard hashes the two STAGED copies and staging is what did not
    #     run (#854) - so this script has to.
    #
    #     Skew is a CONTENT difference, so every leg here writes genuinely different bytes. An earlier
    #     version moved the timestamp on byte-identical files, which only ever proved that the check
    #     read the instrument it was written against - it would have passed just as well against a
    #     wrong instrument. The two timestamp legs below exist because that wrong instrument, an mtime
    #     compare, is silent on both of them.
    # The marker may only waive a byte mismatch while the base source remains exactly the committed
    # tree it records. Make this sandbox source dirty before exercising real changed-source skew.
    Set-Content -Path $sandbox.SourceFile -Value "// changed source" -Encoding Ascii
    $builtItem = Get-Item -LiteralPath $builtRuntime
    $stagedItem = Get-Item -LiteralPath $stagedCore
    $pristineBuilt = Get-Content -Path $builtRuntime -Raw
    # The staged satellite from the clean run above. A rejected run must leave it exactly here:
    # Ship-Satellite.ps1 reads this tree and not the exit code, so a satellite staged against the new
    # runtime beside the old base would ship on the next gate with nothing left to report it.
    $satBefore = (Get-FileHash -Path $stagedSatellite -Algorithm SHA256).Hash
    # The build output has to differ from what is staged, or "staged copy unchanged" is true whether
    # or not the copy ran and the leg proves nothing. This is also what really happens: the satellite
    # recompiles against the changed runtime, which is the whole reason its bits must not be staged.
    Set-Content -Path $sandbox.BuiltSatellite -Value "recompiled against the CHANGED runtime" -Encoding Ascii -NoNewline
    $splatSkew = @{
        Script   = $sandboxScript
        Switches = @("-SkipRuntime")
        WorkDir  = $runDir
    }

    Set-Content -Path $builtRuntime -Value "rebuilt from CHANGED dbatools/ source" -Encoding Ascii -NoNewline
    (Get-Item -LiteralPath $builtRuntime).LastWriteTimeUtc = $stagedItem.LastWriteTimeUtc.AddMinutes(5)
    $skew = Invoke-BuildDev @splatSkew
    Write-Leg -Ok ($skew.ExitCode -eq 1) -Message "a runtime whose bytes differ from the staged base fails the -SkipRuntime run (exit $($skew.ExitCode))"
    Write-Leg -Ok ($skew.Output -match "DIFFERS from the staged base") -Message "the failure names the skew rather than dying obscurely"
    Write-Leg -Ok ($skew.Output -match "#854") -Message "it says the gate will not catch this, and cites the issue"
    Write-Leg -Ok ($skew.Output -match "Building satellite dbatools.fake") -Message "the check runs AFTER the satellites build - it is a verdict, not a second preflight"
    Write-Leg -Ok ($skew.Output -notmatch "Staged satellite: dbatools.fake") -Message "but nothing was staged - a rejected build must not leave new satellites beside the old base"
    Write-Leg -Ok ((Get-FileHash -Path $stagedSatellite -Algorithm SHA256).Hash -eq $satBefore) -Message "and the previously staged satellite is byte-identical, so Ship-Satellite has nothing mismatched to push"

    # Differing bytes, SAME mtime - and then differing bytes, OLDER mtime. Both are real skew (a
    # staged copy that came from some other build), and an mtime compare passes both.
    (Get-Item -LiteralPath $builtRuntime).LastWriteTimeUtc = $stagedItem.LastWriteTimeUtc
    $skewSame = Invoke-BuildDev @splatSkew
    Write-Leg -Ok ($skewSame.ExitCode -eq 1 -and $skewSame.Output -match "DIFFERS from the staged base") -Message "differing bytes with an EQUAL mtime still fail - an mtime compare would pass this"

    (Get-Item -LiteralPath $builtRuntime).LastWriteTimeUtc = $stagedItem.LastWriteTimeUtc.AddMinutes(-5)
    $skewOlder = Invoke-BuildDev @splatSkew
    Write-Leg -Ok ($skewOlder.ExitCode -eq 1 -and $skewOlder.Output -match "DIFFERS from the staged base") -Message "differing bytes with an OLDER mtime still fail - an mtime compare would pass this too"

    # The other direction: identical bytes with a NEWER mtime is NOT skew, and must stay quiet. An
    # mtime compare reds here, which would break the very case -SkipRuntime exists for.
    Set-Content -Path $builtRuntime -Value $pristineBuilt -Encoding Ascii -NoNewline
    (Get-Item -LiteralPath $builtRuntime).LastWriteTimeUtc = $stagedItem.LastWriteTimeUtc.AddMinutes(5)
    $noSkew = Invoke-BuildDev @splatSkew
    Write-Leg -Ok ($noSkew.ExitCode -eq 0 -and $noSkew.Output -notmatch "DIFFERS from the staged base") -Message "identical bytes with a NEWER mtime stay quiet (exit $($noSkew.ExitCode)) - an mtime compare would red this"
    (Get-Item -LiteralPath $builtRuntime).LastWriteTimeUtc = $builtItem.LastWriteTimeUtc

    # A holder that denies reads leaves the comparison unmade. That is UNKNOWN skew, and reporting it
    # as absent is the failure mode this whole check exists to prevent - so it must exit non-zero and
    # say the comparison did not happen, not fall through quietly.
    $deny = [System.IO.File]::Open($stagedCore, "Open", "ReadWrite", "None")
    try {
        $unreadable = Invoke-BuildDev @splatSkew
    } finally {
        $deny.Close()
    }
    Write-Leg -Ok ($unreadable.ExitCode -eq 1) -Message "an unreadable staged base fails the run rather than passing on an unmade comparison (exit $($unreadable.ExitCode))"
    Write-Leg -Ok ($unreadable.Output -match "Skew is UNKNOWN, not absent") -Message "and it says the comparison could not be made, not that the bits agree"

    # 6. NEGATIVE CONTROL. Everything above is unfalsifiable until a script WITHOUT the guard turns a
    #    leg red. Two earlier control shapes were void, both guarded against here: the pre-change
    #    script from git exits 1 on its own base-drop precondition when run from a bare temp
    #    directory (matching the exit code for entirely the wrong reason), and placed where its
    #    paths resolve it runs a real multi-minute dotnet build. So the control is the CURRENT
    #    script with only the mutual-exclusion block removed, inside the sandbox. With the guard
    #    gone both switches are accepted and both loops skip, so nothing is compiled.
    $controlPath = Join-Path -Path $sandbox.Build -ChildPath "build-dev-control.ps1"
    $controlText = $scriptText -replace "(?ms)if \(\`$SkipRuntime -and \`$SkipSatellites\) \{.*?\r?\n\}\r?\n", ""
    if ($controlText -eq $scriptText) {
        Write-Leg -Ok $false -Message "control: could not strip the mutual-exclusion block - THE CONTROL IS VOID, do not trust the legs above"
    } else {
        Set-Content -Path $controlPath -Value $controlText -Encoding UTF8
        $splatCtl = @{
            Script   = $controlPath
            Switches = @("-SkipRuntime", "-SkipSatellites")
            WorkDir  = $runDir
        }
        $control = Invoke-BuildDev @splatCtl
        if ($control.Output -match "base drop missing|A parameter cannot be found|ParameterBindingException") {
            Write-Leg -Ok $false -Message "control: died on a precondition, not on the missing guard - THE CONTROL IS VOID"
        } elseif ($control.Output -match "nothing to build") {
            Write-Leg -Ok $false -Message "control: the stripped script STILL reported the conflict - leg 1 cannot fail, do not trust it"
        } else {
            Write-Leg -Ok $true -Message "control: without the guard the conflict goes unreported (exit $($control.ExitCode)) - leg 1 detects the regression"
        }
    }

    # 7. End-to-end, opt-in: a -SkipRuntime run leaves the REAL staged base byte-identical.
    if ($IncludeBuild) {
        # Drop the sandbox PATH first: the child inherits it, and its fake dotnet compiles nothing, so
        # the "real" build would pass without a compiler ever running. The leg below re-checks that.
        $env:PATH = $originalPath
        $root = Split-Path -Path (Split-Path -Path $resolved)
        $realStaged = Join-Path -Path $root -ChildPath "artifacts/dbatools.library/core/lib/dbatools.dll"
        $before = (Get-FileHash -Path $realStaged -Algorithm SHA256).Hash
        $splatBuild = @{
            Script   = $resolved
            Switches = @("-SkipRuntime")
            WorkDir  = $runDir
        }
        $build = Invoke-BuildDev @splatBuild
        $after = (Get-FileHash -Path $realStaged -Algorithm SHA256).Hash
        Write-Leg -Ok ($build.ExitCode -eq 0) -Message "-SkipRuntime completes against the real tree (exit $($build.ExitCode))"
        Write-Leg -Ok ($build.Output -notmatch "fake dotnet") -Message "a REAL compiler ran - the sandbox's fake dotnet did not leak in and make this leg vacuous"
        Write-Leg -Ok ($before -eq $after) -Message "the staged base dbatools.dll is untouched by a -SkipRuntime run"
    } else {
        Write-Host "skip end-to-end -SkipRuntime build (pass -IncludeBuild, holding the library edit lease)"
    }
} finally {
    $env:PATH = $originalPath
    Remove-Item -Path $runDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "$pass passed, $fail failed"
if ($fail -gt 0) { exit 1 }
exit 0
