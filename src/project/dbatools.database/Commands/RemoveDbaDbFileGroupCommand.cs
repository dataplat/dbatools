#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Drops empty filegroups from one or more databases. Port of public/Remove-DbaDbFileGroup.ps1
/// (W2-160); the workflow remains a module-scoped PowerShell compatibility hop.
///
/// Direct sibling of W2-182 Set-DbaDbFileGroup, already ported in this satellite: same two-phase
/// process body (collect filegroups from either Database or FileGroup input, then act on the
/// collection), same -InputObject duality, same Test-Bound guards. The differences are that this one
/// DROPS rather than alters, carries THREE Test-Bound reads instead of six, and gates once instead of
/// once-per-property.
///
/// THREE Test-Bound reads become THREE carried flags:
///     Test-Bound -ParameterName SqlInstance    -> $__boundSqlInstance
///     Test-Bound -Not -ParameterName Database  -> -not $__boundDatabase
///     Test-Bound -Not -ParameterName FileGroup -> -not $__boundFileGroup
/// All three are was-it-SUPPLIED tests that scope-walk the caller and therefore cannot ride the hop.
/// The FileGroup one fires per piped Database object rather than once up front, which is why it must
/// be carried per record. NOTE ON ITS SEMANTICS, corrected after review caught me asserting the
/// opposite: `Test-Bound -Not` is FALSE when the parameter WAS supplied, so an explicitly passed
/// EMPTY -FileGroup does NOT take the "Filegroup is required" path - it falls through and silently
/// iterates nothing. That is the source's behaviour and the port reproduces it; only an UNBOUND
/// -FileGroup trips the guard.
///
/// -InputObject is deliberately object[] rather than a typed Database[]: the body accepts BOTH
/// Smo.Database and Smo.FileGroup objects and discriminates with -is, so narrowing the type would
/// break the FileGroup-piped path. Same reasoning as the W2-182 sibling.
///
/// NO continue-guard wrapper. The single early exit is a plain `return`, and all four
/// Stop-Function -Continue sites sit inside genuine enclosing foreach loops (over $InputObject, over
/// $FileGroup, and over $fileGroupsToDrop), so every continue has a real loop to continue.
///
/// NO state carry. There is no begin or end block and $fileGroupsToDrop is initialised at the top of
/// process and consumed in the same record, so the hop's per-record scope reset cannot change
/// behaviour. The pre-port DEF-012 check is clean in both shapes, and here that is meaningful rather
/// than a scope artifact, because there is no other block for a carry to hide in.
///
/// ShouldProcess is real at HIGH impact, so $Pscmdlet.ShouldProcess becomes
/// $__realCmdlet.ShouldProcess with target and action byte-for-byte, and the hop carries
/// -WhatIf/-Confirm explicitly.
///
/// PRESERVED SOURCE BEHAVIOUR worth noting for reviewers: the not-empty check uses
/// Stop-Function -Continue WITHOUT a preceding gate, so a non-empty filegroup produces a warning and
/// is skipped before ShouldProcess is ever consulted - meaning -WhatIf reports nothing for it. That
/// is the source's ordering and is reproduced as-is.
///
/// Only other body edit is -FunctionName Remove-DbaDbFileGroup on the five direct Stop-Function sites.
///
/// Surface pinned by migration/baselines/Remove-DbaDbFileGroup.json
/// (sourceSha256 fb91adf6208556f410270aaa63b6675561f37ced2b7f0b5850ff18ec828e9974): no named parameter
/// sets; SqlInstance 0, SqlCredential 1, Database 2, FileGroup 3, InputObject 4 ValueFromPipeline;
/// outputType empty. Positions declared explicitly per the positional-binding-loss class.
/// </summary>
[Cmdlet(VerbsCommon.Remove, "DbaDbFileGroup", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High)]
public sealed class RemoveDbaDbFileGroupCommand : DbaBaseCmdlet
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

    /// <summary>The filegroup(s) to drop.</summary>
    [Parameter(Position = 3)]
    public string[]? FileGroup { get; set; }

    /// <summary>Database or FileGroup object(s) piped in.</summary>
    [Parameter(ValueFromPipeline = true, Position = 4)]
    public object[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    protected override void ProcessRecord()
    {

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
            SqlInstance, SqlCredential, Database, FileGroup, InputObject, EnableException.ToBool(),
            TestBound(nameof(SqlInstance)), TestBound(nameof(Database)), TestBound(nameof(FileGroup)),
            this, NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the process block verbatim. Edits: the three Test-Bound reads -> carried bound flags,
    // $Pscmdlet -> $__realCmdlet, and -FunctionName Remove-DbaDbFileGroup on the direct
    // Stop-Function sites.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Database, $FileGroup, $InputObject, $EnableException, $__boundSqlInstance, $__boundDatabase, $__boundFileGroup, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High")]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [string[]]$Database, [string[]]$FileGroup, [object[]]$InputObject, $EnableException, $__boundSqlInstance, $__boundDatabase, $__boundFileGroup, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    if ($__boundSqlInstance -and (-not $__boundDatabase)) {
        Stop-Function -Message "Database is required when SqlInstance is specified" -FunctionName Remove-DbaDbFileGroup
        return
    }

    foreach ($instance in $SqlInstance) {
        $InputObject += Get-DbaDatabase -SqlInstance $instance -SqlCredential $SqlCredential -Database $Database
    }

    $fileGroupsToDrop = @()

    foreach ($obj in $InputObject) {

        if ($obj -is [Microsoft.SqlServer.Management.Smo.Database]) {

            if (-not $__boundFileGroup) {
                Stop-Function -Message "Filegroup is required" -Continue -FunctionName Remove-DbaDbFileGroup
            }

            foreach ($fg in $FileGroup) {

                if ($obj.FileGroups.Name -notcontains $fg) {
                    Stop-Function -Message "Filegroup $fg does not exist in the database $($obj.Name) on $($obj.Parent.Name)" -Continue -FunctionName Remove-DbaDbFileGroup
                }

                $fileGroupsToDrop += $obj.FileGroups[$fg]
            }

        } elseif ($obj -is [Microsoft.SqlServer.Management.Smo.FileGroup]) {
            $fileGroupsToDrop += $obj
        }
    }

    foreach ($fgToDrop in $fileGroupsToDrop) {

        if ($fgToDrop.Files.Count -gt 0) {
            Stop-Function -Message "Filegroup $($fgToDrop.Name) is not empty. Before the filegroup can be dropped the files must be removed in $($fgToDrop.Name) on $($fgToDrop.Parent.Name) on $($fgToDrop.Parent.Parent.Name)" -Continue -FunctionName Remove-DbaDbFileGroup
        }

        if ($__realCmdlet.ShouldProcess($fgToDrop.Parent.Parent.Name, "Removing the filegroup $($fgToDrop.Name) on the database $($fgToDrop.Parent.Name) on $($fgToDrop.Parent.Parent.Name)")) {
            try {
                $fgToDrop.Drop()
            } catch {
                Stop-Function -Message "Failure on $($fgToDrop.Parent.Parent.Name) to remove the filegroup $($fgToDrop.Name) in the database $($fgToDrop.Parent.Name)" -ErrorRecord $_ -Continue -FunctionName Remove-DbaDbFileGroup
            }
        }
    }
} $SqlInstance $SqlCredential $Database $FileGroup $InputObject $EnableException $__boundSqlInstance $__boundDatabase $__boundFileGroup $__realCmdlet $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}

