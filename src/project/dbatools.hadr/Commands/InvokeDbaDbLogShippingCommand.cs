#nullable enable

using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Sets up log shipping from a source database to one or more secondaries: backup,
/// copy and restore jobs, schedules, monitor configuration and optional seeding.
/// Port of public/Invoke-DbaDbLogShipping.ps1; surface pinned by
/// migration/baselines/Invoke-DbaDbLogShipping.json. Parameters live in the
/// .Parameters partial; the begin/process scripts in the .BeginScript*/.ProcessScript*
/// partials.
/// </summary>
[Cmdlet(VerbsLifecycle.Invoke, "DbaDbLogShipping", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
public sealed partial class InvokeDbaDbLogShippingCommand : DbaBaseCmdlet
{
    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // The begin hop's 47-variable carry (40 default-mutated params + 7 begin locals,
    // AST-inventoried) plus the begin-latch flag; ProcessRecord re-injects the carry
    // and merges each hop's reported interrupt into _hopInterrupted (the source's
    // process-top Test-FunctionInterrupt reads the fn-scope flag that begin's 28
    // plain validation Stop-Function sites and process's 10 plain sites latch).
    private Hashtable? _state;
    private bool _hopInterrupted;

    protected override void BeginProcessing()
    {
        // W3-102 CONTINUE RELAY on the BEGIN hop: the source's line-692
        // `Stop-Function ... -Continue` is loop-less in begin (it fires when Database
        // arrives via pipeline, since begin runs before pipeline binding) - the escape
        // must abort the caller's pipeline exactly like the function world.
        object continueMarker = new object();
        bool continueEscaped = false;
        foreach (PSObject? item in NestedCommand.InvokeScoped(this, BeginScript,
            BuildParameterTable(), ExactlyOneSharedOrAzure(), continueMarker,
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
        {
            if (ReferenceEquals(item?.BaseObject, continueMarker))
            {
                continueEscaped = true;
                continue;
            }
            if (DrainSentinelOrError(item))
            {
                continue;
            }
            WriteObject(item);
        }
        if (continueEscaped)
        {
            NestedCommand.InvokeScoped(this, ContinueScript);
        }
    }

    protected override void ProcessRecord()
    {
        if (Interrupted || _hopInterrupted)
        {
            return;
        }

        // [DEF-001] closed via InvokeScopedStreaming (ab7492c). Streaming changes -WhatIf transcript
        // capture (documented observability change, not behaviour); the parity runner strips the
        // transcript gate-message. Fleet-confirmed non-blocker (C's streamed ShouldProcess wave, MSTest 487/487).
        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (DrainSentinelOrError(item))
            {
                return;
            }
            WriteObject(item);
        }, ProcessScript,
            BuildParameterTable(), _state,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    protected override void EndProcessing()
    {
        // The source END block has NO Test-FunctionInterrupt guard - its verbose
        // "Finished..." message emits even after a begin/process latch (codex r2), so
        // only the native Interrupted flag gates here, never _hopInterrupted.
        if (Interrupted)
        {
            return;
        }

        foreach (PSObject? item in NestedCommand.InvokeScoped(this, EndScript,
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
        {
            if (DrainSentinelOrError(item))
            {
                continue;
            }
            WriteObject(item);
        }
    }

    private bool ExactlyOneSharedOrAzure()
    {
        int bound = (TestBound(nameof(SharedPath)) ? 1 : 0) + (TestBound(nameof(AzureBaseUrl)) ? 1 : 0);
        return bound == 1;
    }

    private bool DrainSentinelOrError(PSObject? item)
    {
        if (item?.BaseObject is Hashtable sentinel && sentinel.ContainsKey("__w4038State"))
        {
            _state = sentinel["__w4038State"] as Hashtable;
            if (_state is not null && _state["interrupted"] is bool interrupted && interrupted)
            {
                _hopInterrupted = true;
            }
            return true;
        }
        if (item?.BaseObject is ErrorRecord nestedError)
        {
            NestedCommand.RemoveDuplicateError(this, nestedError);
            WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
            return true;
        }
        return false;
    }

    // PS: the engine-authored `continue` for the begin relay above.
    private const string ContinueScript = """
continue
""";

    // PS: the end block VERBATIM (single Write-Message + append).
    private const string EndScript = """
param($__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param($__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

        Write-Message -Message "Finished setting up log shipping." -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"
} $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";

    // ONLY the caller-bound parameters ride the splat (minus engine common
    // parameters, which travel separately via @__commonParameters): the source reads
    // $PSBoundParameters.ContainsKey("AzureBaseUrl") at line 627 and truthiness-gates
    // several params - splatting all 84 values would make every key count as bound.
    // The typed inner param blocks give unbound parameters their function-world
    // defaults exactly.
    private static readonly System.Collections.Generic.HashSet<string> CommonParameterNames =
        new System.Collections.Generic.HashSet<string>(System.StringComparer.OrdinalIgnoreCase)
        {
            "Verbose", "Debug", "ErrorAction", "WarningAction", "InformationAction", "ProgressAction",
            "ErrorVariable", "WarningVariable", "InformationVariable", "OutVariable", "OutBuffer",
            "PipelineVariable", "WhatIf", "Confirm"
        };

    private Hashtable BuildParameterTable()
    {
        Hashtable parameters = new Hashtable(System.StringComparer.OrdinalIgnoreCase);
        foreach (System.Collections.Generic.KeyValuePair<string, object> bound in MyInvocation.BoundParameters)
        {
            if (!CommonParameterNames.Contains(bound.Key))
            {
                parameters[bound.Key] = bound.Value;
            }
        }
        return parameters;
    }
}
