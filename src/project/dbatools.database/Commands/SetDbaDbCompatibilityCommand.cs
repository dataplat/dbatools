#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Sets the compatibility level of one or more databases. Port of public/Set-DbaDbCompatibility.ps1;
/// the workflow remains a module-scoped PowerShell compatibility hop.
///
/// A process-only port carrying THREE bound flags from two Test-Bound statements:
///     Test-Bound -not 'SqlInstance', 'InputObject'  -> (-not $__boundSqlInstance) -and (-not $__boundInputObject)
///     Test-Bound -ParameterName 'Compatibility'     -> $__boundCompatibility
/// The -not multi-name form is true only when NEITHER name is bound, which is why it renders as a
/// conjunction of negations rather than "either unbound". The Compatibility flag is behavioural, not
/// merely defensive: when the caller did not supply it the body DERIVES the target level from the
/// server's own major version, so a truthiness test would mis-handle a deliberately-passed default
/// enum value.
///
/// NO CONTINUE-GUARD WRAPPER - and that decision is MEASURED, not assumed. I first shipped this row
/// WITH the usual `foreach ($__continueGuard in @(1)) { ... }` wrapper, because the guard at the top
/// of process ends in a bare `continue` with no enclosing loop. Review challenged it and the
/// measurement proved the challenge right, so the wrapper was removed.
///
/// What the source actually does: that bare `continue` is non-local PowerShell flow control. It does
/// NOT merely end the record - it escapes the function entirely, bypassing try/catch (a surrounding
/// catch never fires). Called from a plain script it unwinds the CALLER'S SCRIPT silently; called
/// inside a caller's loop it continues THAT loop.
///
/// What the wrapper did: absorbed the signal, so the call returned normally and the caller carried
/// on. Sane - and therefore wrong, because it silently repaired a source bug the campaign requires
/// be preserved.
///
/// Measured both ways with DBATOOLS_LEGACY_FUNCTIONS, calling with no arguments so the guard fires:
///                          outside a caller loop        inside foreach 1..3
///   legacy function        script unwound after call    enter1,enter2,enter3 (no "after")
///   WITH wrapper           call returns, script ends    all three iterations complete
///   WITHOUT wrapper        script unwound after call    enter1,enter2,enter3 (no "after")
/// The signal propagates out of the hop scriptblock and across the cmdlet invocation intact, so
/// faithful reproduction was possible all along and the wrapper was the only thing preventing it.
///
/// The lesson generalises beyond this row: a continue-guard is only ever ADDED where a bare continue
/// has no enclosing loop, which is exactly the case where the source escapes to the caller - so the
/// wrapper always changes behaviour where it is applied. It is not a neutral compatibility shim.
/// Raised to the coordinator as a class question; the underlying source behaviour (a command that
/// silently kills the caller's script with no catchable error) is logged upstream separately.
///
/// The Stop-Function -Continue site inside `foreach ($db in $InputObject)` has its own real loop and
/// was never part of this question.
///
/// ShouldProcess is real (baseline: supportsShouldProcess true, confirmImpact Medium), so
/// $PSCmdlet.ShouldProcess(...) becomes $__realCmdlet.ShouldProcess(...) with the target and action
/// strings byte-for-byte.
///
/// $InputObject is APPENDED to (`$InputObject += Get-DbaDatabase ...`), not reassigned, so a caller
/// may pipe databases AND name an instance and get both sets - preserved verbatim.
///
/// Pre-port cross-record scope check (tools/Find-CrossRecordScopeReliance.ps1) returns NO hits for
/// this body: nothing here reads a process local before assigning it, so the per-record scope reset
/// that a hop imposes cannot change behaviour. Run on the source BEFORE porting, per the class
/// opened by W2-180.
///
/// Other body edits are -FunctionName Set-DbaDbCompatibility attribution stamping on the direct
/// Write-Message and Stop-Function sites.
///
/// Surface pinned by migration/baselines/Set-DbaDbCompatibility.json
/// (sourceSha256 6ee187bba92c4887361512ff445b1a62f3efc0ba46ae3bf3d57e2df8a8cb9e8f):
/// SqlInstance 0, SqlCredential 1, Database 2, Compatibility 3, InputObject 4 ValueFromPipeline;
/// no parameter sets; outputType empty. Positions are declared explicitly per the
/// positional-binding-loss class.
/// </summary>
[Cmdlet(VerbsCommon.Set, "DbaDbCompatibility", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
public sealed class SetDbaDbCompatibilityCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The database(s) to process.</summary>
    [Parameter(Position = 2)]
    public string[]? Database { get; set; }

    /// <summary>Target compatibility level; derived from the server version when omitted.</summary>
    [Parameter(Position = 3)]
    public Microsoft.SqlServer.Management.Smo.CompatibilityLevel Compatibility { get; set; }

    /// <summary>Database object(s) piped in.</summary>
    [Parameter(ValueFromPipeline = true, Position = 4)]
    public Microsoft.SqlServer.Management.Smo.Database[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    protected override void ProcessRecord()
    {
        if (Interrupted)
            return;

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                return;
            }
            WriteObject(item);
        }, ProcessScript,
            SqlInstance, SqlCredential, Database, Compatibility, InputObject,
            EnableException.ToBool(),
            TestBound(nameof(SqlInstance)), TestBound(nameof(InputObject)), TestBound(nameof(Compatibility)),
            this, NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the process block verbatim inside the module-scoped hop scriptblock - NO continue-guard
    // wrapper, deliberately (see the class remarks). Edits: the two Test-Bound reads -> carried
    // bound flags, $PSCmdlet -> $__realCmdlet, and -FunctionName Set-DbaDbCompatibility on the
    // direct Write-Message and Stop-Function sites.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Database, $Compatibility, $InputObject, $EnableException, $__boundSqlInstance, $__boundInputObject, $__boundCompatibility, $__realCmdlet, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [string[]]$Database, [Microsoft.SqlServer.Management.Smo.CompatibilityLevel]$Compatibility, [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject, $EnableException, $__boundSqlInstance, $__boundInputObject, $__boundCompatibility, $__realCmdlet, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    # NO continue-guard wrapper here, DELIBERATELY - see the class remarks. The bare continue below
    # must keep escaping to the caller, exactly as the source's does.
        if ((-not $__boundSqlInstance) -and (-not $__boundInputObject)) {
            Write-Message -Level Warning -Message 'You must specify either a SQL instance or pipe a database collection' -FunctionName Set-DbaDbCompatibility -ModuleName "dbatools"
            continue
        }

        if ($SqlInstance) {
            $InputObject += Get-DbaDatabase -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database
        }

        foreach ($db in $InputObject) {
            $server = $db.Parent
            $dbLevel = $db.CompatibilityLevel
            Write-Message -Level Verbose -Message "Database $db current Compatibility Level: $dbLevel" -FunctionName Set-DbaDbCompatibility -ModuleName "dbatools"

            if ($__boundCompatibility) {
                $targetCompatibility = $Compatibility
            } else {
                $serverVersion = $server.VersionMajor
                $targetCompatibility = [Microsoft.SqlServer.Management.Smo.CompatibilityLevel]"Version$($serverVersion)0"
                Write-Message -Level Verbose -Message "No Compatibility value provided, setting databases to match the SQL Server Instance version: $targetCompatibility" -FunctionName Set-DbaDbCompatibility -ModuleName "dbatools"
            }

            if ($dbLevel -ne $targetCompatibility) {
                if ($__realCmdlet.ShouldProcess($server.Name, "Setting $db Compatibility Level to $targetCompatibility")) {
                    try {
                        $db.CompatibilityLevel = $targetCompatibility
                        $db.Alter()

                        [PSCustomObject]@{
                            ComputerName          = $server.ComputerName
                            InstanceName          = $server.ServiceName
                            SqlInstance           = $server.DomainInstanceName
                            Database              = $db.Name
                            Compatibility         = $db.CompatibilityLevel
                            PreviousCompatibility = $dbLevel
                        }
                    } catch {
                        Stop-Function -Message 'Failed to change Compatibility Level' -ErrorRecord $_ -Target $db -Continue -FunctionName Set-DbaDbCompatibility
                    }
                }
            } else {
                Write-Message -Level Verbose -Message "Database $db current Compatibility Level matches target level [$targetCompatibility]" -FunctionName Set-DbaDbCompatibility -ModuleName "dbatools"
            }
        }
} $SqlInstance $SqlCredential $Database $Compatibility $InputObject $EnableException $__boundSqlInstance $__boundInputObject $__boundCompatibility $__realCmdlet $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
