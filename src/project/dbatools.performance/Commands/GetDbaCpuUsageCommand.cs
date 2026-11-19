#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Data;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Parameter;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Correlates sqlservr thread CPU counters with SPIDs. Port of
/// public/Get-DbaCpuUsage.ps1 (W1-060). The Get-DbaProcess and Get-DbaCmObject fetch
/// statements ride module hops VERBATIM (the CIM filter scriptblock included, its
/// $Threshold read bound in the hop scope); the version-split SPID map rides the
/// Server.Query ETS hop; the thread loop decorates the CIM instances with the nine
/// Add-Member notes (member-enumeration projections for the spid/process/Processes
/// lookups) and emits through a per-thread Select-DefaultView hop. The thread-state and
/// wait-reason tables model the property-bag-by-int lookups ($bag.$int converts the key
/// to its string name; a miss reads null). Surface pinned by
/// migration/baselines/Get-DbaCpuUsage.json.
/// </summary>
[Cmdlet(VerbsCommon.Get, "DbaCpuUsage")]
public sealed class GetDbaCpuUsageCommand : DbaInstanceCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public override DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public override PSCredential? SqlCredential { get; set; }

    /// <summary>Windows credential for the CIM query.</summary>
    [Parameter(Position = 2)]
    public PSCredential? Credential { get; set; }

    /// <summary>Minimum PercentProcessorTime to include.</summary>
    [Parameter(Position = 3)]
    public int Threshold { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    private static readonly Dictionary<string, string> ThreadStates = new Dictionary<string, string>
    {
        { "0", "Initialized. It is recognized by the microkernel." },
        { "1", "Ready. It is prepared to run on the next available processor." },
        { "2", "Running. It is executing." },
        { "3", "Standby. It is about to run. Only one thread may be in this state at a time." },
        { "4", "Terminated. It is finished executing." },
        { "5", "Waiting. It is not ready for the processor. When ready, it will be rescheduled." },
        { "6", "Transition. The thread is waiting for resources other than the processor." },
        { "7", "Unknown. The thread state is unknown." },
    };

    private static readonly Dictionary<string, string> ThreadWaitReasons = new Dictionary<string, string>
    {
        { "0", "Executive" }, { "1", "FreePage" }, { "2", "PageIn" }, { "3", "PoolAllocation" },
        { "4", "ExecutionDelay" }, { "5", "FreePage" }, { "6", "PageIn" }, { "7", "Executive" },
        { "8", "FreePage" }, { "9", "PageIn" }, { "10", "PoolAllocation" }, { "11", "ExecutionDelay" },
        { "12", "FreePage" }, { "13", "PageIn" }, { "14", "EventPairHigh" }, { "15", "EventPairLow" },
        { "16", "LPCReceive" }, { "17", "LPCReply" }, { "18", "VirtualMemory" }, { "19", "PageOut" },
        { "20", "Unknown" },
    };

    // PS: process-block locals persist across loop iterations and pipeline blocks; a
    // faulted fetch statement keeps the previous value (stale-value law, W1-056 shape).
    private Collection<PSObject> _processes = new Collection<PSObject>();
    private Collection<PSObject> _threads = new Collection<PSObject>();
    private Collection<PSObject> _spidCollection = new Collection<PSObject>();

    protected override void ProcessRecord()
    {
        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            Hashtable connectParams = new Hashtable();
            connectParams["SqlInstance"] = instance;
            connectParams["SqlCredential"] = SqlCredential;
            NestedConnect.Outcome connection = NestedConnect.Connect(this, connectParams);
            if (!connection.Ok)
            {
                StopFunction("Failure", target: instance, errorRecord: connection.Failure, category: ErrorCategory.ConnectionError, continueLoop: true);
                continue;
            }
            Server server = connection.Server!;

            // PS: $processes = Get-DbaProcess -SqlInstance $server (statement-conditional)
            try
            {
                _processes = NestedCommand.InvokeScoped(this, GetProcessesScript, server, BoundVerbose(), BoundDebug());
            }
            catch (PipelineStoppedException) { throw; }
            catch (RuntimeException ex) { StatementFault.Surface(this, ex, "Get-DbaCpuUsage"); }

            // PS: $threads = Get-DbaCmObject ... | Where-Object { sql* and >= $Threshold }
            try
            {
                _threads = NestedCommand.InvokeScoped(this, GetThreadsScript, instance.ComputerName, Credential, Threshold, BoundVerbose(), BoundDebug());
            }
            catch (PipelineStoppedException) { throw; }
            catch (RuntimeException ex) { StatementFault.Surface(this, ex, "Get-DbaCpuUsage"); }

            // PS: version-split SPID map via $server.Query(...)
            string spidQuery = server.VersionMajor == 8
                ? "SELECT spid, kpid FROM sysprocesses"
                : @"SELECT t.os_thread_id AS kpid, s.session_id AS spid
            FROM sys.dm_exec_sessions s
            JOIN sys.dm_exec_requests er ON s.session_id = er.session_id
            JOIN sys.dm_os_workers w ON er.task_address = w.task_address
            JOIN sys.dm_os_threads t ON w.thread_address = t.thread_address";
            try
            {
                _spidCollection = NestedCommand.InvokeScoped(this, ServerQueryScript, server, spidQuery);
            }
            catch (PipelineStoppedException) { throw; }
            catch (RuntimeException ex) { StatementFault.Surface(this, ex, "Get-DbaCpuUsage"); }

            foreach (PSObject? thread in _threads)
            {
                if (thread is null)
                    continue;

                // PS: $spid = ($spidcollection | Where-Object kpid -eq $thread.IDThread).spid
                object? idThread = DotAccess(thread, "IDThread");
                object? spid = ProjectMemberValues(FilterByProperty(_spidCollection, "kpid", idThread), "spid");

                // PS: $process = $processes | Where-Object spid -eq $spid
                object? process = ProjectMatches(FilterByProperty(_processes, "spid", spid));

                object? threadWaitReason = DotAccess(thread, "ThreadWaitReason");
                object? threadState = DotAccess(thread, "ThreadState");
                string? stateValue;
                ThreadStates.TryGetValue(KeyText(threadState), out stateValue);
                string? waitValue;
                ThreadWaitReasons.TryGetValue(KeyText(threadWaitReason), out waitValue);

                SetNote(thread, "ComputerName", SmoServerExtensions.GetComputerName(server));
                SetNote(thread, "InstanceName", server.ServiceName);
                SetNote(thread, "SqlInstance", SmoServerExtensions.GetDomainInstanceName(server));
                SetNote(thread, "Processes", ProjectMatches(FilterByProperty(_processes, "HostProcessID", DotAccess(thread, "IDProcess"))));
                SetNote(thread, "ThreadStateValue", stateValue);
                SetNote(thread, "ThreadWaitReasonValue", waitValue);
                SetNote(thread, "Process", process);
                SetNote(thread, "Query", DotAccess(process, "LastQuery"));
                SetNote(thread, "Spid", spid);

                try
                {
                    foreach (PSObject? item in NestedCommand.InvokeScoped(this, SelectDefaultViewScript, thread))
                        WriteObject(item);
                }
                catch (PipelineStoppedException) { throw; }
                catch (RuntimeException ex) { StatementFault.Surface(this, ex, "Get-DbaCpuUsage"); }
            }
        }
    }

    /// <summary>PS: $bag.$intKey - the int converts to its string property name.</summary>
    private static string KeyText(object? key)
    {
        if (key is null)
            return "";
        return (string)LanguagePrimitives.ConvertTo(key, typeof(string), CultureInfo.InvariantCulture);
    }

    /// <summary>Where-Object Prop -eq value over a collection.</summary>
    private static List<object?> FilterByProperty(Collection<PSObject> items, string property, object? value)
    {
        List<object?> matched = new List<object?>();
        foreach (PSObject? item in items)
        {
            if (item is null)
                continue;
            if (PsOps.Eq(DotAccess(item, property), value))
                matched.Add(item);
        }
        return matched;
    }

    /// <summary>The PS filter-result projection: empty = null, one = scalar, many = array.</summary>
    private static object? ProjectMatches(List<object?> matches)
    {
        if (matches.Count == 0)
            return null;
        if (matches.Count == 1)
            return matches[0];
        return matches.ToArray();
    }

    /// <summary>The .spid read over the filter result: ONE match is plain property access
    /// (a nested collection stays nested); 2+ matches member-enumerate - collection values
    /// FLATTEN one level and a singleton total unwraps to scalar.</summary>
    private static object? ProjectMemberValues(List<object?> matches, string property)
    {
        if (matches.Count == 0)
            return null;
        if (matches.Count == 1)
            return DotAccess(matches[0], property);
        List<object?> collected = new List<object?>();
        foreach (object? match in matches)
        {
            object? value = DotAccess(match, property);
            if (value is not string && LanguagePrimitives.GetEnumerable(value) is IEnumerable elements)
            {
                foreach (object? element in elements)
                    collected.Add(UnwrapTransit(element));
            }
            else
            {
                collected.Add(value);
            }
        }
        if (collected.Count == 0)
            return null;
        if (collected.Count == 1)
            return collected[0];
        return collected.ToArray();
    }

    /// <summary>Add-Member -Force NoteProperty: an existing INSTANCE member is removed and
    /// the note re-appends at the END (an adapted property is shadowed, never assigned).</summary>
    private static void SetNote(PSObject target, string name, object? value)
    {
        PSPropertyInfo? existing = target.Properties[name];
        if (existing is not null && existing.IsInstance)
            target.Properties.Remove(name);
        target.Properties.Add(new PSNoteProperty(name, value));
    }

    /// <summary>The PS dot operator with member-enumeration semantics (W1-044 shape).</summary>
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

    private const string GetProcessesScript = """
param($server, $__boundVerbose, $__boundDebug)
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    param($server, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundVerbose) { $VerbosePreference = $(if ($__boundVerbose) { "Continue" } else { "SilentlyContinue" }) }
    if ($null -ne $__boundDebug) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }
    Get-DbaProcess -SqlInstance $server
} $server $__boundVerbose $__boundDebug 3>&1
""";

    private const string GetThreadsScript = """
param($__computerName, $Credential, $Threshold, $__boundVerbose, $__boundDebug)
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    param($__computerName, $Credential, $Threshold, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundVerbose) { $VerbosePreference = $(if ($__boundVerbose) { "Continue" } else { "SilentlyContinue" }) }
    if ($null -ne $__boundDebug) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }
    Get-DbaCmObject -ComputerName $__computerName -ClassName Win32_PerfFormattedData_PerfProc_Thread -Credential $Credential | Where-Object { $_.Name -like "sql*" -and $_.PercentProcessorTime -ge $Threshold }
} $__computerName $Credential $Threshold $__boundVerbose $__boundDebug 3>&1
""";

    private const string ServerQueryScript = """
param($server, $query)
$server.Query($query)
""";

    private const string SelectDefaultViewScript = """
param($__thread)
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    param($__thread)
    Select-DefaultView -InputObject $__thread -Property ComputerName, InstanceName, SqlInstance, Name, ContextSwitchesPersec, ElapsedTime, IDProcess, Spid, PercentPrivilegedTime, PercentProcessorTime, PercentUserTime, PriorityBase, PriorityCurrent, StartAddress, ThreadStateValue, ThreadWaitReasonValue, Process, Query
} $__thread 3>&1
""";
}
