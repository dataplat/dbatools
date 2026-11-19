#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Sets database ownership. Port of public/Set-DbaDbOwner.ps1 (W3-088). The process body
/// rides one VERBATIM module hop per record inside a DOT-SOURCED inner block (the
/// no-input validation is a `Stop-Function; return` early exit that re-fires per
/// record). DUAL ValueFromPipeline binding preserved: BOTH SqlInstance and InputObject
/// are VFP - the binder disambiguates piped records by type exactly like the function.
/// CROSS-RECORD QUIRK preserved via the __w3088State sentinel: an UNBOUND $TargetLogin
/// is mutated in-loop to the first server's sa-equivalent login (id = 1) and the
/// function-scope value persists into later records - later piped servers REUSE the
/// first resolution instead of re-resolving (source behavior). The $InputObject +=
/// Get-DbaDatabase accumulation ALSO crosses records (B batch [P1]): the engine
/// restores only PIPELINE-BOUND params, so with instances piped record-by-record the
/// source re-processes earlier records' databases; the sentinel carries the
/// accumulated array and ProcessRecord restores it unless InputObject was piped
/// this record.
/// $PSCmdlet.ShouldProcess routes to the REAL cmdlet (W1-085, default ConfirmImpact
/// Medium); the two explicit `-EnableException $EnableException` Stop-Function calls,
/// the system-db/inaccessible skips, the ownership-validation warning ladder, the
/// SMO-#8528 `$null = $db.Owner` priming and the forced $db.Alter() ride verbatim. NO
/// WarningAction carrier (codex W3-005 r3). Surface pinned by
/// migration/baselines/Set-DbaDbOwner.json (implicit positions 0-5, TargetLogin Alias
/// Login, dual VFP).
/// </summary>
[Cmdlet(VerbsCommon.Set, "DbaDbOwner", SupportsShouldProcess = true)]
public sealed class SetDbaDbOwnerCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(ValueFromPipeline = true, Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The database(s) to process.</summary>
    [Parameter(Position = 2)]
    public object[]? Database { get; set; }

    /// <summary>Database(s) to exclude.</summary>
    [Parameter(Position = 3)]
    public object[]? ExcludeDatabase { get; set; }

    /// <summary>SMO Database object(s), typically from Get-DbaDatabase.</summary>
    [Parameter(ValueFromPipeline = true, Position = 4)]
    public Microsoft.SqlServer.Management.Smo.Database[]? InputObject { get; set; }

    /// <summary>The login to set as owner; defaults to the sa-equivalent (id 1).</summary>
    [Parameter(Position = 5)]
    [Alias("Login")]
    public string? TargetLogin { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // Cross-record $TargetLogin mutation (unbound resolves once and persists) PLUS the
    // cross-record $InputObject accumulation (B batch finding [P1], coordinator
    // preserve-source-verbatim ruling): the source's `$InputObject += Get-DbaDatabase`
    // mutates the fn-scope param, and PowerShell restores ONLY pipeline-bound
    // parameters between records - so when SqlInstance is the piped param, $InputObject
    // is never restored and ACCUMULATES (record 2 re-processes record 1's databases).
    // The hop scope dies per record, so the accumulated value rides the sentinel and is
    // restored EXCEPT when InputObject was pipeline-bound THIS record (mirroring the
    // engine's restore semantics exactly).
    private Hashtable? _state;
    private bool _inputObjectNamedAtBegin;
    private object? _inputObjectPrePipeline;

    /// <inheritdoc />
    protected override void BeginProcessing()
    {
        base.BeginProcessing();
        // Named parameters are bound before the pipeline starts; anything appearing in
        // BoundParameters later but not now arrived through the pipeline. The engine
        // RESTORES a pipeline-bound parameter to this pre-pipeline value after each
        // piped record, so it is also the reset target for the carried accumulation.
        _inputObjectNamedAtBegin = MyInvocation.BoundParameters.ContainsKey("InputObject");
        _inputObjectPrePipeline = InputObject;
    }

    protected override void ProcessRecord()
    {
        if (Interrupted)
            return;

        bool inputObjectPipedThisRecord = !_inputObjectNamedAtBegin &&
            MyInvocation.BoundParameters.ContainsKey("InputObject");
        object? effectiveInputObject = InputObject;
        if (!inputObjectPipedThisRecord && _state is not null && _state.ContainsKey("InputObject"))
            effectiveInputObject = _state["InputObject"];

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            Hashtable? sentinel = item?.BaseObject as Hashtable;
            if (sentinel is not null && sentinel.ContainsKey("__w3088State"))
            {
                _state = sentinel["__w3088State"] as Hashtable;
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
            SqlInstance, SqlCredential, Database, ExcludeDatabase, effectiveInputObject,
            TargetLogin, EnableException.ToBool(), _state, this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));

        // Engine restore semantics: after a record where InputObject was PIPELINE-bound,
        // the fn-scope variable snaps back to its pre-pipeline value - any accumulation
        // from earlier records is discarded. Mirror that by resetting the carried value.
        if (inputObjectPipedThisRecord && _state is not null)
            _state["InputObject"] = _inputObjectPrePipeline;
    }

    // PS: the ENTIRE process body VERBATIM per record inside a dot-sourced block.
    // Substitutions only: $PSCmdlet -> $__realCmdlet, explicit -FunctionName
    // Set-DbaDbOwner on Stop-Function/Write-Message (W1-090), and the cross-record
    // $TargetLogin restore/carry through the sentinel. The explicit -EnableException
    // $EnableException arguments, the SMO-#8528 priming and the why-comments ride as-is.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Database, $ExcludeDatabase, $InputObject, $TargetLogin, $EnableException, $__state, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess)]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [object[]]$Database, [object[]]$ExcludeDatabase, [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject, [string]$TargetLogin, $EnableException, $__state, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    # cross-record quirk restore: an unbound $TargetLogin resolved by an earlier record
    # persists (the source mutates the fn-scope param)
    if ($null -ne $__state) {
        $TargetLogin = $__state.TargetLogin
    }

    . {
        if (-not $InputObject -and -not $SqlInstance) {
            Stop-Function -Message "You must pipe in a database or specify a SqlInstance" -FunctionName Set-DbaDbOwner
            return
        }

        if ($SqlInstance) {
            $InputObject += Get-DbaDatabase -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database -ExcludeDatabase $ExcludeDatabase
        }

        foreach ($db in $InputObject) {
            # Exclude system databases
            if ($db.IsSystemObject) {
                continue
            }
            if (!$db.IsAccessible) {
                Write-Message -Level Warning -Message "Database $db is not accessible. Skipping." -FunctionName Set-DbaDbOwner -ModuleName "dbatools"
                continue
            }

            $server = $db.Parent
            $instance = $server.Name

            # dynamic sa name for orgs who have changed their sa name
            if (!$TargetLogin) {
                $TargetLogin = ($server.logins | Where-Object { $_.id -eq 1 }).Name
            }

            #Validate login
            if (($server.Logins.Name) -notcontains $TargetLogin) {
                Stop-Function -Message "$TargetLogin is not a valid login on $instance. Moving on." -Continue -EnableException $EnableException -FunctionName Set-DbaDbOwner
            }

            #Owner cannot be a group
            $TargetLoginObject = $server.Logins | Where-Object { $PSItem.Name -eq $TargetLogin } | Select-Object -property  Name, LoginType
            if ($TargetLoginObject.LoginType -eq 'WindowsGroup') {
                Stop-Function -Message "$TargetLogin is a group, therefore can't be set as owner. Moving on." -Continue -EnableException $EnableException -FunctionName Set-DbaDbOwner
            }

            $dbName = $db.name
            if ($__realCmdlet.ShouldProcess($instance, "Setting database owner for $dbName to $TargetLogin")) {
                try {
                    Write-Message -Level Verbose -Message "Setting database owner for $dbName to $TargetLogin on $instance." -FunctionName Set-DbaDbOwner -ModuleName "dbatools"
                    # Set database owner to $TargetLogin (default 'sa')
                    # Ownership validations checks

                    if ($db.Status -notmatch 'Normal') {
                        Write-Message -Level Warning -Message "$dbName on $instance is in a  $($db.Status) state and can not be altered. It will be skipped." -FunctionName Set-DbaDbOwner -ModuleName "dbatools"
                    }
                    #Database is updatable, not read-only
                    elseif ($db.IsUpdateable -eq $false) {
                        Write-Message -Level Warning -Message "$dbName on $instance is not in an updateable state and can not be altered. It will be skipped." -FunctionName Set-DbaDbOwner -ModuleName "dbatools"
                    }
                    #Is the login mapped as a user? Logins already mapped in the database can not be the owner
                    elseif ($db.Users.name -contains $TargetLogin) {
                        Write-Message -Level Warning -Message "$dbName on $instance has $TargetLogin as a mapped user. Mapped users can not be database owners." -FunctionName Set-DbaDbOwner -ModuleName "dbatools"
                    } else {
                        # Make sure the Owner property in the SMO is filled befor the change. See #8528 for details.
                        $null = $db.Owner
                        $db.SetOwner($TargetLogin)
                        # The used version of the SMO does not update the .Owner property, so we have to force this:
                        $db.Alter()
                        [PSCustomObject]@{
                            ComputerName = $server.ComputerName
                            InstanceName = $server.ServiceName
                            SqlInstance  = $server.DomainInstanceName
                            Database     = $dbName
                            Owner        = $TargetLogin
                        }
                    }
                } catch {
                    Stop-Function -Message "Failure updating owner." -ErrorRecord $_ -Target $instance -Continue -FunctionName Set-DbaDbOwner
                }
            }
        }
    }

    @{ __w3088State = @{ TargetLogin = $TargetLogin; InputObject = $InputObject } }
} $SqlInstance $SqlCredential $Database $ExcludeDatabase $InputObject $TargetLogin $EnableException $__state $__realCmdlet $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
