#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Collects SQL memory performance counters. Port of public/Get-DbaMemoryUsage.ps1
/// (W1-082). The begin-block SCRIPTBLOCK rides the hop VERBATIM (tooling-extracted; its
/// $Computer verbose interpolations stay UNDEFINED remotely); each member-enumerated
/// computer resolves through Resolve-DbaNetworkName -ErrorAction SilentlyContinue (a
/// falsy FullComputerName warns "Can't resolve" with the ORIGINAL name and continues),
/// then Invoke-Command2 runs the block and each result re-projects with
/// [dbasize]($Memory * 1024 * 1024); the try's catch is Stop-Function "Failure"
/// -Continue. Surface pinned by migration/baselines/Get-DbaMemoryUsage.json.
/// </summary>
[Cmdlet(VerbsCommon.Get, "DbaMemoryUsage")]
public sealed class GetDbaMemoryUsageCommand : DbaBaseCmdlet
{
    /// <summary>The target computer(s); defaults to the local computer.</summary>
    [Parameter(ValueFromPipeline = true, Position = 0)]
    [Alias("Host", "cn", "Server")]
    public DbaInstanceParameter[]? ComputerName { get; set; } = BuildDefaultComputerName();

    private static DbaInstanceParameter[]? BuildDefaultComputerName()
    {
        string? name = Environment.GetEnvironmentVariable("COMPUTERNAME");
        if (string.IsNullOrEmpty(name))
            return null;
        return new DbaInstanceParameter[] { new DbaInstanceParameter(name) };
    }

    /// <summary>Windows credential for the remote collection.</summary>
    [Parameter(Position = 1)]
    public PSCredential? Credential { get; set; }

    /// <summary>Memory Manager counter filter.</summary>
    [Parameter(Position = 2)]
    public string MemoryCounterRegex { get; set; } = "(Total Server Memory |Target Server Memory |Connection Memory |Lock Memory |SQL Cache Memory |Optimizer Memory |Granted Workspace Memory |Cursor memory usage|Maximum Workspace)";

    /// <summary>Plan Cache counter filter.</summary>
    [Parameter(Position = 3)]
    public string PlanCounterRegex { get; set; } = "(cache pages|procedure plan|ad hoc sql plan|prepared SQL Plan)";

    /// <summary>Buffer Manager counter filter.</summary>
    [Parameter(Position = 4)]
    public string BufferCounterRegex { get; set; } = "(Free pages|Reserved pages|Stolen pages|Total pages|Database pages|target pages|extension .* pages)";

    /// <summary>SSAS counter filter.</summary>
    [Parameter(Position = 5)]
    public string SSASCounterRegex { get; set; } = "(\\\\memory )";

    /// <summary>SSIS counter filter.</summary>
    [Parameter(Position = 6)]
    public string SSISCounterRegex { get; set; } = "(memory)";

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    protected override void ProcessRecord()
    {
        // PS: foreach ($Computer in $ComputerName.ComputerName) - member enumeration
        // (null parameter/elements walk per the pinned laws).
        List<object?> computers = new List<object?>();
        foreach (DbaInstanceParameter? item in ComputerName ?? new DbaInstanceParameter[0])
        {
            if (item is null)
                continue;
            computers.Add(item.ComputerName);
        }

        foreach (object? computer in computers)
        {
            object? reply = PipelineValue(NestedCommand.InvokeScoped(this, ResolveScript, computer, Credential, BoundVerbose(), BoundDebug()));
            object? fullName = DotAccess(reply, "FullComputerName");
            if (LanguagePrimitives.IsTrue(fullName))
            {
                try
                {
                    foreach (object? item in EnumerateValue(PipelineValue(NestedCommand.InvokeScoped(this, InvokeScript, fullName, Credential, MemoryCounterRegex, PlanCounterRegex, BufferCounterRegex, SSASCounterRegex, SSISCounterRegex, BoundVerbose(), BoundDebug()))))
                    {
                        // PS: a [dbasize] cast fault propagates to the surrounding try's
                        // catch - the REMAINING results for this computer are abandoned.
                        object? memory = DbaSizeBytes(DotAccess(item, "Memory"));
                        PSObject result = new PSObject();
                        result.Properties.Add(new PSNoteProperty("ComputerName", DotAccess(item, "ComputerName")));
                        result.Properties.Add(new PSNoteProperty("SqlInstance", DotAccess(item, "SqlInstance")));
                        result.Properties.Add(new PSNoteProperty("CounterInstance", DotAccess(item, "CounterInstance")));
                        result.Properties.Add(new PSNoteProperty("Counter", DotAccess(item, "Counter")));
                        result.Properties.Add(new PSNoteProperty("Pages", DotAccess(item, "Pages")));
                        result.Properties.Add(new PSNoteProperty("Memory", memory));
                        WriteObject(result);
                    }
                }
                catch (PipelineStoppedException)
                {
                    throw;
                }
                catch (Exception ex)
                {
                    // PS: $Computer was reassigned to the RESOLVED name before the try.
                    StopFunction("Failure", target: fullName, errorRecord: StatementFault.Record(ex, "Get-DbaMemoryUsage"), continueLoop: true);
                    continue;
                }
            }
            else
            {
                WriteMessage(MessageLevel.Warning, "Can't resolve " + PsText(computer) + ".");
                continue;
            }
        }
    }

    /// <summary>PS: [dbasize]($x * 1024 * 1024) - the arithmetic runs first (null * int
    /// is null), then the cast rides LanguagePrimitives.</summary>
    private static object? DbaSizeBytes(object? value)
    {
        object? unwrapped = value is PSObject pso ? pso.BaseObject : value;
        if (unwrapped is null)
            return LanguagePrimitives.ConvertTo(null, typeof(Size), CultureInfo.InvariantCulture);
        double product = (double)LanguagePrimitives.ConvertTo(unwrapped, typeof(double), CultureInfo.InvariantCulture) * 1024.0 * 1024.0;
        return LanguagePrimitives.ConvertTo(product, typeof(Size), CultureInfo.InvariantCulture);
    }

    /// <summary>PS pipeline-assignment collapse: none = null, one = the item, many = array.</summary>
    private static object? PipelineValue(Collection<PSObject> results)
    {
        if (results.Count == 0)
            return null;
        if (results.Count == 1)
            return results[0];
        object?[] array = new object?[results.Count];
        for (int n = 0; n < results.Count; n++)
            array[n] = results[n];
        return array;
    }

    /// <summary>PS foreach over a value: null iterates zero times, an array yields
    /// elements (nulls included), a scalar yields itself.</summary>
    private static IEnumerable<object?> EnumerateValue(object? value)
    {
        if (value is null)
            yield break;
        if (value is object?[] array)
        {
            foreach (object? element in array)
                yield return element;
            yield break;
        }
        yield return value;
    }

    /// <summary>The PS dot operator with member-enumeration semantics (W1-060 shape).</summary>
    private static object? DotAccess(object? item, string name)
    {
        if (item is null)
            return null;
        PSObject wrapped = PSObject.AsPSObject(item);
        PSPropertyInfo? direct = wrapped.Properties[name];
        if (direct is not null)
        {
            object? value;
            try { value = direct.Value; }
            catch { return null; }
            return UnwrapTransit(value);
        }
        object? baseValue = wrapped.BaseObject;
        if (baseValue is not string && LanguagePrimitives.GetEnumerable(baseValue) is IEnumerable elements)
        {
            List<object?> collected = new List<object?>();
            foreach (object? element in elements)
            {
                if (element is null)
                    continue;
                PSObject wrappedElement = PSObject.AsPSObject(element);
                PSPropertyInfo? property = wrappedElement.Properties[name];
                if (property is not null)
                {
                    try { collected.Add(UnwrapTransit(property.Value)); }
                    catch { collected.Add(null); }
                }
                else if (wrappedElement.BaseObject is PSCustomObject)
                {
                    collected.Add(null);
                }
            }
            if (collected.Count == 0)
                return null;
            if (collected.Count == 1)
                return collected[0];
            return collected.ToArray();
        }
        return null;
    }

    private static object? UnwrapTransit(object? value)
    {
        if (value is PSObject psValue && psValue.BaseObject is not PSCustomObject)
            return psValue.BaseObject;
        return value;
    }

    /// <summary>PS string interpolation via LanguagePrimitives (invariant).</summary>
    private static string PsText(object? value)
    {
        if (value is null)
            return "";
        return (string)LanguagePrimitives.ConvertTo(value, typeof(string), CultureInfo.InvariantCulture);
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

    // PS: Resolve-DbaNetworkName -ErrorAction SilentlyContinue, verbatim.
    private const string ResolveScript = """
param($__computer, $Credential, $__boundVerbose, $__boundDebug)
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    param($__computer, $Credential, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundVerbose) { $VerbosePreference = $(if ($__boundVerbose) { "Continue" } else { "SilentlyContinue" }) }
    if ($null -ne $__boundDebug) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }
    Resolve-DbaNetworkName -ComputerName $__computer -Credential $Credential -ErrorAction SilentlyContinue
} $__computer $Credential $__boundVerbose $__boundDebug 3>&1
""";

    // PS: the begin-block scriptblock VERBATIM + the Invoke-Command2 call.
    private const string InvokeScript = """
param($__computer, $Credential, $MemoryCounterRegex, $PlanCounterRegex, $BufferCounterRegex, $SSASCounterRegex, $SSISCounterRegex, $__boundVerbose, $__boundDebug)
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    param($__computer, $Credential, $MemoryCounterRegex, $PlanCounterRegex, $BufferCounterRegex, $SSASCounterRegex, $SSISCounterRegex, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundVerbose) { $VerbosePreference = $(if ($__boundVerbose) { "Continue" } else { "SilentlyContinue" }) }
    if ($null -ne $__boundDebug) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }
        $scriptBlock = {
            param (
                $MemoryCounterRegex,
                $PlanCounterRegex,
                $BufferCounterRegex,
                $SSASCounterRegex,
                $SSISCounterRegex
            )
            <# DO NOT use Write-Message as this is inside of a script block #>
            Write-Verbose -Message "Searching for Memory Manager Counters on $Computer"
            try {
                $availableCounters = (Get-Counter -ListSet '*sql*:Memory Manager*' -ErrorAction SilentlyContinue).paths
                (Get-Counter -Counter $availableCounters -ErrorAction SilentlyContinue).countersamples | Where-Object { $_.Path -match $MemoryCounterRegex } | ForEach-Object {
                    $instance = (($_.Path.split("\")[-2]).replace("mssql`$", "")).split(':')[0]
                    if ($instance -eq 'sqlserver') { $instance = 'mssqlserver' }
                    [PSCustomObject]@{
                        ComputerName    = $env:computername
                        SqlInstance     = $instance
                        CounterInstance = (($_.Path.split("\")[-2]).replace("mssql`$", "")).split(':')[1]
                        Counter         = $_.Path.split("\")[-1]
                        Pages           = $null
                        Memory          = $_.cookedvalue / 1024
                    }
                }
            } catch {
                <# DO NOT use Write-Message as this is inside of a script block #>
                Write-Verbose -Message "No Memory Manager Counters on $Computer"
            }
            <# DO NOT use Write-Message as this is inside of a script block #>
            Write-Verbose -Message "Searching for Plan Cache Counters on $Computer"
            try {
                $availableCounters = (Get-Counter -ListSet '*sql*:Plan Cache*' -ErrorAction SilentlyContinue).paths
                (Get-Counter -Counter $availableCounters -ErrorAction SilentlyContinue).countersamples | Where-Object { $_.Path -match $PlanCounterRegex } | ForEach-Object {
                    $instance = (($_.Path.split("\")[-2]).replace("mssql`$", "")).split(':')[0]
                    if ($instance -eq 'sqlserver') { $instance = 'mssqlserver' }
                    [PSCustomObject]@{
                        ComputerName    = $env:computername
                        SqlInstance     = $instance
                        CounterInstance = (($_.Path.split("\")[-2]).replace("mssql`$", "")).split(':')[1]
                        Counter         = $_.Path.split("\")[-1]
                        Pages           = $_.cookedvalue
                        Memory          = $_.cookedvalue * 8192 / 1048576
                    }
                }
            } catch {
                <# DO NOT use Write-Message as this is inside of a script block #>
                Write-Verbose -Message "No Plan Cache Counters on $Computer"
            }
            <# DO NOT use Write-Message as this is inside of a script block #>
            Write-Verbose -Message "Searching for Buffer Manager Counters on $Computer"
            try {
                $availableCounters = (Get-Counter -ListSet "*Buffer Manager*" -ErrorAction SilentlyContinue).paths
                (Get-Counter -Counter $availableCounters -ErrorAction SilentlyContinue).countersamples | Where-Object { $_.Path -match $BufferCounterRegex } | ForEach-Object {
                    $instance = (($_.Path.split("\")[-2]).replace("mssql`$", "")).split(':')[0]
                    if ($instance -eq 'sqlserver') { $instance = 'mssqlserver' }
                    [PSCustomObject]@{
                        ComputerName    = $env:computername
                        SqlInstance     = $instance
                        CounterInstance = (($_.Path.split("\")[-2]).replace("mssql`$", "")).split(':')[1]
                        Counter         = $_.Path.split("\")[-1]
                        Pages           = $_.cookedvalue
                        Memory          = $_.cookedvalue * 8192 / 1048576.0
                    }
                }
            } catch {
                <# DO NOT use Write-Message as this is inside of a script block #>
                Write-Verbose -Message "No Buffer Manager Counters on $Computer"
            }
            <# DO NOT use Write-Message as this is inside of a script block #>
            Write-Verbose -Message "Searching for SSAS Counters on $Computer"
            try {
                $availableCounters = (Get-Counter -ListSet "MSAS*:Memory" -ErrorAction SilentlyContinue).paths
                (Get-Counter -Counter $availableCounters -ErrorAction SilentlyContinue).countersamples | Where-Object { $_.Path -match $SSASCounterRegex } | ForEach-Object {
                    $instance = (($_.Path.split("\")[-2]).replace("mssql`$", "")).split(':')[0]
                    if ($instance -eq 'sqlserver') { $instance = 'mssqlserver' }
                    [PSCustomObject]@{
                        ComputerName    = $env:COMPUTERNAME
                        SqlInstance     = $instance
                        CounterInstance = (($_.Path.split("\")[-2]).replace("mssql`$", "")).split(':')[1]
                        Counter         = $_.Path.split("\")[-1]
                        Pages           = $null
                        Memory          = $_.cookedvalue / 1024
                    }
                }
            } catch {
                <# DO NOT use Write-Message as this is inside of a script block #>
                Write-Verbose -Message "No SSAS Counters on $Computer"
            }
            <# DO NOT use Write-Message as this is inside of a script block #>
            Write-Verbose -Message "Searching for SSIS Counters on $Computer"
            try {
                $availableCounters = (Get-Counter -ListSet "*SSIS*" -ErrorAction SilentlyContinue).paths
                (Get-Counter -Counter $availableCounters -ErrorAction SilentlyContinue).countersamples | Where-Object { $_.Path -match $SSISCounterRegex } | ForEach-Object {
                    $instance = (($_.Path.split("\")[-2]).replace("mssql`$", "")).split(':')[0]
                    if ($instance -eq 'sqlserver') { $instance = 'mssqlserver' }
                    [PSCustomObject]@{
                        ComputerName    = $env:computername
                        SqlInstance     = $instance
                        CounterInstance = (($_.Path.split("\")[-2]).replace("mssql`$", "")).split(':')[1]
                        Counter         = $_.Path.split("\")[-1]
                        Pages           = $null
                        Memory          = $_.cookedvalue / 1024 / 1024
                    }
                }
            } catch {
                <# DO NOT use Write-Message as this is inside of a script block #>
                Write-Verbose -Message "No SSIS Counters on $Computer"
            }
        }
    Invoke-Command2 -ComputerName $__computer -Credential $Credential -ScriptBlock $scriptBlock -argumentlist $MemoryCounterRegex, $PlanCounterRegex, $BufferCounterRegex, $SSASCounterRegex, $SSISCounterRegex
} $__computer $Credential $MemoryCounterRegex $PlanCounterRegex $BufferCounterRegex $SSASCounterRegex $SSISCounterRegex $__boundVerbose $__boundDebug 3>&1
""";
}
