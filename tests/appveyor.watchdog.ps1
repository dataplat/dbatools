#Requires -Version 3
<#
    .SYNOPSIS
        Fails a wedged CI test run fast instead of letting it burn the whole job timeout.

    .DESCRIPTION
        Some of the calls the test suite makes cannot be cancelled once they block. A native
        process invoked without a timeout (certreq), an SMO ManagedComputer WMI call, or a
        WinRM operation can all wedge the thread that runs Invoke-Pester. Nothing inside that
        process can recover: PowerShell.Stop only sets a flag that is checked between pipeline
        commands, and Thread.Abort does not interrupt blocking unmanaged code. The run then sits
        silent until the 90 minute job timeout kills it, with no indication of which test file
        was responsible.

        This watchdog runs out of process, so it stays responsive while the test process is
        stuck. appveyor.pester.ps1 writes the file it is about to run into a heartbeat file.
        When a heartbeat gets older than the timeout, the watchdog names the offending file,
        lists the processes that usually cause this, and then kills the test process so the job
        fails in minutes rather than in an hour and a half.

        The heartbeat file is removed by the runner between the test loop and the summary work,
        so a missing heartbeat means "not running a test" and never triggers a kill.

        Two ordering rules matter here. The test process is killed before any descendant is
        enumerated, because enumeration needs WMI and WMI is one of the things that can be
        wedged: a watchdog that queried first could hang on exactly the fault it exists to
        catch. And the watchdog kills processes individually rather than with taskkill /T,
        because it is itself a child of the test process and a tree kill could take it out
        before the wedged process died.

    .PARAMETER ParentProcessId
        Process ID of the PowerShell process running the test loop.

    .PARAMETER HeartbeatPath
        File the test loop writes before each test file, as "<ticks>|<label>".

    .PARAMETER TimeoutMinutes
        How long a single test file may run before it is treated as wedged.

    .PARAMETER PollSeconds
        How often to check the heartbeat.

    .PARAMETER CimTimeoutSeconds
        Bound on the WMI query used to find leftover child processes after the kill.

    .NOTES
        Tags: CI, Testing
        Author: the dbatools team + Claude

        Website: https://dbatools.io
        Copyright: (c) 2026 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .EXAMPLE
        PS C:\> .\appveyor.watchdog.ps1 -ParentProcessId 1234 -HeartbeatPath C:\github\dbatools\pester-heartbeat-1234.txt

        Watches process 1234 and kills it when a single test file runs longer than the default timeout.
#>
param(
    [Parameter(Mandatory)]
    [ValidateRange(1, 2147483647)]
    [int]$ParentProcessId,
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$HeartbeatPath,
    [ValidateRange(1, 1440)]
    [int]$TimeoutMinutes = 15,
    [ValidateRange(1, 300)]
    [int]$PollSeconds = 15,
    [ValidateRange(5, 120)]
    [int]$CimTimeoutSeconds = 20
)

$ErrorActionPreference = "Continue"

function Write-WatchdogLine {
    param(
        [string]$Message
    )

    # Console is used directly rather than Write-Host because this process is started with
    # -NoNewWindow to share the parent console, and its output has to reach the CI log even
    # though nothing is reading this pipeline.
    [Console]::Out.WriteLine($Message)
    [Console]::Out.Flush()
}

function Get-ParentIdentity {
    <#
        Returns the start time of the watched process, or $null when it is gone. A PID on its
        own is not an identity: Windows reuses PIDs, so an abnormally exited parent could be
        replaced by an unrelated process that we would then kill. The creation time pins it.
    #>
    param(
        [int]$ProcessId
    )

    $process = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    if (-not $process) {
        return $null
    }

    try {
        return $process.StartTime
    } catch {
        # A PID we cannot read the start time for is not one we are willing to kill
        return $null
    }
}

function Get-DescendantProcessId {
    <#
        Best effort, and deliberately bounded. This is the only WMI call in the watchdog and it
        runs after the kill, so a wedged WMI provider costs a leftover child rather than the
        whole safety net.
    #>
    param(
        [int]$ProcessId,
        [int]$OperationTimeoutSeconds
    )

    $splatChildQuery = @{
        ClassName           = "Win32_Process"
        Filter              = "ParentProcessId = $ProcessId"
        OperationTimeoutSec = $OperationTimeoutSeconds
        ErrorAction         = "SilentlyContinue"
    }
    $children = Get-CimInstance @splatChildQuery

    foreach ($child in $children) {
        # Never report our own PID, we have to outlive the processes we are killing
        if ($child.ProcessId -eq $PID) {
            continue
        }
        $child.ProcessId
        Get-DescendantProcessId -ProcessId $child.ProcessId -OperationTimeoutSeconds $OperationTimeoutSeconds
    }
}

$parentIdentity = Get-ParentIdentity -ProcessId $ParentProcessId
if (-not $parentIdentity) {
    Write-WatchdogLine -Message "appveyor.watchdog: pid $ParentProcessId is not running, nothing to watch"
    return
}

Write-WatchdogLine -Message "appveyor.watchdog: watching pid $ParentProcessId, per-file limit $TimeoutMinutes minutes"

while ($true) {
    Start-Sleep -Seconds $PollSeconds

    # The run finished normally, or the PID now belongs to an unrelated process
    $currentIdentity = Get-ParentIdentity -ProcessId $ParentProcessId
    if ($currentIdentity -ne $parentIdentity) {
        Write-WatchdogLine -Message "appveyor.watchdog: pid $ParentProcessId exited, stopping"
        return
    }

    # No heartbeat means the runner is not inside a test file right now
    if (-not (Test-Path -Path $HeartbeatPath)) {
        continue
    }

    $splatHeartbeat = @{
        Path        = $HeartbeatPath
        TotalCount  = 1
        ErrorAction = "Stop"
    }
    try {
        $heartbeat = Get-Content @splatHeartbeat
    } catch {
        # The runner rewrites this file before every test, so a read collision just means retry
        continue
    }

    if (-not $heartbeat) {
        continue
    }

    $heartbeatParts = $heartbeat -split "\|", 2
    if ($heartbeatParts.Count -ne 2) {
        continue
    }

    [long]$startedTicks = 0
    if (-not [System.Int64]::TryParse($heartbeatParts[0], [ref]$startedTicks)) {
        continue
    }
    if ($startedTicks -le 0) {
        continue
    }

    $startedAt = New-Object -TypeName System.DateTime -ArgumentList $startedTicks
    $elapsed = (Get-Date) - $startedAt
    if ($elapsed.TotalMinutes -lt $TimeoutMinutes) {
        continue
    }

    # GitHub only parses a workflow command at the start of a line, so this annotation
    # is written without the usual prefix
    Write-WatchdogLine -Message "::error::Test file $($heartbeatParts[1]) has run for $([int]$elapsed.TotalMinutes) minutes (limit $TimeoutMinutes). Killing the run."
    Write-WatchdogLine -Message "appveyor.watchdog: a native call most likely wedged with no timeout (certreq, SMO ManagedComputer/WMI, or WinRM)."

    # Record the usual suspects before the kill removes the evidence. Get-Process is used
    # rather than a WMI query so this diagnostic cannot hang.
    $suspects = Get-Process -Name "certreq", "certutil", "WmiPrvSE", "wsmprovhost" -ErrorAction SilentlyContinue
    foreach ($suspect in $suspects) {
        try {
            $suspectStartTime = $suspect.StartTime.ToString("HH:mm:ss")
            $startedText = "started $suspectStartTime"
        } catch {
            # Protected processes do not expose StartTime, the name and PID are still worth logging
            $startedText = "start time not readable"
        }
        Write-WatchdogLine -Message "appveyor.watchdog: suspect process $($suspect.Name) (pid $($suspect.Id)), $startedText"
    }

    # Re-check identity immediately before the kill, so a parent that exited during the
    # diagnostics above cannot be confused with a recycled PID
    if ((Get-ParentIdentity -ProcessId $ParentProcessId) -ne $parentIdentity) {
        Write-WatchdogLine -Message "appveyor.watchdog: pid $ParentProcessId exited before the kill, stopping"
        return
    }

    # Kill the test process first. This is the action that has to happen, and it needs nothing
    # but the PID, so it cannot be blocked by the fault we are reacting to.
    Write-WatchdogLine -Message "appveyor.watchdog: killing test process pid $ParentProcessId"
    $splatStopParent = @{
        Id          = $ParentProcessId
        Force       = $true
        ErrorAction = "SilentlyContinue"
    }
    Stop-Process @splatStopParent

    # Then clean up whatever it left behind. Win32_Process still reports ParentProcessId for a
    # dead parent, so this works after the kill. If WMI is the thing that is wedged, the bounded
    # query gives up and we simply leave the orphans to the ephemeral runner.
    try {
        $descendantIds = @(Get-DescendantProcessId -ProcessId $ParentProcessId -OperationTimeoutSeconds $CimTimeoutSeconds)
    } catch {
        $descendantIds = @()
        Write-WatchdogLine -Message "appveyor.watchdog: could not enumerate leftover children. $($PSItem.Exception.Message)"
    }

    foreach ($descendantId in $descendantIds) {
        Write-WatchdogLine -Message "appveyor.watchdog: killing leftover child pid $descendantId"
        $splatStopDescendant = @{
            Id          = $descendantId
            Force       = $true
            ErrorAction = "SilentlyContinue"
        }
        Stop-Process @splatStopDescendant
    }

    return
}
