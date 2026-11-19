#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Changes database recovery models. Port of public/Set-DbaDbRecoveryModel.ps1 (W3-089).
/// The process body rides one VERBATIM module hop per record; every record is
/// SELF-CONTAINED: the $InputObject += $databases accumulation is invocation-local (the
/// "Instance" set fires process once; piped "Pipeline" records rebind $InputObject), so
/// no sentinel and no rebind discriminator (the W3-074 shape). WHOLE-ARRAY EXEMPTION
/// from the P2A per-element rule: the $SqlInstance loop accumulates cross-loop state
/// (each iteration appends into $InputObject, consumed by the second loop after it), so
/// the hop stays whole-body per record. PARAMETER SETS mirrored from the baseline
/// including the PHANTOM default set: DefaultParameterSetName "Default" has NO member
/// parameters, so an invocation binding neither SqlInstance nor InputObject (e.g. only
/// -RecoveryModel) resolves to Default, both loops skip, and the command silently does
/// nothing - source quirk preserved. Quirks riding verbatim: $instance LEAKS out of the
/// first loop into the second (null/"" on the Pipeline path - the ShouldProcess target
/// interpolates to "$db on "); the already-set branch Stop-Functions with -Category
/// ConnectionError (source oddity) and -Continue; the no-Database/-AllDatabases check
/// sits INSIDE the instance loop AFTER the connect, and its `Stop-Function; return`
/// early-exits the whole process invocation (remaining instances AND the second loop
/// skip); the trailing Get-DbaDbRecoveryModel (still a FUNCTION) runs OUTSIDE the
/// ShouldProcess gate, so -WhatIf still emits the current model per database (the
/// .OUTPUTS note claiming otherwise documents an intent the code never had - shipped
/// behavior wins). $Pscmdlet.ShouldProcess routes to the REAL cmdlet (ConfirmImpact
/// HIGH mirrored). NO WarningAction carrier (codex W3-005 r3). Surface pinned by
/// migration/baselines/Set-DbaDbRecoveryModel.json (no positions, RecoveryModel
/// Mandatory ValidateSet Simple/Full/BulkLogged, InputObject Database[] Mandatory VFP
/// Pipeline-set).
/// </summary>
[Cmdlet(VerbsCommon.Set, "DbaDbRecoveryModel", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High, DefaultParameterSetName = "Default")]
public sealed class SetDbaDbRecoveryModelCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ParameterSetName = "Instance")]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The recovery model to set (Simple, Full or BulkLogged).</summary>
    [Parameter(Mandatory = true)]
    [PsStringCast]
    [ValidateSet("Simple", "Full", "BulkLogged")]
    public string? RecoveryModel { get; set; }

    /// <summary>The database(s) to change the recovery model for.</summary>
    [Parameter]
    public object[]? Database { get; set; }

    /// <summary>Database(s) to skip.</summary>
    [Parameter]
    public object[]? ExcludeDatabase { get; set; }

    /// <summary>Required safety switch to target all databases on the instance.</summary>
    [Parameter]
    public SwitchParameter AllDatabases { get; set; }

    /// <summary>SMO Database object(s), typically from Get-DbaDatabase.</summary>
    [Parameter(ValueFromPipeline = true, Mandatory = true, ParameterSetName = "Pipeline")]
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
            SqlInstance, SqlCredential, RecoveryModel, Database, ExcludeDatabase,
            AllDatabases.ToBool(), EnableException.ToBool(), InputObject, this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the ENTIRE process body VERBATIM per record. Substitutions only:
    // $Pscmdlet -> $__realCmdlet (source spells it $Pscmdlet) and explicit
    // -FunctionName Set-DbaDbRecoveryModel on Stop-Function/Write-Message (W1-090).
    // The tempdb-only exclusion comments, the leaked $instance, the ConnectionError
    // category on the already-set branch and the ungated trailing
    // Get-DbaDbRecoveryModel ride as-is.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $RecoveryModel, $Database, $ExcludeDatabase, $AllDatabases, $EnableException, $InputObject, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess)]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [string]$RecoveryModel, [object[]]$Database, [object[]]$ExcludeDatabase, $AllDatabases, $EnableException, [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    foreach ($instance in $SqlInstance) {
        try {
            $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Set-DbaDbRecoveryModel
        }

        if (!$Database -and !$AllDatabases -and !$ExcludeDatabase) {
            Stop-Function -Message "You must specify -AllDatabases or -Database to continue" -FunctionName Set-DbaDbRecoveryModel
            return
        }

        # We need to be able to change the RecoveryModel for model database
        $systemdbs = @("tempdb")
        $databases = $server.Databases | Where-Object { $systemdbs -notcontains $_.Name -and $_.IsAccessible -and -Not($_.IsDatabaseSnapshot) }

        # filter collection based on -Database/-Exclude parameters
        if ($Database) {
            $databases = $databases | Where-Object Name -In $Database
        }

        if ($ExcludeDatabase) {
            $databases = $databases | Where-Object Name -NotIn $ExcludeDatabase
        }

        if (!$databases) {
            Stop-Function -Message "The database(s) you specified do not exist on the instance $instance." -FunctionName Set-DbaDbRecoveryModel
            return
        }

        $InputObject += $databases
    }

    foreach ($db in $InputObject) {
        if ($db.RecoveryModel -eq $RecoveryModel) {
            Stop-Function -Message "Recovery Model for database $db is already set to $RecoveryModel" -Category ConnectionError -Target $instance -Continue -FunctionName Set-DbaDbRecoveryModel
        } else {
            if ($__realCmdlet.ShouldProcess("$db on $instance", "ALTER DATABASE $db SET RECOVERY $RecoveryModel")) {
                $db.RecoveryModel = $RecoveryModel
                $db.Alter()
                Write-Message -Level Verbose -Message "Recovery Model set to $RecoveryModel for database $db" -FunctionName Set-DbaDbRecoveryModel -ModuleName "dbatools"
            }
        }
        Get-DbaDbRecoveryModel -SqlInstance $db.Parent -Database $db.name
    }
} $SqlInstance $SqlCredential $RecoveryModel $Database $ExcludeDatabase $AllDatabases $EnableException $InputObject $__realCmdlet $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
