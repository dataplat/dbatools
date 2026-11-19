#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Reads the live transaction log of a database via fn_dblog. Port of
/// public/Read-DbaTransactionLog.ps1 (W2-156); the workflow remains a module-scoped PowerShell
/// compatibility hop.
///
/// STRUCTURALLY THE SIMPLEST SHAPE IN THIS DESCENT, and the first of its kind here: the source has
/// NO begin, process or end block at all. A function body with no named blocks is treated by
/// PowerShell as an END block, so the whole body runs ONCE, after any pipeline input is collected -
/// not once per record. The port therefore drives it from EndProcessing, not ProcessRecord. Nothing
/// here is pipeline-bound (no parameter declares ValueFromPipeline), so the two would behave alike
/// today, but EndProcessing is what the source actually is and a later parameter gaining pipeline
/// binding would make the difference real.
///
/// This is also the FIRST row in my descent with NO ShouldProcess at all. The baseline records
/// supportsShouldProcess false and confirmImpact None, so the [Cmdlet] attribute declares neither and
/// NO $__realCmdlet is passed. That is not an omission: the source's CmdletBinding carries only
/// DefaultParameterSetName, and adding SupportsShouldProcess would invent a -WhatIf/-Confirm surface
/// the command never had.
///
/// NO carries of any kind. There is no cross-block or cross-record state - one block, one execution -
/// so the hop's scope reset cannot change behaviour, and the pre-port DEF-012 check is clean in both
/// shapes. ZERO Test-Bound calls: every guard tests parameter VALUES or SMO state.
///
/// FOUR hard `return`s (connect failure, database missing, database not Normal, and the half-gigabyte
/// live-log refusal) all reproduce as returns inside the hop scriptblock, ending the body exactly as
/// the source's returns end the function. There is no `continue` anywhere, so NO continue-guard
/// wrapper is involved.
///
/// PARAMETER MUTATION, preserved: when -RowLimit is greater than zero the body sets
/// `$IgnoreLimit = $true`, overwriting the caller's own switch value, so a large -RowLimit silently
/// bypasses the size guard the caller may have deliberately left in place. Reproduced verbatim
/// because the hop passes the switch as a carried value the body is free to reassign; the mutation
/// stays local to the invocation, which is exactly what it does in the function.
///
/// -Database is typed `[object]` rather than string, matching the source and the baseline: the body
/// indexes `$server.databases[$Database]` and passes $Database to $server.Query as the database
/// context, both of which accept an SMO database object as readily as a name.
///
/// Only body edit is -FunctionName Read-DbaTransactionLog on the direct Stop-Function and
/// Write-Message sites.
///
/// Surface pinned by migration/baselines/Read-DbaTransactionLog.json
/// (sourceSha256 ef717a9cf2a2159da28611af9cc7a93395970fd9a60b066c82a24b7da9b7a138): supportsShouldProcess
/// FALSE, confirmImpact None, DefaultParameterSetName "Default", outputType empty; SqlInstance 0
/// MANDATORY, SqlCredential 1, Database 2 MANDATORY, RowLimit 3; IgnoreLimit and EnableException
/// non-positional switches. Positions declared explicitly per the positional-binding-loss class.
/// </summary>
[Cmdlet(VerbsCommunications.Read, "DbaTransactionLog", DefaultParameterSetName = "Default")]
public sealed class ReadDbaTransactionLogCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance.</summary>
    [Parameter(Mandatory = true, Position = 0)]
    public DbaInstanceParameter? SqlInstance { get; set; }

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The database whose transaction log is read. Untyped per the source - a name or an
    /// SMO database object both work.</summary>
    [Parameter(Mandatory = true, Position = 2)]
    public object? Database { get; set; }

    /// <summary>Skip the half-gigabyte live-log size guard.</summary>
    [Parameter]
    public SwitchParameter IgnoreLimit { get; set; }

    /// <summary>Return only the first N rows; any value above zero also bypasses the size guard.</summary>
    [Parameter(Position = 3)]
    public int RowLimit { get; set; } = 0;

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // The source has no named blocks, so its body IS an end block: it runs once, after pipeline
    // input, not per record. EndProcessing is the faithful mapping.
    protected override void EndProcessing()
    {
        if (Interrupted)
            return;

        foreach (PSObject? item in NestedCommand.InvokeScoped(this, BodyScript,
            SqlInstance, SqlCredential, Database, IgnoreLimit.ToBool(), RowLimit,
            EnableException.ToBool(),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                continue;
            }
            WriteObject(item);
        }
    }

    // PS: the whole function body verbatim - the source has no named blocks, so this is all of it.
    // Only edit is -FunctionName Read-DbaTransactionLog on the direct Stop-Function and Write-Message
    // sites. No $__realCmdlet: this command has no ShouldProcess gate.
    private const string BodyScript = """
param($SqlInstance, $SqlCredential, $Database, $IgnoreLimit, $RowLimit, $EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter]$SqlInstance, [PSCredential]$SqlCredential, [object]$Database, $IgnoreLimit, [int]$RowLimit, $EnableException, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    try {
        $server = Connect-DbaInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
    } catch {
        Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $SqlInstance -FunctionName Read-DbaTransactionLog
        return
    }

    if (-not $server.databases[$Database]) {
        Stop-Function -Message "$Database does not exist" -FunctionName Read-DbaTransactionLog
        return
    }

    if ('Normal' -notin ($server.databases[$Database].Status -split ',')) {
        Stop-Function -Message "$Database is not in a normal State, command will not run." -FunctionName Read-DbaTransactionLog
        return
    }

    if ($RowLimit -gt 0) {
        Write-Message -Message "Limiting results to $RowLimit rows" -Level Verbose -FunctionName Read-DbaTransactionLog -ModuleName "dbatools"
        $RowLimitSql = " TOP $RowLimit "
        $IgnoreLimit = $true
    } else {
        $RowLimitSql = ""
    }


    if ($IgnoreLimit) {
        Write-Message -Level Verbose -Message "Please be aware that ignoring the recommended limits may impact on the performance of the SQL Server database and the calling system" -FunctionName Read-DbaTransactionLog -ModuleName "dbatools"
    } else {
        #Warn if more than 0.5GB of live log. Dodgy conversion as SMO returns the value in an unhelpful format :(
        $SqlSizeCheck = "SELECT
                                SUM(FileProperty(sf.name,'spaceused')*8/1024) AS 'SizeMb'
                                FROM sys.sysfiles sf
                                WHERE CONVERT(INT,sf.status & 0x40) / 64=1"
        $TransLogSize = $server.Query($SqlSizeCheck, $Database)
        if ($TransLogSize.SizeMb -ge 500) {
            Stop-Function -Message "$Database has more than 0.5 Gb of live log data, returning this may have an impact on the database and the calling system. If you wish to proceed please rerun with the -IgnoreLimit switch" -FunctionName Read-DbaTransactionLog
            return
        }
    }

    $sql = "SELECT $RowLimitSql * FROM fn_dblog(NULL,NULL)"
    Write-Message -Level Debug -Message $sql -FunctionName Read-DbaTransactionLog -ModuleName "dbatools"
    Write-Message -Level Verbose -Message "Starting Log retrieval" -FunctionName Read-DbaTransactionLog -ModuleName "dbatools"
    $server.Query($sql, $Database)
} $SqlInstance $SqlCredential $Database $IgnoreLimit $RowLimit $EnableException $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
