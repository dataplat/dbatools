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
/// Lists available performance counters from the Perflib registry. Port of
/// public/Get-DbaPfAvailableCounter.ps1 (W1-087). The begin-block SCRIPTBLOCK rides the
/// hop VERBATIM (its Credential = $args array quirk and the '[0-90000]' filter class
/// included) together with the Invoke-Command2 pipe and the pattern/no-pattern split
/// (Where-Object Name -match is case-insensitive; Select-DefaultView excludes
/// Credential); the begin block mutates the (empty-string-defaulted) -Pattern with the
/// like-to-regex Replace pair; the catch is Stop-Function "Failure" -Continue.
/// Surface pinned by migration/baselines/Get-DbaPfAvailableCounter.json.
/// </summary>
[Cmdlet(VerbsCommon.Get, "DbaPfAvailableCounter")]
public sealed class GetDbaPfAvailableCounterCommand : DbaBaseCmdlet
{
    /// <summary>The target computer(s); defaults to the local computer.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? ComputerName { get; set; } = BuildDefaultComputerName();

    private static DbaInstanceParameter[]? BuildDefaultComputerName()
    {
        string? name = Environment.GetEnvironmentVariable("COMPUTERNAME");
        if (string.IsNullOrEmpty(name))
            return null;
        return new DbaInstanceParameter[] { new DbaInstanceParameter(name) };
    }

    /// <summary>Windows credential for the remote read.</summary>
    [Parameter(Position = 1)]
    public PSCredential? Credential { get; set; }

    /// <summary>Counter name filter (wildcards convert to regex).</summary>
    [Parameter(Position = 2)]
    public string Pattern { get; set; } = "";

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    private string _pattern = "";

    protected override void BeginProcessing()
    {
        // PS: $Pattern = $Pattern.Replace("*", ".*").Replace("..*", ".*") - the
        // string-typed parameter reads "" when unbound, so this never faults.
        _pattern = Pattern.Replace("*", ".*").Replace("..*", ".*");
    }

    protected override void ProcessRecord()
    {
        foreach (DbaInstanceParameter? computer in ComputerName ?? new DbaInstanceParameter[0])
        {
            try
            {
                bool hasPattern = LanguagePrimitives.IsTrue(_pattern);
                foreach (PSObject? item in NestedCommand.InvokeScoped(this, InvokeScript, computer, Credential, _pattern, hasPattern, BoundVerbose(), BoundDebug()))
                    WriteObject(item);
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch (Exception ex)
            {
                StopFunction("Failure", target: computer, errorRecord: StatementFault.Record(ex, "Get-DbaPfAvailableCounter"), continueLoop: true);
                continue;
            }
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

    // PS: the begin-block scriptblock VERBATIM + the Invoke-Command2 pipe split.
    private const string InvokeScript = """
param($__computer, $Credential, $pattern, $__hasPattern, $__boundVerbose, $__boundDebug)
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    param($__computer, $Credential, $pattern, $__hasPattern, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundVerbose) { $VerbosePreference = $(if ($__boundVerbose) { "Continue" } else { "SilentlyContinue" }) }
    if ($null -ne $__boundDebug) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }
        $scriptBlock = {
            $counters = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Perflib\009' -Name 'counter' | Select-Object -ExpandProperty Counter |
            Where-Object { $_ -notmatch '[0-90000]' } | Sort-Object | Get-Unique

        foreach ($counter in $counters) {
            [PSCustomObject]@{
                ComputerName = $env:COMPUTERNAME
                Name         = $counter
                Credential   = $args
            }
        }
    }
    if ($__hasPattern) {
        Invoke-Command2 -ComputerName $__computer -Credential $Credential -ScriptBlock $scriptBlock -ArgumentList $credential -ErrorAction Stop |
            Where-Object Name -match $pattern | Select-DefaultView -ExcludeProperty Credential
    } else {
        Invoke-Command2 -ComputerName $__computer -Credential $Credential -ScriptBlock $scriptBlock -ArgumentList $credential -ErrorAction Stop |
            Select-DefaultView -ExcludeProperty Credential
    }
} $__computer $Credential $pattern $__hasPattern $__boundVerbose $__boundDebug 3>&1
""";
}
