#nullable enable

using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Grants endpoint or availability-group permissions to logins, creating missing
/// logins on demand. Port of public/Grant-DbaAgPermission.ps1; surface pinned by
/// migration/baselines/Grant-DbaAgPermission.json.
/// </summary>
[Cmdlet(VerbsSecurity.Grant, "DbaAgPermission", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Low)]
public sealed class GrantDbaAgPermissionCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instances using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The logins to grant permissions to; created when missing.</summary>
    [Parameter(Position = 2)]
    public string[]? Login { get; set; }

    /// <summary>The availability groups to grant permissions on.</summary>
    [Parameter(Position = 3)]
    public string[]? AvailabilityGroup { get; set; }

    /// <summary>Whether the grant targets the mirroring endpoint or availability groups.</summary>
    [Parameter(Mandatory = true, Position = 4)]
    [ValidateSet("Endpoint", "AvailabilityGroup")]
    public string[]? Type { get; set; }

    /// <summary>The permissions to grant.</summary>
    [Parameter(Position = 5)]
    [ValidateSet("Alter", "Connect", "Control", "CreateAnyDatabase", "CreateSequence", "Delete", "Execute", "Impersonate", "Insert", "Receive", "References", "Select", "Send", "TakeOwnership", "Update", "ViewChangeTracking", "ViewDefinition")]
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
        PromptStateTransplant.AssertResolvable("Grant-DbaAgPermission");
    }

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        // Whole-record hop per the W4-011 mutating convention: both ShouldProcess gates
        // run on the INNER hop scriptblock's own $Pscmdlet (the inner block re-declares
        // SupportsShouldProcess + ConfirmImpact Low - never prompting by default,
        // exactly like the function; bound WhatIf/Confirm forward raw). Because
        // InputObject is a per-record VFP axis, an explicit -Confirm answer of
        // Yes/No-to-All must survive BETWEEN piped records the way the source's single
        // function-scope $Pscmdlet does: the W3-082 prompt-state transplant carries
        // lastShouldProcessContinueStatus through the __w4036State sentinel. The
        // source's three validation returns and the two mid-loop catch returns exit the
        // whole record via the dot-block frame; the $InputObject += accumulation and the
        // account loop share record scope. The plain Stop-Function sites' interrupt
        // flags are write-only inert (no Test-FunctionInterrupt in source).
        // [DEF-001] closed via InvokeScopedStreaming (ab7492c). Streaming changes -WhatIf transcript
        // capture (documented observability change, not behaviour); the parity runner strips the
        // transcript gate-message. Fleet-confirmed non-blocker (C's streamed ShouldProcess wave, MSTest 487/487).
        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            Hashtable? sentinel = item?.BaseObject as Hashtable;
            if (sentinel is not null && sentinel.ContainsKey("__w4036State"))
            {
                _state = sentinel["__w4036State"] as Hashtable;
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
            SqlInstance, SqlCredential, Login, AvailabilityGroup, Type, Permission,
            InputObject, EnableException.ToBool(),
            TestBound(nameof(SqlInstance)), TestBound(nameof(InputObject)), _state,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the source process block VERBATIM, CRLF-preserved and cmp-proven byte-exact
    // after stripping eleven -FunctionName appends and the one multi-name Test-Bound
    // rewrite (SOURCE comment). ShouldProcess gates use the inner block's own
    // $Pscmdlet; the dot-block preserves the source's early returns.
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

    # cross-record engine-state restore: the ShouldProcess Yes/No-to-All answer spans the
    # pipeline in the source (one CommandRuntime); the transplant field name is identical
    # on PS 5.1 and PS 7 (W3-082 mechanism, empirically verified)
    $__spField = $Pscmdlet.CommandRuntime.GetType().GetField("lastShouldProcessContinueStatus", [System.Reflection.BindingFlags]"NonPublic,Instance")
    if ($null -eq $__spField) {
        throw "Grant-DbaAgPermission: prompt-state transplant field lastShouldProcessContinueStatus not resolvable on this engine (C1 assert)."
    }
    if ($null -ne $__state -and $null -ne $__state.shouldProcessContinueStatus) {
        $__spField.SetValue($Pscmdlet.CommandRuntime, [Enum]::Parse($__spField.FieldType, $__state.shouldProcessContinueStatus))
    }

    . {
        if (-not ($__boundSqlInstance -or $__boundInputObject)) { # SOURCE: if (Test-Bound -Not SqlInstance, InputObject) {
            Stop-Function -Message "You must supply either -SqlInstance or an Input Object" -FunctionName Grant-DbaAgPermission
            return
        }

        if ($Type -contains "Endpoint" -and $SqlInstance -and -not $Login) {
            Stop-Function -Message "You must specify one or more logins when using the Endpoint type together with the SqlInstance parameter." -FunctionName Grant-DbaAgPermission
            return
        }

        if ($Type -contains "AvailabilityGroup" -and -not $AvailabilityGroup) {
            Stop-Function -Message "You must specify at least one availability group when using the AvailabilityGroup type." -FunctionName Grant-DbaAgPermission
            return
        }

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Grant-DbaAgPermission
            }
            if ($Permission -contains "CreateAnyDatabase") {
                foreach ($ag in $AvailabilityGroup) {
                    try {
                        $server.GrantAvailabilityGroupCreateDatabasePrivilege($ag)
                        $server.Alter()
                    } catch {
                        Stop-Function -Message "Failure executing GrantAvailabilityGroupCreateDatabasePrivilege for Availability Group $ag" -ErrorRecord $_ -Target $instance -FunctionName Grant-DbaAgPermission
                        return
                    }
                }
            }
            if ($Login) {
                $InputObject += Get-DbaLogin -SqlInstance $server -SqlCredential $SqlCredential -Login $Login
                foreach ($account in $Login) {
                    if ($account -notin $InputObject.Name) {
                        try {
                            $InputObject += New-DbaLogin -SqlInstance $server -Login $account -EnableException
                        } catch {
                            Stop-Function -Message "Failure creating login $account" -ErrorRecord $_ -Target $instance -FunctionName Grant-DbaAgPermission
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
                    Stop-Function -Message "DatabaseMirroring endpoint does not exist on $server" -Target $server -Continue -FunctionName Grant-DbaAgPermission
                }

                foreach ($perm in $Permission) {
                    if ($Pscmdlet.ShouldProcess($server.Name, "Granting $perm on $endpoint")) {
                        if ($perm -in 'CreateAnyDatabase') {
                            Stop-Function -Message "$perm not supported by endpoints" -Continue -FunctionName Grant-DbaAgPermission
                        }
                        try {
                            $bigperms = New-Object Microsoft.SqlServer.Management.Smo.ObjectPermissionSet([Microsoft.SqlServer.Management.Smo.ObjectPermission]::$perm)
                            $endpoint.Grant($bigperms, $account.Name)
                            [PSCustomObject]@{
                                ComputerName = $account.ComputerName
                                InstanceName = $account.InstanceName
                                SqlInstance  = $account.SqlInstance
                                Name         = $account.Name
                                Permission   = $perm
                                Type         = "Grant"
                                Status       = "Success"
                            }
                        } catch {
                            Stop-Function -Message "Failure granting $perm on endpoint to $($account.Name)" -ErrorRecord $_ -Target $account -Continue -FunctionName Grant-DbaAgPermission
                        }
                    }
                }
            }

            if ($Type -contains "AvailabilityGroup") {
                $ags = Get-DbaAvailabilityGroup -SqlInstance $server -AvailabilityGroup $AvailabilityGroup
                foreach ($ag in $ags) {
                    foreach ($perm in $Permission) {
                        if ($perm -notin 'Alter', 'Control', 'TakeOwnership', 'ViewDefinition') {
                            Stop-Function -Message "$perm not supported by availability groups" -Continue -FunctionName Grant-DbaAgPermission
                        }
                        if ($Pscmdlet.ShouldProcess($server.Name, "Granting $perm on $ags")) {
                            try {
                                $bigperms = New-Object Microsoft.SqlServer.Management.Smo.ObjectPermissionSet([Microsoft.SqlServer.Management.Smo.ObjectPermission]::$perm)
                                $ag.Grant($bigperms, $account.Name)
                                [PSCustomObject]@{
                                    ComputerName = $account.ComputerName
                                    InstanceName = $account.InstanceName
                                    SqlInstance  = $account.SqlInstance
                                    Name         = $account.Name
                                    Permission   = $perm
                                    Type         = "Grant"
                                    Status       = "Success"
                                }
                            } catch {
                                Stop-Function -Message "Failure granting $perm on availability group $($ag.Name) to $($account.Name)" -ErrorRecord $_ -Target $ag -Continue -FunctionName Grant-DbaAgPermission
                            }
                        }
                    }
                }
            }
        }
    }

    @{ __w4036State = @{ shouldProcessContinueStatus = $(if ($null -ne $__spField) { "$($__spField.GetValue($Pscmdlet.CommandRuntime))" } else { $null }) } }
} $SqlInstance $SqlCredential $Login $AvailabilityGroup $Type $Permission $InputObject $EnableException $__boundSqlInstance $__boundInputObject $__state $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
