#nullable enable

using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Sets properties - owner and type - on a SQL Server endpoint.
/// Port of public/Set-DbaEndpoint.ps1; surface pinned by
/// migration/baselines/Set-DbaEndpoint.json.
/// </summary>
[Cmdlet(VerbsCommon.Set, "DbaEndpoint", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Low)]
public sealed class SetDbaEndpointCommand : DbaBaseCmdlet
{
    /// <summary>The SQL Server instance or instances hosting the endpoint.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instances using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The endpoint or endpoints to modify.</summary>
    [Parameter(Position = 2)]
    [PsStringArrayCast]
    public string[]? Endpoint { get; set; }

    /// <summary>The new owner of the endpoint.</summary>
    [Parameter(Position = 3)]
    public string? Owner { get; set; }

    /// <summary>The endpoint type.</summary>
    [Parameter(Position = 4)]
    [ValidateSet("DatabaseMirroring", "ServiceBroker", "Soap", "TSql")]
    [PsStringCast]
    public string? Type { get; set; }

    /// <summary>Modify all endpoints on the instance.</summary>
    [Parameter]
    public SwitchParameter AllEndpoints { get; set; }

    /// <summary>Endpoint objects piped from Get-DbaEndpoint.</summary>
    [Parameter(ValueFromPipeline = true, Position = 5)]
    public Microsoft.SqlServer.Management.Smo.Endpoint[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // The two names the source's $props list iterates at :106, in source order. They are the
    // MAP KEYS, and they must match the source's list exactly - a name here that the source does
    // not iterate would be dead, and one missing here would silently never be assigned.
    private static readonly string[] PropertyNames = { "Owner", "Type" };

    private Hashtable? _state;

    /// <summary>
    /// Builds the propertyName -> was-it-bound map that replaces the source's DYNAMIC
    /// Test-Bound calls at :113 and :116. Test-Bound scope-walks the caller and cannot ride the
    /// hop; worse, hop parameters are BOUND BY CONSTRUCTION (all passed positionally, unbound
    /// ones arriving as $null), so a verbatim Test-Bound inside the hop answers TRUE for
    /// everything and both properties would be assigned onto every endpoint - followed by
    /// $ep.Alter(). Same data-affecting class as W4-058's nine-property overwrite, smaller only
    /// in that there are two properties rather than nine.
    ///
    /// Case-insensitive to match Test-Bound, which tests key presence in the caller's
    /// $PSBoundParameters and is itself case-insensitive.
    /// </summary>
    private Hashtable BuildBoundPropertyMap()
    {
        Hashtable map = new Hashtable(System.StringComparer.OrdinalIgnoreCase);
        foreach (string name in PropertyNames)
        {
            map[name] = MyInvocation.BoundParameters.ContainsKey(name);
        }
        return map;
    }

    protected override void BeginProcessing()
    {
        base.BeginProcessing();

        // C1 transplant condition: loud fail before any record if the engine field is gone.
        PromptStateTransplant.AssertResolvable("Set-DbaEndpoint");
    }

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        // WHOLE-RECORD hop. No begin block and no Test-FunctionInterrupt in the source, so no
        // begin/process lifecycle and no DEF-011 latch exposure - checked against this source.
        //
        // NO PARAMETER CARRY. The only process-block parameter mutation is `$InputObject +=` at
        // :103, and $InputObject is the ValueFromPipeline parameter, which the binder RE-BINDS
        // every record. The cross-record leak detector reports clean; I also read the branches by
        // hand, because that tool catches SOURCE order and not per-BRANCH order - the gap that let
        // $ag through on W4-055 until codex caught it. $instance, $ep, $prop and $realprop are all
        // assigned before every read on every path, and $props is assigned unconditionally at :106
        // ahead of its only read.
        //
        // THREE carried bound flags for the guard at :98. $__boundSqlInstance is a single-name
        // form; the second half is the MULTI-NAME -Not over Endpoint and AllEndpoints, which means
        // NEITHER bound (Test-Bound computes Min=1/Max=length and returns ((-not $Not) -eq $test)),
        // so it becomes -not ($__boundEndpoint -or $__boundAllEndpoints). Note this guard keys on
        // BINDING: -Endpoint bound to an EMPTY string still clears it, where a value test would
        // not.
        //
        // FOURTH ARGUMENT, the bound-flag MAP: see BuildBoundPropertyMap. $Owner and $Type ride as
        // hop parameters under their OWN names so the source's `Get-Variable -Name $prop -ValueOnly`
        // at :114 and :117 still resolves them - verified, not assumed, and the reason those two
        // parameters must not be renamed in the hop frame.
        //
        // W3-082 PROMPT-STATE TRANSPLANT: VFP + per-record + an inner $Pscmdlet gate at :109.
        // [DEF-001] closed via InvokeScopedStreaming (ab7492c). Streaming changes -WhatIf transcript
        // capture (documented observability change, not behaviour); the parity runner strips the
        // transcript gate-message. Fleet-confirmed non-blocker (C's streamed ShouldProcess wave, MSTest 487/487).
        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            Hashtable? sentinel = item?.BaseObject as Hashtable;
            if (sentinel is not null && sentinel.ContainsKey("__w4050State"))
            {
                _state = sentinel["__w4050State"] as Hashtable;
                return;
            }
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                return;
            }
            WriteObject(item);
        }, ProcessScript,
            SqlInstance, SqlCredential, Endpoint, Owner, Type,
            AllEndpoints.ToBool(), InputObject,
            EnableException.ToBool(),
            TestBound(nameof(SqlInstance)), TestBound(nameof(Endpoint)), TestBound(nameof(AllEndpoints)),
            BuildBoundPropertyMap(),
            _state,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the source process block VERBATIM, CRLF-preserved and byte-proven against source
    // lines 98-126 after stripping two -FunctionName appends and reversing THREE Test-Bound
    // rewrites (each carrying its own # SOURCE: marker): the compound guard at :98 and the two
    // DYNAMIC calls at :113 and :116. The source's "Seting" typo at :109 rides untouched.
    // $AllEndpoints is passed UNTYPED and as .ToBool() - a typed [switch] in a hop param block is
    // excluded from positional binding (the class #7/#8 switch-shift), which would silently shift
    // every argument after it. The gate uses the inner block's own $Pscmdlet; the dot-block
    // preserves the source's early return at :100. Bracketing the body: only the W3-082
    // prompt-state transplant.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Endpoint, $Owner, $Type, $AllEndpoints, $InputObject, $EnableException, $__boundSqlInstance, $__boundEndpoint, $__boundAllEndpoints, $__boundProps, $__state, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [string[]]$Endpoint, [string]$Owner, [string]$Type, $AllEndpoints, [Microsoft.SqlServer.Management.Smo.Endpoint[]]$InputObject, $EnableException, $__boundSqlInstance, $__boundEndpoint, $__boundAllEndpoints, $__boundProps, $__state, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    # cross-record engine-state restore: the ShouldProcess Yes/No-to-All answer spans the
    # pipeline in the source (one CommandRuntime); the transplant field name is identical
    # on PS 5.1 and PS 7 (W3-082 mechanism, empirically verified). No parameter carry on this
    # row - the only process-block param mutation targets the VFP $InputObject, which the
    # binder re-binds every record.
    $__spField = $Pscmdlet.CommandRuntime.GetType().GetField("lastShouldProcessContinueStatus", [System.Reflection.BindingFlags]"NonPublic,Instance")
    if ($null -eq $__spField) {
        throw "Set-DbaEndpoint: prompt-state transplant field lastShouldProcessContinueStatus not resolvable on this engine (C1 assert)."
    }
    if ($null -ne $__state -and $null -ne $__state.shouldProcessContinueStatus) {
        $__spField.SetValue($Pscmdlet.CommandRuntime, [Enum]::Parse($__spField.FieldType, $__state.shouldProcessContinueStatus))
    }

    . {
        if ($__boundSqlInstance -And (-not ($__boundEndpoint -or $__boundAllEndpoints))) { # SOURCE: if ((Test-Bound -ParameterName SqlInstance) -And (Test-Bound -Not -ParameterName Endpoint, AllEndpoints)) {
            Stop-Function -Message "You must specify AllEndpoints or Endpoint when using the SqlInstance parameter." -FunctionName Set-DbaEndpoint
            return
        }
        foreach ($instance in $SqlInstance) {
            $InputObject += Get-DbaEndpoint -SqlInstance $instance -SqlCredential $SqlCredential -Endpoint $Endpoint
        }

        $props = "Owner", "Type"
        foreach ($ep in $InputObject) {
            try {
                if ($Pscmdlet.ShouldProcess($ep.Parent.Name, "Seting properties on $ep")) {
                    foreach ($prop in $props) {
                        if ($prop -eq "Type") {
                            $realprop = "EndpointType"
                            if ($__boundProps[$prop]) { # SOURCE: if (Test-Bound -ParameterName $prop) {
                                $ep.$realprop = (Get-Variable -Name $prop -ValueOnly)
                            }
                        } elseif ($__boundProps[$prop]) { # SOURCE: } elseif (Test-Bound -ParameterName $prop) {
                            $ep.$prop = (Get-Variable -Name $prop -ValueOnly)
                        }
                    }
                    $ep.Alter()
                    $ep
                }
            } catch {
                Stop-Function -Message "Failure" -ErrorRecord $_ -Continue -FunctionName Set-DbaEndpoint
            }
        }
    }

    @{ __w4050State = @{ shouldProcessContinueStatus = $(if ($null -ne $__spField) { "$($__spField.GetValue($Pscmdlet.CommandRuntime))" } else { $null }) } }
} $SqlInstance $SqlCredential $Endpoint $Owner $Type $AllEndpoints $InputObject $EnableException $__boundSqlInstance $__boundEndpoint $__boundAllEndpoints $__boundProps $__state $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
