#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Lists OS processes spawned by SQL Server. Port of public/Get-DbaExternalProcess.ps1
/// (W1-077). Both Get-DbaCmObject fetch statements ride module hops VERBATIM (the
/// Where-Object filters and the parenthesized-pipe .ProcessId member-enumeration
/// included, with the RAW DbaInstanceParameter passed as -ComputerName); the process
/// loop projects DotAccess reads (Credential and the raw CIM object included) through
/// the per-item Select-DefaultView hop; the whole body sits INSIDE the function's own
/// try - any fault lands in the catch's Stop-Function "Failure for computer" -Continue.
/// Surface pinned by migration/baselines/Get-DbaExternalProcess.json.
/// </summary>
[Cmdlet(VerbsCommon.Get, "DbaExternalProcess")]
public sealed class GetDbaExternalProcessCommand : DbaBaseCmdlet
{
    /// <summary>The target computer(s).</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public DbaInstanceParameter[] ComputerName { get; set; } = null!;

    /// <summary>Windows credential for the CIM queries.</summary>
    [Parameter(Position = 1)]
    public PSCredential? Credential { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    protected override void ProcessRecord()
    {
        foreach (DbaInstanceParameter computer in ComputerName)
        {
            try
            {
                object? sqlPid = PipelineValue(NestedCommand.InvokeScoped(this, GetSqlPidScript, computer, Credential, BoundVerbose(), BoundDebug()));
                object? processes = PipelineValue(NestedCommand.InvokeScoped(this, GetChildProcessesScript, computer, Credential, sqlPid, BoundVerbose(), BoundDebug()));

                foreach (object? process in EnumerateValue(processes))
                {
                    PSObject result = new PSObject();
                    result.Properties.Add(new PSNoteProperty("ComputerName", computer));
                    result.Properties.Add(new PSNoteProperty("Credential", Credential));
                    result.Properties.Add(new PSNoteProperty("ProcessId", DotAccess(process, "ProcessId")));
                    result.Properties.Add(new PSNoteProperty("Name", DotAccess(process, "Name")));
                    result.Properties.Add(new PSNoteProperty("HandleCount", DotAccess(process, "HandleCount")));
                    result.Properties.Add(new PSNoteProperty("WorkingSetSize", DotAccess(process, "WorkingSetSize")));
                    result.Properties.Add(new PSNoteProperty("VirtualSize", DotAccess(process, "VirtualSize")));
                    result.Properties.Add(new PSNoteProperty("CimObject", process is PSObject processPso ? processPso.BaseObject : process));

                    foreach (PSObject? shaped in NestedCommand.InvokeScoped(this, SelectDefaultViewScript, result))
                        WriteObject(shaped);
                }
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch (Exception ex)
            {
                StopFunction("Failure for " + PsText(computer), errorRecord: StatementFault.Record(ex, "Get-DbaExternalProcess"), continueLoop: true);
                continue;
            }
        }
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

    /// <summary>The PS dot operator (raw CIM property reads).</summary>
    private static object? DotAccess(object? item, string name)
    {
        if (item is null)
            return null;
        PSObject wrapped = PSObject.AsPSObject(item);
        PSPropertyInfo? direct = wrapped.Properties[name];
        if (direct is null)
            return null;
        object? value;
        try { value = direct.Value; }
        catch { return null; }
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

    // PS: the sqlservr pid fetch VERBATIM (parenthesized pipe + .ProcessId member enum).
    private const string GetSqlPidScript = """
param($__computer, $Credential, $__boundVerbose, $__boundDebug)
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    param($__computer, $Credential, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundVerbose) { $VerbosePreference = $(if ($__boundVerbose) { "Continue" } else { "SilentlyContinue" }) }
    if ($null -ne $__boundDebug) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }
    (Get-DbaCmObject -ComputerName $__computer -Credential $Credential -ClassName win32_process | Where-Object ProcessName -eq "sqlservr.exe").ProcessId
} $__computer $Credential $__boundVerbose $__boundDebug 3>&1
""";

    // PS: the child-process fetch VERBATIM (ParentProcessId -in $sqlpid).
    private const string GetChildProcessesScript = """
param($__computer, $Credential, $__sqlpid, $__boundVerbose, $__boundDebug)
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    param($__computer, $Credential, $__sqlpid, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundVerbose) { $VerbosePreference = $(if ($__boundVerbose) { "Continue" } else { "SilentlyContinue" }) }
    if ($null -ne $__boundDebug) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }
    Get-DbaCmObject -ComputerName $__computer -Credential $Credential -ClassName win32_process | Where-Object ParentProcessId -in $__sqlpid
} $__computer $Credential $__sqlpid $__boundVerbose $__boundDebug 3>&1
""";

    private const string SelectDefaultViewScript = """
param($__process)
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    param($__process)
    Select-DefaultView -InputObject $__process -Property ComputerName, ProcessId, Name, HandleCount, WorkingSetSize, VirtualSize, CimObject
} $__process 3>&1
""";
}
