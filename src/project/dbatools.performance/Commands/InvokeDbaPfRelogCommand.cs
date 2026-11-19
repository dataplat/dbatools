#nullable enable

using System;
using System.Collections;
using System.Collections.ObjectModel;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Wraps relog.exe over perfmon logs. Port of public/Invoke-DbaPfRelog.ps1 (W1-109).
/// The begin/process/end lifecycle: begin writes MODULE-SCOPE $script: state
/// (beginstring/endstring/destinationset/perfmonobject - cross-invocation pollution the
/// module-scoped hops preserve NATURALLY) and seeds $allpaths from -Path; each process
/// record appends .blg discoveries from piped DataCollectorSet/DataCollector objects
/// (the record-less Append/bin gate returns per record); the end hop runs the unique
/// filter, the giant relog scriptblock (elevation check, clobber dance, param build,
/// cmd /c relog with the nested output-parsing scriptblock and its Add-Member RelogFile
/// decoration) and the Multithread Invoke-Parallel path VERBATIM - the two LOCAL
/// Invoke-Command sites are scope-equivalent invocations per the W1-080 law (their bare
/// `continue`s target the enclosing foreach exactly as before); $allpaths carries
/// begin->process->end through the sentinel state bag; in-hop Stop-Functions carry
/// -FunctionName (W1-090). Surface pinned by migration/baselines/Invoke-DbaPfRelog.json.
/// </summary>
[Cmdlet(VerbsLifecycle.Invoke, "DbaPfRelog")]
public sealed class InvokeDbaPfRelogCommand : DbaBaseCmdlet
{
    /// <summary>The .blg file path(s).</summary>
    [Parameter(ValueFromPipelineByPropertyName = true, Position = 0)]
    [Alias("FullName")]
    public string[]? Path { get; set; }

    /// <summary>Output destination.</summary>
    [Parameter(Position = 1)]
    public string? Destination { get; set; }

    /// <summary>Output type.</summary>
    [Parameter(Position = 2)]
    [PsStringCast]
    [ValidateSet("tsv", "csv", "bin", "sql")]
    public string Type { get; set; } = "tsv";

    /// <summary>Appends to an existing bin file.</summary>
    [Parameter]
    public SwitchParameter Append { get; set; }

    /// <summary>Overwrites existing output.</summary>
    [Parameter]
    public SwitchParameter AllowClobber { get; set; }

    /// <summary>Counter filter list.</summary>
    [Parameter(Position = 3)]
    public string[]? PerformanceCounter { get; set; }

    /// <summary>Counter filter file.</summary>
    [Parameter(Position = 4)]
    public string? PerformanceCounterPath { get; set; }

    /// <summary>Sample interval.</summary>
    [Parameter(Position = 5)]
    public int Interval { get; set; }

    /// <summary>Range start.</summary>
    [Parameter(Position = 6)]
    [PsDateTimeCast]
    public DateTime BeginTime { get; set; }

    /// <summary>Range end.</summary>
    [Parameter(Position = 7)]
    [PsDateTimeCast]
    public DateTime EndTime { get; set; }

    /// <summary>relog config file.</summary>
    [Parameter(Position = 8)]
    public string? ConfigPath { get; set; }

    /// <summary>Summary output (-q).</summary>
    [Parameter]
    public SwitchParameter Summary { get; set; }

    /// <summary>Collector/collector-set objects piped in.</summary>
    [Parameter(ValueFromPipeline = true, Position = 9)]
    public object[]? InputObject { get; set; }

    /// <summary>Parallel relog via Invoke-Parallel.</summary>
    [Parameter]
    public SwitchParameter Multithread { get; set; }

    /// <summary>All log files instead of the latest.</summary>
    [Parameter]
    public SwitchParameter AllTime { get; set; }

    /// <summary>Raw relog output passthrough.</summary>
    [Parameter]
    public SwitchParameter Raw { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    private Hashtable? _state;

    protected override void BeginProcessing()
    {
        Collection<PSObject> results = NestedCommand.InvokeScoped(this, BeginScript,
            Path, BeginTime, EndTime, Destination ?? "", TestBound("BeginTime"), TestBound("EndTime"), TestBound("Destination"), EnableException.ToBool(), BoundVerbose(), BoundDebug());
        CaptureState(results, emitOthers: false);
    }

    protected override void ProcessRecord()
    {
        Collection<PSObject> results = NestedCommand.InvokeScoped(this, ProcessScript,
            InputObject, Append.ToBool(), Type, Path, AllTime.ToBool(), _state, EnableException.ToBool(), BoundVerbose(), BoundDebug());
        CaptureState(results, emitOthers: true);
    }

    protected override void EndProcessing()
    {
        Collection<PSObject> results = NestedCommand.InvokeScoped(this, EndScript,
            Append.ToBool(), AllowClobber.ToBool(), PerformanceCounter, PerformanceCounterPath ?? "", Interval, ConfigPath ?? "", Summary.ToBool(), Multithread.ToBool(), Raw.ToBool(), Type, Destination ?? "", Path, _state, EnableException.ToBool(), BoundVerbose(), BoundDebug());
        CaptureState(results, emitOthers: true);
    }

    private void CaptureState(Collection<PSObject> results, bool emitOthers)
    {
        foreach (PSObject? item in results)
        {
            Hashtable? sentinel = item?.BaseObject as Hashtable;
            if (sentinel is not null && sentinel.ContainsKey("__w1109State"))
            {
                _state = sentinel["__w1109State"] as Hashtable;
                continue;
            }
            if (emitOthers)
                WriteObject(item);
        }
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

    // PS: the begin block VERBATIM (module-scope $script: writes preserved).
    private const string BeginScript = """
param($Path, $BeginTime, $EndTime, $Destination, $__begintimeBound, $__endtimeBound, $__destinationBound, $EnableException, $__boundVerbose, $__boundDebug)
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    param($Path, $BeginTime, $EndTime, $Destination, $__begintimeBound, $__endtimeBound, $__destinationBound, $EnableException, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundVerbose) { $VerbosePreference = $(if ($__boundVerbose) { "Continue" } else { "SilentlyContinue" }) }
    if ($null -ne $__boundDebug) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }



    if ($__begintimeBound) {
        $script:beginstring = ($BeginTime -f 'M/d/yyyy hh:mm:ss' | Out-String).Trim()
    }
    if ($__endtimeBound) {
        $script:endstring = ($EndTime -f 'M/d/yyyy hh:mm:ss' | Out-String).Trim()
    }

    $allpaths = @()
    $allpaths += $Path

    # to support multithreading
    if ($__destinationBound) {
        $script:destinationset = $true
        $originaldestination = $Destination
    } else {
        $script:destinationset = $false
    }

    @{ __w1109State = @{ allpaths = $allpaths; originaldestination = $originaldestination } }
} $Path $BeginTime $EndTime $Destination $__begintimeBound $__endtimeBound $__destinationBound $EnableException $__boundVerbose $__boundDebug 3>&1
""";

    // PS: the process block VERBATIM (the record-less Append gate's `return` exits the
    // dot-sourced block so the sentinel still emits - the W1-108 law).
    private const string ProcessScript = """
param($InputObject, $Append, $Type, $Path, $AllTime, $__state, $EnableException, $__boundVerbose, $__boundDebug)
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    param($InputObject, $Append, $Type, $Path, $AllTime, $__state, $EnableException, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundVerbose) { $VerbosePreference = $(if ($__boundVerbose) { "Continue" } else { "SilentlyContinue" }) }
    if ($null -ne $__boundDebug) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }
    $allpaths = $__state.allpaths
    . {

    if ($Append -and $Type -ne "bin") {
        Stop-Function -Message "Append can only be used with -Type bin." -Target $Path -FunctionName Invoke-DbaPfRelog
        return
    }

    if ($InputObject) {
        foreach ($object in $InputObject) {
            # DataCollectorSet
            if ($object.OutputLocation -and $object.RemoteOutputLocation) {
                $instance = [dbainstance]$object.ComputerName

                if (-not $AllTime) {
                    if ($instance.IsLocalHost) {
                        $allpaths += (Get-ChildItem -Recurse -Path $object.LatestOutputLocation -Include *.blg -ErrorAction SilentlyContinue).FullName
                    } else {
                        $allpaths += (Get-ChildItem -Recurse -Path $object.RemoteLatestOutputLocation -Include *.blg -ErrorAction SilentlyContinue).FullName
                    }
                } else {
                    if ($instance.IsLocalHost) {
                        $allpaths += (Get-ChildItem -Recurse -Path $object.OutputLocation -Include *.blg -ErrorAction SilentlyContinue).FullName
                    } else {
                        $allpaths += (Get-ChildItem -Recurse -Path $object.RemoteOutputLocation -Include *.blg -ErrorAction SilentlyContinue).FullName
                    }
                }


                $script:perfmonobject = $true
            }
            # DataCollector
            if ($object.LatestOutputLocation -and $object.RemoteLatestOutputLocation) {
                $instance = [dbainstance]$object.ComputerName

                if (-not $AllTime) {
                    if ($instance.IsLocalHost) {
                        $allpaths += (Get-ChildItem -Recurse -Path $object.LatestOutputLocation -Include *.blg -ErrorAction SilentlyContinue).FullName
                    } else {
                        $allpaths += (Get-ChildItem -Recurse -Path $object.RemoteLatestOutputLocation -Include *.blg -ErrorAction SilentlyContinue).FullName
                    }
                } else {
                    if ($instance.IsLocalHost) {
                        $allpaths += (Get-ChildItem -Recurse -Path (Split-Path $object.LatestOutputLocation) -Include *.blg -ErrorAction SilentlyContinue).FullName
                    } else {
                        $allpaths += (Get-ChildItem -Recurse -Path (Split-Path $object.RemoteLatestOutputLocation) -Include *.blg -ErrorAction SilentlyContinue).FullName
                    }
                }
                $script:perfmonobject = $true
            }
        }
    }

    }
    @{ __w1109State = @{ allpaths = $allpaths; originaldestination = $__state.originaldestination } }
} $InputObject $Append $Type $Path $AllTime $__state $EnableException $__boundVerbose $__boundDebug 3>&1
""";

    // PS: the end block VERBATIM (the unique filter, the relog scriptblock, the
    // Multithread/serial split with the W1-080 scope-equivalent local invocations).
    private const string EndScript = """
param($Append, $AllowClobber, $PerformanceCounter, $PerformanceCounterPath, $Interval, $ConfigPath, $Summary, $Multithread, $Raw, $Type, $Destination, $Path, $__state, $EnableException, $__boundVerbose, $__boundDebug)
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    param($Append, $AllowClobber, $PerformanceCounter, $PerformanceCounterPath, $Interval, $ConfigPath, $Summary, $Multithread, $Raw, $Type, $Destination, $Path, $__state, $EnableException, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundVerbose) { $VerbosePreference = $(if ($__boundVerbose) { "Continue" } else { "SilentlyContinue" }) }
    if ($null -ne $__boundDebug) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }
    $allpaths = $__state.allpaths
    $originaldestination = $__state.originaldestination
    . {

    $allpaths = $allpaths | Where-Object { $_ -match '.blg' } | Select-Object -Unique

    if (-not $allpaths) {
        # -Continue here had no enclosing loop: the flow control leaked out of the
        # function and TERMINATED THE CALLING SCRIPT. The return alone is correct.
        Stop-Function -Message "Could not find matching .blg files" -Target $file -FunctionName Invoke-DbaPfRelog
        return
    }

    $scriptBlock = {
        if ($args) {
            $file = $args
        } else {
            $file = $PSItem
        }
        $item = Get-ChildItem -Path $file -ErrorAction SilentlyContinue

        if ($null -eq $item) {
            Stop-Function -Message "$file does not exist." -Target $file -Continue -FunctionName Invoke-DbaPfRelog
            return
        }

        if (-not $script:destinationset -and $file -match "C\:\\.*Admin.*") {
            $null = Test-ElevationRequirement -ComputerName $env:COMPUTERNAME -Continue
        }

        if ($script:destinationset -eq $false -and -not $Append) {
            $Destination = Join-Path (Split-Path $file) $item.BaseName
        }

        if ($Destination -and $Destination -notmatch "\." -and -not $Append -and $script:perfmonobject) {
            # if destination is set, then it needs a different name
            if ($script:destinationset -eq $true) {
                if ($file -match "\:") {
                    $computer = $env:COMPUTERNAME
                } else {
                    $computer = $file.Split("\")[2]
                }
                # Avoid naming conflicts
                $timestamp = Get-Date -format yyyyMMddHHmmfff
                $Destination = Join-Path $originaldestination "$computer - $($item.BaseName) - $timestamp"
            }
        }

        $params = @("`"$file`"")

        if ($Append) {
            $params += "-a"
        }

        if ($PerformanceCounter) {
            $parsedcounters = $PerformanceCounter -join " "
            $params += "-c `"$parsedcounters`""
        }

        if ($PerformanceCounterPath) {
            $params += "-cf `"$PerformanceCounterPath`""
        }

        $params += "-f $Type"

        if ($Interval) {
            $params += "-t $Interval"
        }

        if ($Destination) {
            $params += "-o `"$Destination`""
        }

        if ($script:beginstring) {
            $params += "-b $script:beginstring"
        }

        if ($script:endstring) {
            $params += "-e $script:endstring"
        }

        if ($ConfigPath) {
            $params += "-config $ConfigPath"
        }

        if ($Summary) {
            $params += "-q"
        }


        if (-not ($Destination.StartsWith("DSN"))) {
            $outputisfile = $true
        } else {
            $outputisfile = $false
        }

        if ($outputisfile) {
            if ($Destination) {
                $dir = Split-Path $Destination
                if (-not (Test-Path -Path $dir)) {
                    try {
                        $null = New-Item -ItemType Directory -Path $dir -ErrorAction Stop
                    } catch {
                        Stop-Function -Message "Failure" -ErrorRecord $_ -Target $Destination -Continue -FunctionName Invoke-DbaPfRelog
                    }
                }

                if ((Test-Path $Destination) -and -not $Append -and ((Get-Item $Destination) -isnot [System.IO.DirectoryInfo])) {
                    if ($AllowClobber) {
                        try {
                            Remove-Item -Path "$Destination" -ErrorAction Stop
                        } catch {
                            Stop-Function -Message "Failure" -ErrorRecord $_ -Continue -FunctionName Invoke-DbaPfRelog
                        }
                    } else {
                        if ($Type -eq "bin") {
                            Stop-Function -Message "$Destination exists. Use -AllowClobber to overwrite or -Append to append." -Continue -FunctionName Invoke-DbaPfRelog
                        } else {
                            Stop-Function -Message "$Destination exists. Use -AllowClobber to overwrite." -Continue -FunctionName Invoke-DbaPfRelog
                        }
                    }
                }

                if ((Test-Path "$Destination.$type") -and -not $Append) {
                    if ($AllowClobber) {
                        try {
                            Remove-Item -Path "$Destination.$type" -ErrorAction Stop
                        } catch {
                            Stop-Function -Message "Failure" -ErrorRecord $_ -Continue -FunctionName Invoke-DbaPfRelog
                        }
                    } else {
                        if ($Type -eq "bin") {
                            Stop-Function -Message "$("$Destination.$type") exists. Use -AllowClobber to overwrite or -Append to append." -Continue -FunctionName Invoke-DbaPfRelog
                        } else {
                            Stop-Function -Message "$("$Destination.$type") exists. Use -AllowClobber to overwrite." -Continue -FunctionName Invoke-DbaPfRelog
                        }
                    }
                }
            }
        }

        $arguments = ($params -join " ")

        try {
            if ($Raw) {
                Write-Message -Level Output -Message "relog $arguments"
                cmd /c "relog $arguments"
            } else {
                Write-Message -Level Verbose -Message "relog $arguments"
                $scriptBlock = {
                    $output = (cmd /c "relog $arguments" | Out-String).Trim()

                    if ($output -notmatch "Success") {
                        Stop-Function -Continue -Message $output.Trim("Input") -FunctionName Invoke-DbaPfRelog
                    } else {
                        Write-Message -Level Verbose -Message "$output"
                        $array = $output -Split [environment]::NewLine
                        $files = $array | Select-String "File:"

                        foreach ($rawfile in $files) {
                            $rawfile = $rawfile.ToString().Replace("File:", "").Trim()
                            $gcierror = $null
                            Get-ChildItem $rawfile -ErrorAction SilentlyContinue -ErrorVariable gcierror | Add-Member -MemberType NoteProperty -Name RelogFile -Value $true -PassThru -ErrorAction Ignore
                            if ($gcierror) {
                                Write-Message -Level Verbose -Message "$gcierror"
                            }
                        }
                    }
                }
                & $scriptBlock
            }
        } catch {
            Stop-Function -Message "Failure" -ErrorRecord $_ -Target $path -FunctionName Invoke-DbaPfRelog
        }
    }

    if ($Multithread) {
        $allpaths | Invoke-Parallel -ImportVariables -ImportModules -ScriptBlock $scriptBlock -ErrorAction SilentlyContinue -ErrorVariable parallelerror
        if ($parallelerror) {
            Write-Message -Level Verbose -Message "$parallelerror"
        }
    } else {
        foreach ($file in $allpaths) { & $scriptBlock $file }
    }

    }
    @{ __w1109State = @{ allpaths = $allpaths; originaldestination = $originaldestination } }
} $Append $AllowClobber $PerformanceCounter $PerformanceCounterPath $Interval $ConfigPath $Summary $Multithread $Raw $Type $Destination $Path $__state $EnableException $__boundVerbose $__boundDebug 3>&1
""";
}
