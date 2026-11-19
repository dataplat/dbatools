#nullable enable

using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Revokes endpoint and availability group permissions from a login.
/// Port of public/Revoke-DbaAgPermission.ps1; surface pinned by
/// migration/baselines/Revoke-DbaAgPermission.json.
/// </summary>
[Cmdlet(VerbsSecurity.Revoke, "DbaAgPermission", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Low)]
public sealed class RevokeDbaAgPermissionCommand : DbaBaseCmdlet
{
    /// <summary>The SQL Server instance or instances hosting the logins.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instances using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The login or logins to revoke permissions from.</summary>
    [Parameter(Position = 2)]
    [PsStringArrayCast]
    public string[]? Login { get; set; }

    /// <summary>The availability group or groups to act on.</summary>
    [Parameter(Position = 3)]
    [PsStringArrayCast]
    public string[]? AvailabilityGroup { get; set; }

    /// <summary>The permission type - Endpoint and/or AvailabilityGroup.</summary>
    [Parameter(Mandatory = true, Position = 4)]
    [ValidateSet("Endpoint", "AvailabilityGroup")]
    [PsStringArrayCast]
    public string[]? Type { get; set; }

    /// <summary>The permission or permissions to revoke.</summary>
    [Parameter(Position = 5)]
    [ValidateSet("Alter", "Connect", "Control", "CreateAnyDatabase", "CreateSequence", "Delete",
        "Execute", "Impersonate", "Insert", "Receive", "References", "Select", "Send",
        "TakeOwnership", "Update", "ViewChangeTracking", "ViewDefinition")]
    [PsStringArrayCast]
    public string[] Permission { get; set; } = new[] { "Connect" };

    /// <summary>Login objects piped from Get-DbaLogin.</summary>
    [Parameter(ValueFromPipeline = true, Position = 6)]
    public Microsoft.SqlServer.Management.Smo.Login[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    private Hashtable? _state;

    protected override void BeginProcessing()
    {
        base.BeginProcessing();

        // C1 transplant condition: loud fail before any record if the engine field is gone.
        PromptStateTransplant.AssertResolvable("Revoke-DbaAgPermission");
    }

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        // WHOLE-RECORD hop. This row carries the DEF-012 NON-PARAMETER cross-record sub-class
        // (coordinator ruling 2026-07-19 02:35), and the first two leaks were MEASURED before the port was
        // written - not inferred from reading the source.
        //
        // CARRY 1 - $perm, and it is the severe one (escalated upstream as U-10, a privilege-
        // escalation bug in dbatools itself). The source reads $perm at :128 inside the instance
        // loop:
        //     :128  if ($perm -contains "CreateAnyDatabase") {
        //     :137      $server.Query("ALTER AVAILABILITY GROUP $ag GRANT CREATE ANY DATABASE")
        //     :143  } elseif ($Login) { ... }
        // $perm is never assigned before :128 in a record - it is the LOOP VARIABLE of the later
        // :168/:195 loops. Record 1 therefore takes the elseif branch. But it is function-scoped,
        // so on RECORD 2 the test can be TRUE and the command issues a GRANT - from inside a
        // command named Revoke-. Measured with two piped logins:
        //     record 1: getlogin | newlogin | getag        (elseif, then $perm assigned)
        //     record 2: connect  | ALTER AVAILABILITY GROUP ag1 GRANT CREATE ANY DATABASE
        // A per-record hop would give record 2 a fresh scope, always take the elseif branch, and
        // never issue the GRANT - safer, and therefore DIVERGENT. The verbatim law says reproduce
        // it; the upstream bug is tracked separately as U-10 rather than fixed here.
        //
        // CARRY 2 - $server. At :148 the source calls
        //     $InputObject += New-DbaLogin -SqlInstance $server -Login $account -EnableException
        // but on that branch $server is only assigned at :130 (the OTHER branch) and at :159 (the
        // later loop). Measured: record 1 passes an EMPTY server, record 2 passes record 1's
        // $account.Parent. Carried so the port reproduces both.
        //
        // Neither leak is a PARAMETER, which is why Get-ParamMutationInventory reports zero for
        // this row and is correct to. They ride the __w4055State sentinel alongside the W3-082
        // prompt state.
        // [DEF-001] closed via InvokeScopedStreaming (ab7492c). Streaming changes -WhatIf transcript
        // capture (documented observability change, not behaviour); the parity runner strips the
        // transcript gate-message. Fleet-confirmed non-blocker (C's streamed ShouldProcess wave, MSTest 487/487).
        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            Hashtable? sentinel = item?.BaseObject as Hashtable;
            if (sentinel is not null && sentinel.ContainsKey("__w4055State"))
            {
                _state = sentinel["__w4055State"] as Hashtable;
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
            SqlInstance, SqlCredential, Login, AvailabilityGroup, Type, Permission, InputObject,
            EnableException.ToBool(),
            TestBound(nameof(SqlInstance)), TestBound(nameof(InputObject)),
            _state,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the source process block VERBATIM, CRLF-preserved and byte-proven against source
    // lines 112-219 after appending nine -FunctionName arguments and reversing the single
    // Test-Bound rewrite (SOURCE comment). The source's own "Seting"/"Revokeing" typos ride
    // untouched. Bracketing the body: the THREE DEF-012 non-parameter leaks ($perm, $server, $ag) are
    // seeded BEFORE the body so it observes the source's cross-record state, and the W3-082
    // prompt-state transplant is injected before any gate; the tail harvests all FOUR values.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Login, $AvailabilityGroup, $Type, $Permission, $InputObject, $EnableException, $__boundSqlInstance, $__boundInputObject, $__state, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [string[]]$Login, [string[]]$AvailabilityGroup, [string[]]$Type, [string[]]$Permission, [Microsoft.SqlServer.Management.Smo.Login[]]$InputObject, $EnableException, $__boundSqlInstance, $__boundInputObject, $__state, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    # DEF-012 NON-PARAMETER cross-record state. None of these is a parameter: $perm is the loop
    # variable of the :168/:195 loops, read at :128 before any record assigns it, and $server is
    # assigned only on the other branch (:130) and in the later loop (:159). Both survive in
    # function scope in the source, so both are seeded here BEFORE the body. Seeded on ContainsKey
    # so a carried $null is restored too - "record 1 saw nothing" is itself state the next record
    # must observe.
    if ($null -ne $__state -and $__state.ContainsKey('perm')) { $perm = $__state.perm }
    if ($null -ne $__state -and $__state.ContainsKey('server')) { $server = $__state.server }
    # THIRD LEAK, carried under the SAME coordinator ruling by extension rather than by name.
    # The 2026-07-19 W4-055 dual ruling names $perm and $server; it does not mention $ag, which I
    # reported separately. Its stated PRINCIPLE - port bug-for-bug, never let a per-record hop's
    # safer divergence hide the bug - applies to $ag identically, so it is carried here rather
    # than left to differ. $ag is assigned at :135 (CreateAnyDatabase branch) and :194 (AG branch)
    # but READ at :186 in the ENDPOINT branch as `-Target $ag`, a path on which nothing assigns it.
    # Source order says assigned, control flow says never assigned on the reading path - which is
    # exactly the per-BRANCH blind spot my own detector documents. WITHOUT this carry the compiled
    # world would pass -Target $null where the source passes the previous record's group: a
    # divergence in the SAFE direction, which is still a divergence and the one thing the ruling
    # forbids. FLAGGED TO THE COORDINATOR as an applied extension, not a silent decision - strike
    # it and this line comes out. Severity assessed (not measured) as benign like W4-039's
    # Stop-Function -Target case: it colours an error record's Target, it does not issue a grant.
    if ($null -ne $__state -and $__state.ContainsKey('ag')) { $ag = $__state.ag }

    # cross-record engine-state restore: the ShouldProcess Yes/No-to-All answer spans the
    # pipeline in the source (one CommandRuntime); the transplant field name is identical
    # on PS 5.1 and PS 7 (W3-082 mechanism, empirically verified)
    $__spField = $Pscmdlet.CommandRuntime.GetType().GetField("lastShouldProcessContinueStatus", [System.Reflection.BindingFlags]"NonPublic,Instance")
    if ($null -eq $__spField) {
        throw "Revoke-DbaAgPermission: prompt-state transplant field lastShouldProcessContinueStatus not resolvable on this engine (C1 assert)."
    }
    if ($null -ne $__state -and $null -ne $__state.shouldProcessContinueStatus) {
        $__spField.SetValue($Pscmdlet.CommandRuntime, [Enum]::Parse($__spField.FieldType, $__state.shouldProcessContinueStatus))
    }

    . {
        if (-not ($__boundSqlInstance -or $__boundInputObject)) { # SOURCE: if (Test-Bound -Not SqlInstance, InputObject) {
            Stop-Function -Message "You must supply either -SqlInstance or an Input Object" -FunctionName Revoke-DbaAgPermission
            return
        }

        if ($SqlInstance -and -not $Login -and -not $AvailabilityGroup) {
            Stop-Function -Message "You must specify one or more logins when using the SqlInstance parameter." -FunctionName Revoke-DbaAgPermission
            return
        }

        if ($Type -contains "AvailabilityGroup" -and -not $AvailabilityGroup) {
            Stop-Function -Message "You must specify at least one availability group when using the AvailabilityGroup type." -FunctionName Revoke-DbaAgPermission
            return
        }

        foreach ($instance in $SqlInstance) {
            if ($perm -contains "CreateAnyDatabase") {
                try {
                    $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
                } catch {
                    Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Revoke-DbaAgPermission
                }

                foreach ($ag in $AvailabilityGroup) {
                    try {
                        $server.Query("ALTER AVAILABILITY GROUP $ag GRANT CREATE ANY DATABASE")
                    } catch {
                        Stop-Function -Message "Failure" -ErrorRecord $_ -Target $instance -FunctionName Revoke-DbaAgPermission
                        return
                    }
                }
            } elseif ($Login) {
                $InputObject += Get-DbaLogin -SqlInstance $instance -SqlCredential $SqlCredential -Login $Login
                foreach ($account in $Login) {
                    if ($account -notin $InputObject.Name) {
                        try {
                            $InputObject += New-DbaLogin -SqlInstance $server -Login $account -EnableException
                        } catch {
                            Stop-Function -Message "Failure" -ErrorRecord $_ -Target $instance -FunctionName Revoke-DbaAgPermission
                            return
                        }
                    }
                }
            }
        }

        foreach ($account in $InputObject) {
            $server = $account.Parent
            if ($Type -contains "Endpoint") {
                $server.Endpoints.Refresh()
                $endpoint = $server.Endpoints | Where-Object EndpointType -eq DatabaseMirroring

                if (-not $endpoint) {
                    Stop-Function -Message "DatabaseMirroring endpoint does not exist on $server" -Target $server -Continue -FunctionName Revoke-DbaAgPermission
                }

                foreach ($perm in $Permission) {
                    if ($Pscmdlet.ShouldProcess($server.Name, "Revokeing $perm on $endpoint")) {
                        if ($perm -in 'CreateAnyDatabase') {
                            Stop-Function -Message "$perm not supported by endpoints" -Continue -FunctionName Revoke-DbaAgPermission
                        }
                        try {
                            $bigperms = New-Object Microsoft.SqlServer.Management.Smo.ObjectPermissionSet([Microsoft.SqlServer.Management.Smo.ObjectPermission]::$perm)
                            $endpoint.Revoke($bigperms, $account.Name)
                            [PSCustomObject]@{
                                ComputerName = $account.ComputerName
                                InstanceName = $account.InstanceName
                                SqlInstance  = $account.SqlInstance
                                Name         = $account.Name
                                Permission   = $perm
                                Type         = "Revoke"
                                Status       = "Success"
                            }
                        } catch {
                            Stop-Function -Message "Failure" -ErrorRecord $_ -Target $ag -Continue -FunctionName Revoke-DbaAgPermission
                        }
                    }
                }
            }

            if ($Type -contains "AvailabilityGroup") {
                $ags = Get-DbaAvailabilityGroup -SqlInstance $account.Parent -AvailabilityGroup $AvailabilityGroup
                foreach ($ag in $ags) {
                    foreach ($perm in $Permission) {
                        if ($perm -notin 'Alter', 'Control', 'TakeOwnership', 'ViewDefinition') {
                            Stop-Function -Message "$perm not supported by availability groups" -Continue -FunctionName Revoke-DbaAgPermission
                        }
                        if ($Pscmdlet.ShouldProcess($server.Name, "Revokeing $perm on $ags")) {
                            try {
                                $bigperms = New-Object Microsoft.SqlServer.Management.Smo.ObjectPermissionSet([Microsoft.SqlServer.Management.Smo.ObjectPermission]::$perm)
                                $ag.Revoke($bigperms, $account.Name)
                                [PSCustomObject]@{
                                    ComputerName = $account.ComputerName
                                    InstanceName = $account.InstanceName
                                    SqlInstance  = $account.SqlInstance
                                    Name         = $account.Name
                                    Permission   = $perm
                                    Type         = "Revoke"
                                    Status       = "Success"
                                }
                            } catch {
                                Stop-Function -Message "Failure" -ErrorRecord $_ -Target $ag -Continue -FunctionName Revoke-DbaAgPermission
                            }
                        }
                    }
                }
            }
        }
    }

    @{ __w4055State = @{ perm = $perm; server = $server; ag = $ag; shouldProcessContinueStatus = $(if ($null -ne $__spField) { "$($__spField.GetValue($Pscmdlet.CommandRuntime))" } else { $null }) } }
} $SqlInstance $SqlCredential $Login $AvailabilityGroup $Type $Permission $InputObject $EnableException $__boundSqlInstance $__boundInputObject $__state $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
