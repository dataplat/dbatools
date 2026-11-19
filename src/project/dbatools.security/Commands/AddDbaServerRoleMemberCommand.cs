#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Adds logins or server roles as members of server-level roles on one or more SQL Server instances.
/// </summary>
/// <remarks>
/// <para>
/// The workflow remains a module-scoped PowerShell compatibility hop so that role resolution,
/// SMO membership calls, warning text, and dbatools stream and error handling stay
/// observable-identical to the script implementation.
/// </para>
/// <para>
/// Three parameters accept pipeline input (SqlInstance, ServerRole and InputObject) and none of
/// them belong to a parameter set, so a single piped value binds to EVERY one of them that was not
/// already supplied as an argument. The body's type switch over each InputObject element is what
/// disambiguates the result; that behavior is reproduced here rather than corrected.
/// </para>
/// <para>
/// The InputObject value the begin block derived from SqlInstance is held as a field because each
/// record's hop gets a fresh scope that cannot see the previous record.
/// </para>
/// </remarks>
[Cmdlet(VerbsCommon.Add, "DbaServerRoleMember", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High)]
public sealed class AddDbaServerRoleMemberCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(ValueFromPipeline = true, Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The server-level role or roles that receive the new members.</summary>
    [Parameter(ValueFromPipeline = true, Position = 2)]
    public string[]? ServerRole { get; set; }

    /// <summary>The login or logins to add to the target server-level roles.</summary>
    [Parameter(Position = 3)]
    public string[]? Login { get; set; }

    /// <summary>The server-level role or roles to nest inside the target server-level roles.</summary>
    [Parameter(Position = 4)]
    public string[]? Role { get; set; }

    /// <summary>Server role objects, typically piped from Get-DbaServerRole or New-DbaServerRole.</summary>
    [Parameter(ValueFromPipeline = true, Position = 5)]
    public object[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    /// <summary>Set when the begin block stopped the command, suppressing every record.</summary>
    private bool _beginInterrupted;

    /// <summary>
    /// Whether SqlInstance and InputObject were bound as ARGUMENTS, captured before any record ran.
    /// </summary>
    private bool _sqlInstanceBoundAsArgument;
    private bool _inputObjectBoundAsArgument;

    /// <summary>
    /// The value the begin block assigned to InputObject from SqlInstance, held across records.
    /// </summary>
    private object[]? _beginInputObject;

    /// <summary>Validates the parameter combination once, before any pipeline record is processed.</summary>
    protected override void BeginProcessing()
    {
        // PowerShell binds pipeline parameters per record, so a function's begin block saw only the
        // parameters supplied as ARGUMENTS. Snapshot that set now: by ProcessRecord, BoundParameters
        // also contains whatever the current record bound, which would answer these tests differently.
        Hashtable boundAsArguments = new Hashtable(MyInvocation.BoundParameters);
        _sqlInstanceBoundAsArgument = boundAsArguments.ContainsKey(nameof(SqlInstance));
        _inputObjectBoundAsArgument = boundAsArguments.ContainsKey(nameof(InputObject));

        bool completed = false;
        foreach (PSObject? item in NestedCommand.InvokeScoped(this, BeginScript,
            _sqlInstanceBoundAsArgument, boundAsArguments.ContainsKey(nameof(ServerRole)),
            boundAsArguments.ContainsKey(nameof(Login)), EnableException.ToBool()))
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
            }
            else if (item is not null && LanguagePrimitives.IsTrue(
                item.Properties["__AddDbaServerRoleMemberBeginComplete"]?.Value))
            {
                completed = true;
            }
            else if (item is not null)
            {
                WriteObject(item);
            }
        }

        // The sentinel is the last statement of the begin body, so it is absent exactly when that
        // body returned early - which it does only after Stop-Function has stopped the command.
        _beginInterrupted = !completed;

        // The begin block's "$InputObject = $SqlInstance". It is kept out of the hop because a hop
        // scope dies with the record and this value must reach every record.
        if (_sqlInstanceBoundAsArgument)
        {
            _beginInputObject = SqlInstance;
        }
    }

    /// <summary>Adds the requested members for one pipeline record.</summary>
    protected override void ProcessRecord()
    {
        if (_beginInterrupted || Interrupted)
            return;

        // Reproduces what $InputObject actually held when the script's process block ran. The
        // precedence flips on how InputObject was supplied, because PowerShell will not re-bind a
        // parameter that was given as an argument:
        //   - given as an argument: no record can overwrite it, so the begin block's assignment
        //     from SqlInstance (which overwrote the argument in place) stands for every record;
        //   - not given as an argument: each record's binding overwrites the begin assignment, and
        //     the assignment only survives when there is no pipeline input at all.
        // Whether the begin block ASSIGNED is decided by the bound flag, never by testing the
        // assigned value for null: "-SqlInstance $null" is still BOUND, so the begin block
        // overwrites InputObject with that null and the command must go on to do nothing. Reading
        // the null as "no assignment" would fall back to the caller's -InputObject and add members
        // the script implementation never adds.
        object[]? effectiveInputObject;
        if (_inputObjectBoundAsArgument)
        {
            effectiveInputObject = _sqlInstanceBoundAsArgument ? _beginInputObject : InputObject;
        }
        else
        {
            effectiveInputObject = InputObject ?? _beginInputObject;
        }

        // [DEF-001] streamed via InvokeScopedStreaming: the body loops the members emitting per-add and
        // carries reachable terminating throws (-Continue Stop-Function under -EnableException); a
        // buffered InvokeScoped would lose an earlier member's emit when a later one throws. The
        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                return;
            }
            WriteObject(item);
        }, BodyScript,
            effectiveInputObject, SqlCredential, ServerRole, Login, Role,
            EnableException.ToBool(), this, TestBound(nameof(ServerRole)),
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the begin body VERBATIM. Substitutions only: each Test-Bound reads a carried flag because
    // Test-Bound inspects the CALLER's bound parameters and would see the hop's, and explicit
    // -FunctionName on Stop-Function. The "$InputObject = $SqlInstance" assignment is performed in
    // BeginProcessing instead, since a hop scope cannot carry it to the process records.
    private const string BeginScript = """
param($__boundSqlInstance, $__boundServerRole, $__boundLogin, $EnableException)
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    param($__boundSqlInstance, $__boundServerRole, $__boundLogin, $EnableException)

    if ( (-not $__boundSqlInstance) -and (-not $__boundServerRole) -and (-not $__boundLogin) ) {
        Stop-Function -Message "You must pipe in a ServerRole, Login, or specify a SqlInstance" -FunctionName Add-DbaServerRoleMember
        return
    }

    [pscustomobject]@{ __AddDbaServerRoleMemberBeginComplete = $true }
} $__boundSqlInstance $__boundServerRole $__boundLogin $EnableException 3>&1 2>&1
""";

    // PS: the ENTIRE process body VERBATIM per record. Substitutions only: $PSCmdlet ->
    // $__realCmdlet, the Test-Bound ServerRole test -> the carried per-record flag, and explicit
    // -FunctionName on Stop-Function/Write-Message. The body is dot-sourced so that its early
    // return leaves only that block and the trailing sentinel still reports the interrupt latch.
    //
    // Source behaviors reproduced deliberately - all four are load-bearing for compatibility and
    // must not be "repaired" here. A fix belongs in the script implementation first:
    //   * foreach ($input in ...) writes the automatic variable $input, exactly as the script did.
    //   * the ServerRole branch assigns $inputObject - the WHOLE array - not the current element,
    //     which only shows up when InputObject is passed directly with more than one element.
    //   * $l is a string, so $l.Name is null and the "already a member" test can never match:
    //     the warning is unreachable and AddMember is always attempted.
    //   * the two innermost Stop-Function calls pass neither -Continue nor a following return, so
    //     they set the interrupt latch and fall through to the next iteration with stale state.
    private const string BodyScript = """
param($InputObject, $SqlCredential, $ServerRole, $Login, $Role, $EnableException, $__realCmdlet, $__boundServerRole, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High")]
    param([object[]]$InputObject, [PSCredential]$SqlCredential, [string[]]$ServerRole, [string[]]$Login, [string[]]$Role, $EnableException, $__realCmdlet, $__boundServerRole, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    . {
        if (Test-FunctionInterrupt) { return }

        foreach ($input in $InputObject) {
            $inputType = $input.GetType().FullName

            if ((-not $__boundServerRole) -and ($inputType -ne 'Microsoft.SqlServer.Management.Smo.ServerRole')) {
                Stop-Function -Message "You must pipe in a ServerRole or specify a ServerRole." -FunctionName Add-DbaServerRoleMember
                return
            }

            switch ($inputType) {
                'Dataplat.Dbatools.Parameter.DbaInstanceParameter' {
                    Write-Message -Level Verbose -Message "Processing DbaInstanceParameter through InputObject" -FunctionName Add-DbaServerRoleMember -ModuleName "dbatools"
                    try {
                        $serverRoles = Get-DbaServerRole -SqlInstance $input -SqlCredential $SqlCredential -ServerRole $ServerRole -EnableException
                    } catch {
                        Stop-Function -Message "Failure access $input" -ErrorRecord $_ -Target $input -Continue -FunctionName Add-DbaServerRoleMember
                    }
                }
                'Microsoft.SqlServer.Management.Smo.Server' {
                    Write-Message -Level Verbose -Message "Processing Server through InputObject" -FunctionName Add-DbaServerRoleMember -ModuleName "dbatools"
                    try {
                        $serverRoles = Get-DbaServerRole -SqlInstance $input -SqlCredential $SqlCredential -ServerRole $ServerRole -EnableException
                    } catch {
                        Stop-Function -Message "Failure access $input" -ErrorRecord $_ -Target $input -Continue -FunctionName Add-DbaServerRoleMember
                    }
                }
                'Microsoft.SqlServer.Management.Smo.ServerRole' {
                    Write-Message -Level Verbose -Message "Processing ServerRole through InputObject" -FunctionName Add-DbaServerRoleMember -ModuleName "dbatools"
                    try {
                        $serverRoles = $inputObject
                    } catch {
                        Stop-Function -Message "Failure access $input" -ErrorRecord $_ -Target $input -Continue -FunctionName Add-DbaServerRoleMember
                    }
                }
                default {
                    Stop-Function -Message "InputObject is not a server or role." -FunctionName Add-DbaServerRoleMember
                    continue
                }
            }

            foreach ($sr in $serverRoles) {
                $instance = $sr.Parent
                foreach ($l in $Login) {
                    if ( $sr.EnumMemberNames().Contains($l.Name) ) {
                        Write-Message -Level Warning -Message "Login $l is already a member in server-level role: $sr" -FunctionName Add-DbaServerRoleMember -ModuleName "dbatools"
                        continue
                    } else {
                        if ($__realCmdlet.ShouldProcess($instance, "Adding login $l to server-level role: $sr")) {
                            Write-Message -Level Verbose -Message "Adding login $l to server-level role: $sr on $instance" -FunctionName Add-DbaServerRoleMember -ModuleName "dbatools"
                            try {
                                $sr.AddMember($l)
                            } catch {
                                Stop-Function -Message "Failure adding $l on $instance" -ErrorRecord $_ -Target $sr -FunctionName Add-DbaServerRoleMember
                            }
                        }
                    }
                }
                foreach ($r in $Role) {
                    try {
                        $isServerRole = Get-DbaServerRole -SqlInstance $input -SqlCredential $SqlCredential -ServerRole $r -EnableException
                    } catch {
                        Stop-Function -Message "Failure access $input" -ErrorRecord $_ -Target $input -FunctionName Add-DbaServerRoleMember
                        continue
                    }
                    if (-not $isServerRole) {
                        Write-Message -Level Warning -Message "$r server-level role was not found on $instance" -FunctionName Add-DbaServerRoleMember -ModuleName "dbatools"
                        continue
                    }
                    if ($__realCmdlet.ShouldProcess($instance, "Adding role $r to server-level role: $sr")) {
                        Write-Message -Level Verbose -Message "Adding role $r to server-level role: $sr on $instance" -FunctionName Add-DbaServerRoleMember -ModuleName "dbatools"
                        try {
                            $sr.AddMembershipToRole($r)
                        } catch {
                            Stop-Function -Message "Failure adding $r on $instance" -ErrorRecord $_ -Target $sr -FunctionName Add-DbaServerRoleMember
                        }
                    }
                }
            }
        }
    }
} $InputObject $SqlCredential $ServerRole $Login $Role $EnableException $__realCmdlet $__boundServerRole $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
