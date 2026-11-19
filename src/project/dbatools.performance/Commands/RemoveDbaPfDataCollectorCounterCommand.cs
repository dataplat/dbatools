#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Removes performance counters from PLA data collectors. Port of
/// public/Remove-DbaPfDataCollectorCounter.ps1 (W1-114). The W1-089 input scaffold is
/// preserved: InputObject re-binds fresh per pipeline record, its Credential is adopted
/// with typed coercion when -Credential is unbound, and the refetch gate appends
/// Get-DbaPfDataCollectorCounter output per ComputerName. The whole mutation loop then
/// rides one VERBATIM module-scoped hop because the source deliberately loops `$object`
/// while reading the WHOLE `$InputObject` for every field; that also preserves the XML
/// adapter calls, last-$countername behavior, Test-ElevationRequirement flow, PLA commit
/// scriptblock, ShouldProcess text, verbose result, stale locals, and output shape.
/// Surface pinned by migration/baselines/Remove-DbaPfDataCollectorCounter.json.
/// </summary>
[Cmdlet(VerbsCommon.Remove, "DbaPfDataCollectorCounter", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High)]
public sealed class RemoveDbaPfDataCollectorCounterCommand : DbaBaseCmdlet
{
    /// <summary>The target computer(s); defaults to the local computer.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? ComputerName { get; set; } = BuildDefaultComputerName();

    private static DbaInstanceParameter[]? BuildDefaultComputerName()
    {
        string? name = Environment.GetEnvironmentVariable("COMPUTERNAME");
        if (string.IsNullOrEmpty(name))
            return null;
        return new[] { new DbaInstanceParameter(name) };
    }

    /// <summary>Windows credential for remote operations.</summary>
    [Parameter(Position = 1)]
    public PSCredential? Credential { get; set; }

    /// <summary>The collector-set names to target.</summary>
    [Parameter(Position = 2)]
    [Alias("DataCollectorSet")]
    public string[]? CollectorSet { get; set; }

    /// <summary>The collector names to target.</summary>
    [Parameter(Position = 3)]
    [Alias("DataCollector")]
    public string[]? Collector { get; set; }

    /// <summary>The counter names to remove.</summary>
    [Parameter(Mandatory = true, ValueFromPipelineByPropertyName = true, Position = 4)]
    [Alias("Name")]
    public object[] Counter { get; set; } = null!;

    /// <summary>Counter objects piped from Get-DbaPfDataCollectorCounter.</summary>
    [Parameter(ValueFromPipeline = true, Position = 5)]
    public object[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    private object? _credential;
    private bool _credentialAdopted;
    private List<object?> _accumulated = new List<object?>();

    protected override void ProcessRecord()
    {
        // Pipeline binding re-binds InputObject fresh for every record; += growth is local
        // to that process invocation.
        _accumulated = new List<object?>();
        if (InputObject is not null)
        {
            foreach (object? item in InputObject)
                _accumulated.Add(item);
        }

        object? effectiveCredential = _credentialAdopted ? _credential : Credential;
        object? inputCredential = MemberEnum(_accumulated, "Credential");
        if (LanguagePrimitives.IsTrue(inputCredential) && !TestBound("Credential"))
        {
            try
            {
                object? coerced = LanguagePrimitives.ConvertTo(inputCredential, typeof(PSCredential), CultureInfo.InvariantCulture);
                effectiveCredential = coerced;
                _credential = coerced;
                _credentialAdopted = true;
            }
            catch (PipelineStoppedException) { throw; }
            catch (Exception ex) { StatementFault.Surface(this, ex, "Remove-DbaPfDataCollectorCounter"); }
        }

        bool haveInput = PsTruthyList(_accumulated);
        if (!haveInput || (haveInput && TestBound("ComputerName")))
        {
            foreach (DbaInstanceParameter? computer in ComputerName ?? Array.Empty<DbaInstanceParameter>())
            {
                try
                {
                    foreach (PSObject? fetched in NestedCommand.InvokeScoped(this, GetCounterScript,
                        computer, effectiveCredential, CollectorSet, Collector, Counter, BoundVerbose(), BoundDebug()))
                    {
                        _accumulated.Add(fetched);
                    }
                }
                catch (PipelineStoppedException) { throw; }
                catch (RuntimeException ex) { StatementFault.Surface(this, ex, "Remove-DbaPfDataCollectorCounter"); }
            }
        }

        if (PsTruthyList(_accumulated) && !LanguagePrimitives.IsTrue(MemberEnum(_accumulated, "CounterObject")))
        {
            StopFunction("InputObject is not of the right type. Please use Get-DbaPfDataCollectorCounter.");
            return;
        }

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
            }
            else
            {
                WriteObject(item);
            }
        }, MutationScript,
            _accumulated.ToArray(), Counter, effectiveCredential, EnableException.ToBool(),
            this, BoundVerbose(), BoundDebug());
    }

    private static bool PsTruthyList(List<object?> values)
    {
        if (values.Count == 0)
            return false;
        if (values.Count == 1)
            return LanguagePrimitives.IsTrue(values[0]);
        return true;
    }

    /// <summary>PowerShell member enumeration, including one-level collection flattening.</summary>
    private static object? MemberEnum(List<object?> items, string name)
    {
        List<object?> collected = new List<object?>();
        foreach (object? item in items)
        {
            if (item is null)
                continue;
            PSObject wrapped = PSObject.AsPSObject(item);
            PSPropertyInfo? property = wrapped.Properties[name];
            if (property is not null)
            {
                object? value;
                try { value = property.Value; }
                catch { value = null; }
                if (value is PSObject psValue && psValue.BaseObject is not PSCustomObject)
                    value = psValue.BaseObject;
                if (value is not string && LanguagePrimitives.GetEnumerable(value) is IEnumerable elements)
                {
                    foreach (object? element in elements)
                    {
                        object? unwrapped = element;
                        if (unwrapped is PSObject psElement && psElement.BaseObject is not PSCustomObject)
                            unwrapped = psElement.BaseObject;
                        collected.Add(unwrapped);
                    }
                }
                else
                {
                    collected.Add(value);
                }
            }
            else if (wrapped.BaseObject is PSCustomObject)
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

    private object? BoundDebug()
    {
        if (MyInvocation.BoundParameters.TryGetValue("Debug", out object? debug))
            return LanguagePrimitives.IsTrue(debug);
        return null;
    }

    private object? BoundVerbose()
    {
        if (MyInvocation.BoundParameters.TryGetValue("Verbose", out object? verbose))
            return LanguagePrimitives.IsTrue(verbose);
        return null;
    }

    private const string GetCounterScript = """
param($__computer, $Credential, $CollectorSet, $Collector, $Counter, $__boundVerbose, $__boundDebug)
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    param($__computer, $Credential, $CollectorSet, $Collector, $Counter, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundVerbose) { $VerbosePreference = $(if ($__boundVerbose) { "Continue" } else { "SilentlyContinue" }) }
    if ($null -ne $__boundDebug) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }
    Get-DbaPfDataCollectorCounter -ComputerName $__computer -Credential $Credential -CollectorSet $CollectorSet -Collector $Collector -Counter $Counter
} $__computer $Credential $CollectorSet $Collector $Counter $__boundVerbose $__boundDebug 3>&1
""";

    private const string MutationScript = """
param($InputObject, $Counter, $Credential, $EnableException, $__realCmdlet, $__boundVerbose, $__boundDebug)
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    param($InputObject, $Counter, $Credential, $EnableException, $__realCmdlet, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundVerbose) { $VerbosePreference = $(if ($__boundVerbose) { "Continue" } else { "SilentlyContinue" }) }
    if ($null -ne $__boundDebug) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }
    $setscript = {
        $setname = $args[0]; $removexml = $args[1]
        $CollectorSet = New-Object -ComObject Pla.DataCollectorSet
        $CollectorSet.SetXml($removexml)
        $CollectorSet.Commit($setname, $null, 0x0003) #add or modify.
        $CollectorSet.Query($setname, $Null)
    }

    # ATTRIBUTION SHIM (the W3-084 Get-PSCallStack class): Test-ElevationRequirement stamps its
    # Stop-Function with (Get-PSCallStack)[1].Command - the CALLER frame. Called bare from this hop
    # that frame is the scriptblock => [<ScriptBlock>] attribution. The named wrapper restores the
    # source's own frame; -Continue flow control unwinds through the wrapper to the foreach exactly
    # as through the source frame.
    function Remove-DbaPfDataCollectorCounter {
        param($__splat)
        Test-ElevationRequirement @__splat
    }

    foreach ($object in $InputObject) {
        $computer = $InputObject.ComputerName
        $null = Remove-DbaPfDataCollectorCounter @{ ComputerName = $computer; Continue = $true }
        $setname = $InputObject.DataCollectorSet
        $collectorname = $InputObject.DataCollector

        $xml = [xml]($InputObject.DataCollectorSetXml)

        foreach ($countername in $counter) {
            $node = $xml.SelectSingleNode("//Name[.='$collectorname']").SelectSingleNode("//Counter[.='$countername']")
            $null = $node.ParentNode.RemoveChild($node)
            $node = $xml.SelectSingleNode("//Name[.='$collectorname']").SelectSingleNode("//CounterDisplayName[.='$countername']")
            $null = $node.ParentNode.RemoveChild($node)
        }

        $plainxml = $xml.OuterXml

        if ($__realCmdlet.ShouldProcess("$computer", "Remove $countername from $collectorname with the $setname collection set")) {
            try {
                $results = Invoke-Command2 -ComputerName $computer -Credential $Credential -ScriptBlock $setscript -ArgumentList $setname, $plainxml -ErrorAction Stop -Raw
                Write-Message -Level Verbose -Message " $results" -FunctionName Remove-DbaPfDataCollectorCounter -ModuleName "dbatools"
                [PSCustomObject]@{
                    ComputerName     = $computer
                    DataCollectorSet = $setname
                    DataCollector    = $collectorname
                    Name             = $counterName
                    Status           = "Removed"
                }
            } catch {
                Stop-Function -Message "Failure importing $Countername to $computer." -ErrorRecord $_ -Target $computer -Continue -FunctionName Remove-DbaPfDataCollectorCounter
            }
        }
    }
} $InputObject $Counter $Credential $EnableException $__realCmdlet $__boundVerbose $__boundDebug 3>&1 2>&1
""";
}
