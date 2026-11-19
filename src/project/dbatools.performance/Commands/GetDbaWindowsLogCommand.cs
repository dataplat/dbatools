#nullable enable

using System;
using System.Collections;
using System.Collections.ObjectModel;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Parses SQL Server error logs remotely via runspace fan-out. Port of
/// public/Get-DbaWindowsLog.ps1 (W1-106). The begin/process/end lifecycle shares LIVE
/// state (the runspace pool, the runspace collection, the two scriptblocks, and the
/// captured DefaultRunspace) through a hashtable bag the C# side holds by reference
/// between hops; each hop re-defines the Start-Runspace/Receive-Runspace helpers
/// VERBATIM over locals unpacked from the bag so their dynamic-scope reads resolve the
/// same way the function's did. Output streams from EndInvoke inside Receive-Runspace
/// (the buffered NestedCommand interleave is the ruled W1-032 class). $Start defaults
/// to the 1/1/1970 cast and $End to Get-Date at invocation. Surface pinned by
/// migration/baselines/Get-DbaWindowsLog.json.
/// </summary>
[Cmdlet(VerbsCommon.Get, "DbaWindowsLog")]
public sealed class GetDbaWindowsLogCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(ValueFromPipeline = true, Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; } = BuildDefaultComputerName();

    private static DbaInstanceParameter[]? BuildDefaultComputerName()
    {
        string? name = Environment.GetEnvironmentVariable("COMPUTERNAME");
        if (string.IsNullOrEmpty(name))
            return null;
        return new DbaInstanceParameter[] { new DbaInstanceParameter(name) };
    }

    /// <summary>Earliest log entry to include.</summary>
    [Parameter(Position = 1)]
    [PsDateTimeCast]
    public DateTime Start { get; set; } = (DateTime)LanguagePrimitives.ConvertTo("1/1/1970 00:00:00", typeof(DateTime), CultureInfo.InvariantCulture);

    /// <summary>Latest log entry to include.</summary>
    [Parameter(Position = 2)]
    [PsDateTimeCast]
    public DateTime End { get; set; } = DateTime.Now;

    /// <summary>Windows credential for the remote execution.</summary>
    [Parameter(Position = 3)]
    public PSCredential? Credential { get; set; }

    /// <summary>Local runspace throttle (0 = unlimited).</summary>
    [Parameter(Position = 4)]
    public int MaxThreads { get; set; }

    /// <summary>Remote per-host runspace throttle.</summary>
    [Parameter(Position = 5)]
    public int MaxRemoteThreads { get; set; } = 2;

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    private Hashtable? _state;

    protected override void BeginProcessing()
    {
        // PS: Write-Message -Level Debug -Message "Bound parameters: ..."
        WriteMessage(MessageLevel.Debug, "Bound parameters: " + string.Join(", ", MyInvocation.BoundParameters.Keys));

        Collection<PSObject> results = NestedCommand.InvokeScoped(this, BeginScript, MaxThreads);
        _state = results.Count == 1 ? PSObject.AsPSObject(results[results.Count - 1]).BaseObject as Hashtable : null;
    }

    protected override void ProcessRecord()
    {
        foreach (DbaInstanceParameter? instance in SqlInstance ?? new DbaInstanceParameter[0])
        {
            foreach (PSObject? item in NestedCommand.InvokeScoped(this, ProcessScript, _state, instance, Start, End, Credential, MaxRemoteThreads, BoundVerbose(), BoundDebug()))
                WriteObject(item);
        }
    }

    protected override void EndProcessing()
    {
        foreach (PSObject? item in NestedCommand.InvokeScoped(this, EndScript, _state, BoundVerbose(), BoundDebug()))
            WriteObject(item);
    }

    /// <summary>A bound -Debug carrier for the hop scopes (W1-044 convention).</summary>
    private object? BoundDebug()
    {
        object? debug;
        if (MyInvocation.BoundParameters.TryGetValue("Debug", out debug))
            return LanguagePrimitives.IsTrue(debug);
        return null;
    }

    /// <summary>A bound -Verbose carrier for the hop scopes (W1-044 convention).</summary>
    private object? BoundVerbose()
    {
        object? verbose;
        if (MyInvocation.BoundParameters.TryGetValue("Verbose", out verbose))
            return LanguagePrimitives.IsTrue(verbose);
        return null;
    }

    // PS: the begin block VERBATIM (the two scriptblocks, the runspace pool setup, the
    // DefaultRunspace capture) returned as a live-state hashtable.
    private const string BeginScript = """
param($MaxThreads)
#region Scriptblocks
$scriptBlock_RemoteExecution = {
    param (
        [System.DateTime]
        $Start,

        [System.DateTime]
        $End,

        [string]
        $InstanceName,

        [int]
        $Throttle
    )

    #region Helper function
    function Convert-ErrorRecord {
        param (
            $Line
        )

        if (Get-Variable -Name codesAndStuff -Scope 1) {
            $line2 = (Get-Variable -Name codesAndStuff -Scope 1).Value
            Remove-Variable -Name codesAndStuff -Scope 1

            $groups = [regex]::Matches($line2, '^([\d- :]+.\d\d) (\w+)[ ]+Error: (\d+), Severity: (\d+), State: (\d+)').Groups
            $groups2 = [regex]::Matches($line, '^[\d- :]+.\d\d \w+[ ]+(.*)$').Groups

            New-Object PSObject -Property @{
                Timestamp   = [DateTime]::ParseExact($groups[1].Value, "yyyy-MM-dd HH:mm:ss.ff", $null)
                Spid        = $groups[2].Value
                Message     = $groups2[1].Value
                ErrorNumber = [int]($groups[3].Value)
                Severity    = [int]($groups[4].Value)
                State       = [int]($groups[5].Value)
            }
        }

        if ($Line -match '^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\.\d\d[\w ]+((\w+): (\d+)[,\.]\s?){3}') {
            Set-Variable -Name codesAndStuff -Value $Line -Scope 1
        }
    }
    #endregion Helper function

    #region Script that processes an individual file
    $scriptBlock = {
        param (
            [System.IO.FileInfo]
            $File
        )

        try {
            $stream = New-Object System.IO.FileStream($File.FullName, "Open", "Read", "ReadWrite, Delete")
            $reader = New-Object System.IO.StreamReader($stream)

            while (-not $reader.EndOfStream) {
                Convert-ErrorRecord -Line $reader.ReadLine()
            }
        } catch {
            # here to avoid an empty catch
            $null = 1
        }
    }
    #endregion Script that processes an individual file

    #region Gather list of files to process
    $eventSource = "MSSQLSERVER"
    if ($InstanceName -notmatch "^DEFAULT$|^MSSQLSERVER$") {
        $eventSource = 'MSSQL$' + $InstanceName
    }

    $event = Get-WinEvent -FilterHashtable @{
        LogName      = "Application"
        ID           = 17111
        ProviderName = $eventSource
    } -MaxEvents 1 -ErrorAction SilentlyContinue

    if (-not $event) { return }

    $path = $event.Properties[0].Value
    $errorLogPath = Split-Path -Path $path
    $errorLogFileName = Split-Path -Path $path -Leaf
    $errorLogFiles = Get-ChildItem -Path $errorLogPath | Where-Object { ($_.Name -like "$errorLogFileName*") -and ($_.LastWriteTime -gt $Start) -and ($_.CreationTime -lt $End) }
    #endregion Gather list of files to process

    #region Prepare Runspaces
    [Collections.Arraylist]$RunspaceCollection = @()

    $InitialSessionState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    $Command = Get-Item function:Convert-ErrorRecord
    $InitialSessionState.Commands.Add((New-Object System.Management.Automation.Runspaces.SessionStateFunctionEntry($command.Name, $command.Definition)))

    $RunspacePool = [RunspaceFactory]::CreateRunspacePool($InitialSessionState)
    $null = $RunspacePool.SetMinRunspaces(1)
    if ($Throttle -gt 0) { $null = $RunspacePool.SetMaxRunspaces($Throttle) }
    $RunspacePool.Open()
    #endregion Prepare Runspaces

    #region Process Error files
    $countDone = 0
    $countStarted = 0
    $countTotal = ($errorLogFiles | Measure-Object).Count

    while ($countDone -lt $countTotal) {
        while (($RunspacePool.GetAvailableRunspaces() -gt 0) -and ($countStarted -lt $countTotal)) {
            $Powershell = [PowerShell]::Create().AddScript($scriptBlock).AddParameter("File", $errorLogFiles[$countStarted])
            $Powershell.RunspacePool = $RunspacePool
            $null = $RunspaceCollection.Add((New-Object -TypeName PSObject -Property @{ Runspace = $PowerShell.BeginInvoke(); PowerShell = $PowerShell }))
            $countStarted++
        }

        foreach ($Run in $RunspaceCollection.ToArray()) {
            if ($Run.Runspace.IsCompleted) {
                $Run.PowerShell.EndInvoke($Run.Runspace) | Where-Object { ($_.Timestamp -gt $Start) -and ($_.Timestamp -lt $End) }
                $Run.PowerShell.Dispose()
                $RunspaceCollection.Remove($Run)
                $countDone++
            }
        }

        Start-Sleep -Milliseconds 250
    }
    $RunspacePool.Close()
    $RunspacePool.Dispose()
    #endregion Process Error files
}

$scriptBlock_ParallelRemoting = {
    param (
        [DbaInstanceParameter]
        $SqlInstance,

        [DateTime]
        $Start,

        [DateTime]
        $End,

        [PSCredential]
        $Credential,

        [int]
        $MaxRemoteThreads,

        [System.Management.Automation.ScriptBlock]
        $ScriptBlock
    )

    $params = @{
        ArgumentList = $Start, $End, $SqlInstance.InstanceName, $MaxRemoteThreads
        ScriptBlock  = $ScriptBlock
    }
    if (-not $SqlInstance.IsLocalhost) { $params["ComputerName"] = $SqlInstance.ComputerName }
    if ($Credential) { $params["Credential"] = $Credential }

    Invoke-Command @params | Select-Object @{ n = "InstanceName"; e = { $SqlInstance.FullSmoName } }, Timestamp, Spid, Severity, ErrorNumber, State, Message
}
#endregion Scriptblocks

# Sever the caller-runspace affinity the nested-pipeline literals carry: the pool
# must OWN the execution (and its $error bag) the way the function world's detached
# invocation did - an affine scriptblock marshals home and silently bags the remote
# scriptblock's Get-WinEvent records into the caller $error (lab-diffed).
$scriptBlock_RemoteExecution = [scriptblock]::Create($scriptBlock_RemoteExecution.ToString())
$scriptBlock_ParallelRemoting = [scriptblock]::Create($scriptBlock_ParallelRemoting.ToString())

#region Setup Runspace
[Collections.Arraylist]$RunspaceCollection = @()
$InitialSessionState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
$defaultrunspace = [System.Management.Automation.Runspaces.Runspace]::DefaultRunspace
$RunspacePool = [RunspaceFactory]::CreateRunspacePool($InitialSessionState)
$RunspacePool.SetMinRunspaces(1) | Out-Null
if ($MaxThreads -gt 0) { $null = $RunspacePool.SetMaxRunspaces($MaxThreads) }
$RunspacePool.Open()
#endregion Setup Runspace

@{ RunspaceCollection = $RunspaceCollection; RunspacePool = $RunspacePool; ScriptBlockRemote = $scriptBlock_RemoteExecution; ScriptBlockParallel = $scriptBlock_ParallelRemoting; DefaultRunspace = $defaultrunspace }
""";

    // PS: the process body VERBATIM (the helpers re-defined over the live state, the
    // per-instance Start-Runspace + Receive-Runspace pair).
    private const string ProcessScript = """
param($__state, $instance, $Start, $End, $Credential, $MaxRemoteThreads, $__boundVerbose, $__boundDebug)
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    param($__state, $instance, $Start, $End, $Credential, $MaxRemoteThreads, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundVerbose) { $VerbosePreference = $(if ($__boundVerbose) { "Continue" } else { "SilentlyContinue" }) }
    if ($null -ne $__boundDebug) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }
    $RunspaceCollection = $__state.RunspaceCollection
    $RunspacePool = $__state.RunspacePool
    $scriptBlock_RemoteExecution = $__state.ScriptBlockRemote
    $scriptBlock_ParallelRemoting = $__state.ScriptBlockParallel

    function Start-Runspace {
        $Powershell = [PowerShell]::Create().AddScript($scriptBlock_ParallelRemoting).AddParameter("SqlInstance", $instance).AddParameter("Start", $Start).AddParameter("End", $End).AddParameter("Credential", $Credential).AddParameter("MaxRemoteThreads", $MaxRemoteThreads).AddParameter("ScriptBlock", $scriptBlock_RemoteExecution)
        $Powershell.RunspacePool = $RunspacePool
        Write-Message -Level Verbose -Message "Launching remote runspace against <c='green'>$instance</c>" -Target $instance
        $null = $RunspaceCollection.Add((New-Object -TypeName PSObject -Property @{ Runspace = $PowerShell.BeginInvoke(); PowerShell = $PowerShell; Instance = $instance.FullSmoName }))
    }

    function Receive-Runspace {
        [Parameter()]
        param (
            [switch]
            $Wait
        )

        do {
            foreach ($Run in $RunspaceCollection.ToArray()) {
                if ($Run.Runspace.IsCompleted) {
                    Write-Message -Level Verbose -Message "Receiving results from <c='green'>$($Run.Instance)</c>" -Target $Run.Instance
                    $Run.PowerShell.EndInvoke($Run.Runspace)
                    $Run.PowerShell.Dispose()
                    $RunspaceCollection.Remove($Run)
                }
            }

            if ($Wait -and ($RunspaceCollection.Count -gt 0)) { Start-Sleep -Milliseconds 250 }
        }
        while ($Wait -and ($RunspaceCollection.Count -gt 0))
    }

    Write-Message -Level VeryVerbose -Message "Processing <c='green'>$instance</c>" -Target $instance
    Start-Runspace
    Receive-Runspace
} $__state $instance $Start $End $Credential $MaxRemoteThreads $__boundVerbose $__boundDebug 3>&1
""";

    // PS: the end block VERBATIM (drain, close, restore DefaultRunspace).
    private const string EndScript = """
param($__state, $__boundVerbose, $__boundDebug)
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    param($__state, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundVerbose) { $VerbosePreference = $(if ($__boundVerbose) { "Continue" } else { "SilentlyContinue" }) }
    if ($null -ne $__boundDebug) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }
    $RunspaceCollection = $__state.RunspaceCollection
    $RunspacePool = $__state.RunspacePool
    $defaultrunspace = $__state.DefaultRunspace

    function Receive-Runspace {
        [Parameter()]
        param (
            [switch]
            $Wait
        )

        do {
            foreach ($Run in $RunspaceCollection.ToArray()) {
                if ($Run.Runspace.IsCompleted) {
                    Write-Message -Level Verbose -Message "Receiving results from <c='green'>$($Run.Instance)</c>" -Target $Run.Instance
                    $Run.PowerShell.EndInvoke($Run.Runspace)
                    $Run.PowerShell.Dispose()
                    $RunspaceCollection.Remove($Run)
                }
            }

            if ($Wait -and ($RunspaceCollection.Count -gt 0)) { Start-Sleep -Milliseconds 250 }
        }
        while ($Wait -and ($RunspaceCollection.Count -gt 0))
    }

    Receive-Runspace -Wait
    $RunspacePool.Close()
    $RunspacePool.Dispose()
    [System.Management.Automation.Runspaces.Runspace]::DefaultRunspace = $defaultrunspace
} $__state $__boundVerbose $__boundDebug 3>&1
""";
}
