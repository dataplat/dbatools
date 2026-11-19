#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Reports network interface activity via CIM. Port of
/// public/Get-DbaNetworkActivity.ps1 (W1-084). Quirks preserved: the begin block MUTATES
/// $ComputerName (split "\\" [0] + case-sensitive Select -Unique) but PIPELINE records
/// re-bind the parameter RAW, bypassing the mutation; the DCom session option builds once
/// in begin; per computer the Resolve-DbaNetworkName hop (no -ErrorAction) gates on
/// FullComputerName, the WSMan New-CimSession falls back to DCom (both engine hops
/// WITHOUT the verbose carrier - the W1-051 provider law), and the NIC block rides ONE
/// verbatim hop: Get-CimInstance + the two ScriptProperty Add-Members (the UNBOUND
/// { $computer } closure and the "Bandwith" TYPO property that the 'Bandwidth' display
/// column never finds) + the per-NIC Select-DefaultView with the 'Name as NIC' rename.
/// Surface pinned by migration/baselines/Get-DbaNetworkActivity.json.
/// </summary>
[Cmdlet(VerbsCommon.Get, "DbaNetworkActivity")]
public sealed class GetDbaNetworkActivityCommand : DbaBaseCmdlet
{
    /// <summary>The target computer(s); defaults to the local computer.</summary>
    [Parameter(ValueFromPipeline = true, Position = 0)]
    [Alias("cn", "host", "Server")]
    public string[]? ComputerName { get; set; } = BuildDefaultComputerName();

    private static string[]? BuildDefaultComputerName()
    {
        string? name = Environment.GetEnvironmentVariable("COMPUTERNAME");
        if (string.IsNullOrEmpty(name))
            return null;
        return new string[] { name! };
    }

    /// <summary>Windows credential for the CIM sessions.</summary>
    [Parameter(Position = 1)]
    public PSCredential? Credential { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    private object? _beginBound;
    private List<string> _mutatedNames = new List<string>();
    private object? _sessionOption;

    protected override void BeginProcessing()
    {
        // PS: $ComputerName = $ComputerName | ForEach-Object { $_.split("\")[0] } |
        // Select-Object -Unique - runs ONCE against the named/default binding.
        _beginBound = ComputerName;
        List<string> seen = new List<string>();
        foreach (string? name in ComputerName ?? new string[0])
        {
            if (name is null)
                continue;
            string head = name.Split('\\')[0];
            bool exists = false;
            foreach (string prior in seen)
            {
                if (string.Equals(prior, head, StringComparison.Ordinal))
                {
                    exists = true;
                    break;
                }
            }
            if (!exists)
                seen.Add(head);
        }
        _mutatedNames = seen;

        _sessionOption = PipelineValue(NestedCommand.InvokeScoped(this, NewSessionOptionScript));
    }

    protected override void ProcessRecord()
    {
        // PS: a pipeline record RE-BINDS $ComputerName raw, bypassing the begin
        // mutation - and the function iterates the array DIRECTLY, so null elements
        // iterate too (Resolve runs with null and the "can't connect" warn fires).
        List<string?> names;
        if (ReferenceEquals(ComputerName, _beginBound))
        {
            names = new List<string?>(_mutatedNames);
        }
        else
        {
            names = new List<string?>();
            foreach (string? name in ComputerName ?? new string[0])
                names.Add(name);
        }

        foreach (string? computer in names)
        {
            object? server = PipelineValue(NestedCommand.InvokeScoped(this, ResolveScript, computer, Credential, BoundVerbose(), BoundDebug()));
            object? fullName = DotAccess(server, "FullComputerName");
            if (LanguagePrimitives.IsTrue(fullName))
            {
                string resolved = PsText(fullName);
                WriteMessage(MessageLevel.Verbose, "Creating CIMSession on " + resolved + " over WSMan");
                object? cimSession = PipelineValue(NestedCommand.InvokeScoped(this, NewWsmanSessionScript, resolved, Credential));
                if (!LanguagePrimitives.IsTrue(cimSession))
                {
                    WriteMessage(MessageLevel.Verbose, "Creating CIMSession on " + resolved + " over WSMan failed. Creating CIMSession on " + resolved + " over DCom");
                    cimSession = PipelineValue(NestedCommand.InvokeScoped(this, NewDcomSessionScript, resolved, _sessionOption, Credential));
                }
                if (LanguagePrimitives.IsTrue(cimSession))
                {
                    WriteMessage(MessageLevel.Verbose, "Getting properties for Network Interfaces on " + resolved);
                    try
                    {
                        foreach (PSObject? item in NestedCommand.InvokeScoped(this, GetNicsScript, cimSession, resolved))
                            WriteObject(item);
                    }
                    catch (PipelineStoppedException)
                    {
                        throw;
                    }
                    catch (RuntimeException ex)
                    {
                        StatementFault.Surface(this, ex, "Get-DbaNetworkActivity");
                    }
                }
                else
                {
                    WriteMessage(MessageLevel.Warning, "Can't create CIMSession on " + resolved);
                }
            }
            else
            {
                WriteMessage(MessageLevel.Warning, "can't connect to " + PsText(computer));
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

    /// <summary>The PS dot operator (ETS-first single-object reads).</summary>
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

    /// <summary>A bound -Debug carrier for the dbatools hops (W1-044 convention).</summary>
    private object? BoundDebug()
    {
        object? debug;
        if (MyInvocation.BoundParameters.TryGetValue("Debug", out debug))
            return LanguagePrimitives.IsTrue(debug);
        return null;
    }

    /// <summary>A bound -Verbose carrier for the dbatools hops (W1-044 convention).</summary>
    private object? BoundVerbose()
    {
        object? verbose;
        if (MyInvocation.BoundParameters.TryGetValue("Verbose", out verbose))
            return LanguagePrimitives.IsTrue(verbose);
        return null;
    }

    // PS begin: $sessionoption = New-CimSessionOption -Protocol DCom (engine hop, no carrier).
    private const string NewSessionOptionScript = """
New-CimSessionOption -Protocol DCom
""";

    // PS: Resolve-DbaNetworkName (dbatools hop with the verbose carrier, no -ErrorAction).
    private const string ResolveScript = """
param($__computer, $Credential, $__boundVerbose, $__boundDebug)
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    param($__computer, $Credential, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundVerbose) { $VerbosePreference = $(if ($__boundVerbose) { "Continue" } else { "SilentlyContinue" }) }
    if ($null -ne $__boundDebug) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }
    Resolve-DbaNetworkName -ComputerName $__computer -Credential $Credential
} $__computer $Credential $__boundVerbose $__boundDebug 3>&1
""";

    // PS: New-CimSession over WSMan (engine hop, -ErrorAction SilentlyContinue verbatim).
    private const string NewWsmanSessionScript = """
param($__computer, $Credential)
New-CimSession -ComputerName $__computer -ErrorAction SilentlyContinue -Credential $Credential
""";

    // PS: New-CimSession over DCom (engine hop).
    private const string NewDcomSessionScript = """
param($__computer, $__sessionOption, $Credential)
New-CimSession -ComputerName $__computer -SessionOption $__sessionOption -ErrorAction SilentlyContinue -Credential $Credential
""";

    // PS: the NIC fetch + ScriptProperty decoration + per-NIC Select-DefaultView, VERBATIM
    // (the UNBOUND { $computer } closure and the "Bandwith" typo included).
    private const string GetNicsScript = """
param($CIMSession, $computer)
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    param($CIMSession, $computer)
    $NICs = Get-CimInstance -CimSession $CIMSession -ClassName Win32_PerfFormattedData_Tcpip_NetworkInterface
    $NICs | Add-Member -Force -MemberType ScriptProperty -Name ComputerName -Value { $computer }
    $NICs | Add-Member -Force -MemberType ScriptProperty -Name Bandwith -Value { switch ( $this.CurrentBandWidth ) { 10000000000 { '10Gb' } 1000000000 { '1Gb' } 100000000 { '100Mb' } 10000000 { '10Mb' } 1000000 { '1Mb' } 100000 { '100Kb' } default { 'Low' } } }
    foreach ( $NIC in $NICs ) { Select-DefaultView -InputObject $NIC -Property 'ComputerName', 'Name as NIC', 'BytesReceivedPersec', 'BytesSentPersec', 'BytesTotalPersec', 'Bandwidth' }
} $CIMSession $computer 3>&1
""";
}
