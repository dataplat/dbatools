#nullable enable

using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Removes log shipping from a database.
/// Port of public/Remove-DbaDbLogShipping.ps1; surface pinned by
/// migration/baselines/Remove-DbaDbLogShipping.json.
/// </summary>
[Cmdlet(VerbsCommon.Remove, "DbaDbLogShipping", DefaultParameterSetName = "Default",
    SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
public sealed class RemoveDbaDbLogShippingCommand : DbaBaseCmdlet
{
    /// <summary>The primary SQL Server instance.</summary>
    [Parameter(Mandatory = true, Position = 0)]
    [ValidateNotNullOrEmpty]
    public DbaInstanceParameter? PrimarySqlInstance { get; set; }

    /// <summary>The secondary SQL Server instance.</summary>
    [Parameter(Position = 1)]
    public DbaInstanceParameter? SecondarySqlInstance { get; set; }

    /// <summary>Login to the primary instance using alternative credentials.</summary>
    [Parameter(Position = 2)]
    public PSCredential? PrimarySqlCredential { get; set; }

    /// <summary>Login to the secondary instance using alternative credentials.</summary>
    [Parameter(Position = 3)]
    public PSCredential? SecondarySqlCredential { get; set; }

    /// <summary>The database or databases to remove log shipping from.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 4)]
    public object[]? Database { get; set; }

    /// <summary>Also drop the secondary database.</summary>
    [Parameter]
    public SwitchParameter RemoveSecondaryDatabase { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    private Hashtable? _state;

    protected override void BeginProcessing()
    {
        base.BeginProcessing();

        // C1 transplant condition: loud fail before any record if the engine field is gone.
        PromptStateTransplant.AssertResolvable("Remove-DbaDbLogShipping");

        // SEPARATE BEGIN HOP - deliberately NOT folded into the process top. The source's begin
        // block calls Connect-DbaInstance ONCE and the process block READS the resulting
        // $primaryServer (database-existence check, log-shipping query). Folding begin into the
        // process hop would re-connect PER PIPED RECORD, an observable divergence the source does
        // not have. So begin runs once here and harvests what process needs.
        foreach (PSObject? item in NestedCommand.InvokeScoped(this, BeginScript,
            PrimarySqlInstance, PrimarySqlCredential, Database,
            EnableException.ToBool(),
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
        {
            Hashtable? sentinel = item?.BaseObject as Hashtable;
            if (sentinel is not null && sentinel.ContainsKey("__w4049State"))
            {
                _state = sentinel["__w4049State"] as Hashtable;
                continue;
            }
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                continue;
            }
            WriteObject(item);
        }
    }

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        // WHOLE-RECORD hop. FOUR classes land on this one row.
        //
        // (1) BEGIN/PROCESS LIFECYCLE - see BeginProcessing above. $primaryServer rides the
        //     sentinel from the begin hop; it is a live SMO object, carried by reference.
        //
        // (2) DEF-011 INTERRUPT-LATCH CARRY, and on this row it is a DESTRUCTIVE-DIVERGENCE
        //     guard rather than a reporting nicety. The source's process block opens with
        //     `if (Test-FunctionInterrupt) { return }`, and that latch is SCOPE-LOCAL:
        //     Test-FunctionInterrupt resolves it with `Get-Variable -Scope 1`, i.e. its caller's
        //     scope. Source begin and process share one function scope so it works; a hop runs
        //     them as separate scriptblocks with no shared parent, so the latch does NOT cross.
        //     Measured with controls in migration/tools/Probe-W4049InterruptLatchAcrossHops.ps1
        //     (in-function control observes it; across hops it does not; seeding scope 0 restores
        //     it; a false seed correctly does not fire).
        //
        //     Why it MATTERS here specifically: $Database is ValueFromPipeline, so when the
        //     command is PIPED TO, $Database is unbound during begin - which trips the source's
        //     own `if (-not $Database)` guard, sets the latch, and makes process return without
        //     touching anything. Without the carry, the ported cmdlet would sail past that and
        //     execute the log-shipping teardown on input the SOURCE REFUSES TO ACT ON. That is a
        //     destructive divergence, not a cosmetic one.
        //
        //     The latch is carried BOTH ways: seeded before the body and re-harvested after,
        //     because the source's non--Continue Stop-Function sites inside process (:145, :181,
        //     :196, :210) also set it, and a later piped record must observe that.
        //
        // (3) CROSS-RECORD PARAMETER CARRY, the sticky direction: :158 is
        //     `if (-not $SecondarySqlInstance) { $SecondarySqlInstance = $logshippingInfo.SecondaryServer }`
        //     - a VALUE guard, which per the corrected RULE 2 is STICKY and MUST be carried. Once
        //     record 1 derives a secondary from ITS log-shipping row, record 2 keeps it and never
        //     derives its own. Same shape as W4-042's $ClusterType.
        //
        // (4) W3-082 PROMPT-STATE TRANSPLANT over FOUR inner $PSCmdlet gates at ConfirmImpact
        //     Medium (:171, :189, :203, :216), so Yes/No-to-All persists across piped records.
        // [DEF-001] closed via InvokeScopedStreaming (ab7492c). Streaming changes -WhatIf transcript
        // capture (documented observability change, not behaviour); the parity runner strips the
        // transcript gate-message. Fleet-confirmed non-blocker (C's streamed ShouldProcess wave, MSTest 487/487).
        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            Hashtable? sentinel = item?.BaseObject as Hashtable;
            if (sentinel is not null && sentinel.ContainsKey("__w4049State"))
            {
                _state = sentinel["__w4049State"] as Hashtable;
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
            PrimarySqlInstance, SecondarySqlInstance, PrimarySqlCredential, SecondarySqlCredential,
            Database, RemoveSecondaryDatabase.ToBool(),
            EnableException.ToBool(),
            _state,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the source BEGIN block VERBATIM (lines 111-121), CRLF-preserved, after appending two
    // -FunctionName arguments. The tail harvests $primaryServer and the interrupt latch - the
    // latch is read out of THIS scriptblock's own scope (Scope 0), which is exactly where
    // Stop-Function wrote it and where Test-FunctionInterrupt would have looked.
    private const string BeginScript = """
param($PrimarySqlInstance, $PrimarySqlCredential, $Database, $EnableException, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter]$PrimarySqlInstance, [PSCredential]$PrimarySqlCredential, [object[]]$Database, $EnableException, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    $primaryServer = $null
    . {
        if (-not $Database) {
            Stop-Function -Message "Please enter one or more databases" -FunctionName Remove-DbaDbLogShipping
        }

        # Try connecting to the source instance
        try {
            $primaryServer = Connect-DbaInstance -SqlInstance $PrimarySqlInstance -SqlCredential $PrimarySqlCredential
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $PrimarySqlInstance -FunctionName Remove-DbaDbLogShipping
            return
        }
    }

    # harvest the scope-local interrupt latch: Stop-Function wrote it into THIS scope, and in the
    # source the process block would have read it from the shared function scope (DEF-011)
    $__latchVar = Get-Variable -Name "__dbatools_interrupt_function_78Q9VPrM6999g6zo24Qn83m09XF56InEn4hFrA8Fwhu5xJrs6r" -Scope 0 -ErrorAction Ignore
    @{ __w4049State = @{ primaryServer = $primaryServer; interruptLatch = [bool]($__latchVar.Value); secondarySqlInstance = $null; shouldProcessContinueStatus = $null } }
} $PrimarySqlInstance $PrimarySqlCredential $Database $EnableException $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";

    // PS: the source PROCESS block VERBATIM (lines 125-226), CRLF-preserved and byte-proven,
    // after appending ten -FunctionName arguments. No Test-Bound rewrites - this row has none.
    // Bracketing the body: $primaryServer and the sticky $SecondarySqlInstance are seeded from the
    // sentinel, the DEF-011 interrupt latch is re-seeded into THIS scriptblock's scope so the
    // body's own Test-FunctionInterrupt resolves it (the dot-block adds no scope, verified), and
    // the W3-082 prompt-state transplant is injected before any gate. The tail re-harvests all
    // three plus the prompt state.
    private const string ProcessScript = """
param($PrimarySqlInstance, $SecondarySqlInstance, $PrimarySqlCredential, $SecondarySqlCredential, $Database, $RemoveSecondaryDatabase, $EnableException, $__state, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter]$PrimarySqlInstance, [Dataplat.Dbatools.Parameter.DbaInstanceParameter]$SecondarySqlInstance, [PSCredential]$PrimarySqlCredential, [PSCredential]$SecondarySqlCredential, [object[]]$Database, $RemoveSecondaryDatabase, $EnableException, $__state, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    # begin-block state: $primaryServer is connected ONCE in the begin hop and read by the body
    $primaryServer = $null
    if ($null -ne $__state) { $primaryServer = $__state.primaryServer }

    # cross-record PARAMETER state: the source's :158 VALUE guard makes $SecondarySqlInstance
    # sticky - once a record derives it, later records keep it and never derive their own.
    # Seeded on ContainsKey so a carried $null is restored too.
    if ($null -ne $__state -and $__state.ContainsKey('secondarySqlInstance') -and $null -ne $__state.secondarySqlInstance) {
        $SecondarySqlInstance = $__state.secondarySqlInstance
    }

    # DEF-011: re-seed the SCOPE-LOCAL interrupt latch so the body's own Test-FunctionInterrupt
    # resolves it exactly as it would have from the source's shared function scope. Without this a
    # begin-block Stop-Function stops interrupting and the teardown runs on input the source
    # refuses to act on. Probe-W4049InterruptLatchAcrossHops.ps1 measures all four cases.
    if ($null -ne $__state -and $__state.interruptLatch) {
        Set-Variable -Name "__dbatools_interrupt_function_78Q9VPrM6999g6zo24Qn83m09XF56InEn4hFrA8Fwhu5xJrs6r" -Value $true -Scope 0
    }

    # cross-record engine-state restore: the ShouldProcess Yes/No-to-All answer spans the
    # pipeline in the source (one CommandRuntime); the transplant field name is identical
    # on PS 5.1 and PS 7 (W3-082 mechanism, empirically verified)
    $__spField = $Pscmdlet.CommandRuntime.GetType().GetField("lastShouldProcessContinueStatus", [System.Reflection.BindingFlags]"NonPublic,Instance")
    if ($null -eq $__spField) {
        throw "Remove-DbaDbLogShipping: prompt-state transplant field lastShouldProcessContinueStatus not resolvable on this engine (C1 assert)."
    }
    if ($null -ne $__state -and $null -ne $__state.shouldProcessContinueStatus) {
        $__spField.SetValue($Pscmdlet.CommandRuntime, [Enum]::Parse($__spField.FieldType, $__state.shouldProcessContinueStatus))
    }

    . {
        if (Test-FunctionInterrupt) { return }

        foreach ($db in $Database) {
            if ($db -notin $primaryServer.Databases.Name) {
                Stop-Function -Message "Database [$db] does not exists on $primaryServer" -Target $db -Continue -FunctionName Remove-DbaDbLogShipping
            }

            # Get the log shipping information
            # Using LEFT JOIN to handle incomplete configurations where secondary setup failed
            $query = "SELECT pd.primary_database AS PrimaryDatabase,
                    ps.secondary_server AS SecondaryServer,
                    ps.secondary_database AS SecondaryDatabase
                FROM msdb.dbo.log_shipping_primary_databases AS pd
                    LEFT JOIN msdb.dbo.log_shipping_primary_secondaries AS ps
                        ON [pd].[primary_id] = [ps].[primary_id]
                WHERE pd.[primary_database] = '$db';"

            try {
                [array]$logshippingInfo = Invoke-DbaQuery -SqlInstance $primaryServer -SqlCredential $PrimarySqlCredential -Database msdb -Query $query
            } catch {
                Stop-Function -Message "Something went wrong retrieving the log shipping information" -Target $primaryServer -ErrorRecord $_ -FunctionName Remove-DbaDbLogShipping
            }

            if ($logshippingInfo.Count -lt 1) {
                Stop-Function -Message "Could not retrieve log shipping information for [$db]" -Target $db -Continue -FunctionName Remove-DbaDbLogShipping
            }

            # Determine if this is a complete or incomplete log shipping configuration
            $hasSecondary = $logshippingInfo[0].SecondaryServer -and $logshippingInfo[0].SecondaryDatabase

            # Only attempt secondary operations if we have a complete configuration
            if ($hasSecondary) {
                # Get the secondary server if it's not set
                if (-not $SecondarySqlInstance) {
                    $SecondarySqlInstance = $logshippingInfo.SecondaryServer
                }

                # Try connecting to the destination instance
                try {
                    $secondaryServer = Connect-DbaInstance -SqlInstance $SecondarySqlInstance -SqlCredential $SecondarySqlCredential
                } catch {
                    Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $SecondarySqlInstance -FunctionName Remove-DbaDbLogShipping
                    return
                }

                # Remove the primary secondaries log shipping
                if ($PSCmdlet.ShouldProcess("Removing the primary and secondaries from log shipping")) {
                    $query = "EXEC dbo.sp_delete_log_shipping_primary_secondary
                        @primary_database = N'$($logshippingInfo.PrimaryDatabase)',
                        @secondary_server = N'$($logshippingInfo.SecondaryServer)',
                        @secondary_database = N'$($logshippingInfo.SecondaryDatabase)'"

                    try {
                        Write-Message -Level verbose -Message "Removing the primary and secondaries from log shipping" -FunctionName Remove-DbaDbLogShipping -ModuleName "dbatools"
                        Invoke-DbaQuery -SqlInstance $primaryServer -SqlCredential $PrimarySqlCredential -Database master -Query $query
                    } catch {
                        Stop-Function -Message "Something went wrong removing the primaries and secondaries" -Target $primaryServer -ErrorRecord $_ -FunctionName Remove-DbaDbLogShipping
                    }
                }
            } else {
                Write-Message -Level Verbose -Message "No secondary configuration found for [$db]. Removing primary configuration only." -FunctionName Remove-DbaDbLogShipping -ModuleName "dbatools"
            }

            # Remove the primary database log shipping info
            if ($PSCmdlet.ShouldProcess("Removing the primary database from log shipping")) {
                $query = "EXEC dbo.sp_delete_log_shipping_primary_database @database = N'$($logshippingInfo.PrimaryDatabase)'"

                try {
                    Write-Message -Level verbose -Message "Removing the primary database from log shipping" -FunctionName Remove-DbaDbLogShipping -ModuleName "dbatools"
                    Invoke-DbaQuery -SqlInstance $primaryServer -SqlCredential $PrimarySqlCredential -Database master -Query $query
                } catch {
                    Stop-Function -Message "Something went wrong removing the primary database from log shipping" -Target $primaryServer -ErrorRecord $_ -FunctionName Remove-DbaDbLogShipping
                }
            }

            # Only remove secondary database configuration if we have a complete setup
            if ($hasSecondary) {
                # Remove the secondary database log shipping
                if ($PSCmdlet.ShouldProcess("Removing the secondary database from log shipping")) {
                    $query = "EXEC dbo.sp_delete_log_shipping_secondary_database @secondary_database = N'$($logshippingInfo.SecondaryDatabase)'"

                    try {
                        Write-Message -Level verbose -Message "Removing the secondary database from log shipping" -FunctionName Remove-DbaDbLogShipping -ModuleName "dbatools"
                        Invoke-DbaQuery -SqlInstance $secondaryServer -SqlCredential $SecondarySqlCredential -Database master -Query $query
                    } catch {
                        Stop-Function -Message "Something went wrong removing the secondary database from log shipping" -Target $secondaryServer -ErrorRecord $_ -FunctionName Remove-DbaDbLogShipping
                    }
                }

                # Remove the secondary database if needed
                if ($RemoveSecondaryDatabase) {
                    if ($PSCmdlet.ShouldProcess("Removing the secondary database from [$($logshippingInfo.SecondaryDatabase)]")) {
                        Write-Message -Level verbose -Message "Removing the secondary database [$($logshippingInfo.SecondaryDatabase)]" -FunctionName Remove-DbaDbLogShipping -ModuleName "dbatools"
                        try {
                            $null = Remove-DbaDatabase -SqlInstance $secondaryServer -SqlCredential $SecondarySqlCredential -Database $logshippingInfo.SecondaryDatabase -Confirm:$false
                        } catch {
                            Stop-Function -Message "Could not remove [$($logshippingInfo.SecondaryDatabase)] from $secondaryServer" -Target $secondaryServer -ErrorRecord $_ -Continue -FunctionName Remove-DbaDbLogShipping
                        }
                    }
                }
            }
        }
    }

    $__latchVar = Get-Variable -Name "__dbatools_interrupt_function_78Q9VPrM6999g6zo24Qn83m09XF56InEn4hFrA8Fwhu5xJrs6r" -Scope 0 -ErrorAction Ignore
    @{ __w4049State = @{ primaryServer = $primaryServer; interruptLatch = [bool]($__latchVar.Value); secondarySqlInstance = $SecondarySqlInstance; shouldProcessContinueStatus = $(if ($null -ne $__spField) { "$($__spField.GetValue($Pscmdlet.CommandRuntime))" } else { $null }) } }
} $PrimarySqlInstance $SecondarySqlInstance $PrimarySqlCredential $SecondarySqlCredential $Database $RemoveSecondaryDatabase $EnableException $__state $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
