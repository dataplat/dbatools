#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Sets filegroup options (default, read-only, autogrow-all-files) on one or more filegroups. Port of
/// public/Set-DbaDbFileGroup.ps1; the workflow remains a module-scoped PowerShell compatibility hop.
///
/// A process-only port with the heaviest Test-Bound load in this satellite descent: SIX Test-Bound
/// calls across five statements, every one of which scope-walks the caller and therefore cannot ride
/// the hop. Each is flag-substituted from a carried value computed in C#:
///     Test-Bound -ParameterName SqlInstance          -> $__boundSqlInstance
///     Test-Bound -Not -ParameterName Database        -> -not $__boundDatabase
///     Test-Bound -Not -ParameterName FileGroup       -> -not $__boundFileGroup
///     Test-Bound Default                             -> $__boundDefault
///     Test-Bound ReadOnly                            -> $__boundReadOnly
///     Test-Bound AutoGrowAllFiles                    -> $__boundAutoGrowAllFiles
/// The three switch flags matter for behavior, not just guarding: the source only assigns
/// IsDefault / ReadOnly / AutogrowAllFiles when the caller actually SUPPLIED that switch, so a
/// naive "if ($ReadOnly)" rewrite would silently stop clearing a property with -ReadOnly:$false.
///
/// ShouldProcess is real (baseline: supportsShouldProcess true, confirmImpact High), so
/// $Pscmdlet.ShouldProcess(...) becomes $__realCmdlet.ShouldProcess(...) with the target and action
/// strings byte-for-byte, keeping -WhatIf and -Confirm behavior identical on a High-impact command.
///
/// NO continue-guard wrapper is needed. The body has four Stop-Function -Continue sites, and every
/// one of them sits inside a genuine enclosing foreach (over $InputObject, over $FileGroup, and twice
/// over $fileGroupsToModify), so the continue has a real loop to continue - unlike the guard-with-no-
/// loop case that forces the wrapper elsewhere. The single early `return` is a plain process-block
/// return, which a return inside the hop scriptblock reproduces.
///
/// -InputObject is deliberately Object[] rather than a typed Database[]: the body accepts BOTH
/// Smo.Database and Smo.FileGroup objects and discriminates with -is, so narrowing the type would
/// break the FileGroup-piped path.
///
/// Only other body edit is -FunctionName Set-DbaDbFileGroup on the direct Stop-Function sites.
///
/// Surface pinned by migration/baselines/Set-DbaDbFileGroup.json: SqlInstance 0, SqlCredential 1,
/// Database 2, FileGroup 3, InputObject 4 ValueFromPipeline; Default / ReadOnly / AutoGrowAllFiles
/// are non-positional switches; no parameter sets; outputType empty.
/// </summary>
[Cmdlet(VerbsCommon.Set, "DbaDbFileGroup", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High)]
public sealed class SetDbaDbFileGroupCommand : DbaBaseCmdlet
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

    /// <summary>The filegroup(s) to modify.</summary>
    [Parameter(Position = 3)]
    public string[]? FileGroup { get; set; }

    /// <summary>Make the filegroup the default.</summary>
    [Parameter]
    public SwitchParameter Default { get; set; }

    /// <summary>Set the filegroup read-only state.</summary>
    [Parameter]
    public SwitchParameter ReadOnly { get; set; }

    /// <summary>Set the autogrow-all-files state.</summary>
    [Parameter]
    public SwitchParameter AutoGrowAllFiles { get; set; }

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
            SqlInstance, SqlCredential, Database, FileGroup,
            Default.ToBool(), ReadOnly.ToBool(), AutoGrowAllFiles.ToBool(),
            InputObject, EnableException.ToBool(),
            TestBound(nameof(SqlInstance)), TestBound(nameof(Database)), TestBound(nameof(FileGroup)),
            TestBound(nameof(Default)), TestBound(nameof(ReadOnly)), TestBound(nameof(AutoGrowAllFiles)),
            this, NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the process block verbatim. Edits: the six Test-Bound reads -> carried bound flags,
    // $Pscmdlet -> $__realCmdlet so the gate is the real cmdlet, and -FunctionName Set-DbaDbFileGroup
    // on the direct Stop-Function sites.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Database, $FileGroup, $Default, $ReadOnly, $AutoGrowAllFiles, $InputObject, $EnableException, $__boundSqlInstance, $__boundDatabase, $__boundFileGroup, $__boundDefault, $__boundReadOnly, $__boundAutoGrowAllFiles, $__realCmdlet, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [string[]]$Database, [string[]]$FileGroup, $Default, $ReadOnly, $AutoGrowAllFiles, [object[]]$InputObject, $EnableException, $__boundSqlInstance, $__boundDatabase, $__boundFileGroup, $__boundDefault, $__boundReadOnly, $__boundAutoGrowAllFiles, $__realCmdlet, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    if ($__boundSqlInstance -and (-not $__boundDatabase)) {
        Stop-Function -Message "Database is required when SqlInstance is specified" -FunctionName Set-DbaDbFileGroup
        return
    }

    foreach ($instance in $SqlInstance) {
        $InputObject += Get-DbaDatabase -SqlInstance $instance -SqlCredential $SqlCredential -Database $Database
    }

    $fileGroupsToModify = @()

    foreach ($obj in $InputObject) {

        if ($obj -is [Microsoft.SqlServer.Management.Smo.Database]) {

            if (-not $__boundFileGroup) {
                Stop-Function -Message "Filegroup is required" -Continue -FunctionName Set-DbaDbFileGroup
            }

            foreach ($fg in $FileGroup) {

                if ($obj.FileGroups.Name -notcontains $fg) {
                    Stop-Function -Message "Filegroup $fg does not exist in the database $($obj.Name) on $($obj.Parent.Name)" -Continue -FunctionName Set-DbaDbFileGroup
                }

                $fileGroupsToModify += $obj.FileGroups[$fg]
            }
        } elseif ($obj -is [Microsoft.SqlServer.Management.Smo.FileGroup]) {
            $fileGroupsToModify += $obj
        }
    }

    foreach ($fgToModify in $fileGroupsToModify) {

        if ($fgToModify.Files.Count -eq 0) {
            Stop-Function -Message "Filegroup $FileGroup is empty on $($obj.Name) on $($obj.Parent.Name). Before the options can be set there must be at least one file in the filegroup." -Continue -FunctionName Set-DbaDbFileGroup
        }

        if ($__realCmdlet.ShouldProcess($fgToModify.Parent.Parent.Name, "Updating the filegroup options for $($fgToModify.Name) on the database $($fgToModify.Parent.Name) on $($fgToModify.Parent.Parent.Name)")) {
            try {
                if ($__boundDefault) {
                    $fgToModify.IsDefault = $true
                }

                if ($__boundReadOnly) {
                    $fgToModify.ReadOnly = $ReadOnly
                }

                if ($__boundAutoGrowAllFiles) {
                    $fgToModify.AutogrowAllFiles = $AutoGrowAllFiles
                }

                $fgToModify.Alter()
                $fgToModify
            } catch {
                Stop-Function -Message "Failure on $($fgToModify.Parent.Parent.Name) to set the filegroup options for $($fgToModify.Name) in the database $($fgToModify.Parent.Name)" -ErrorRecord $_ -Continue -FunctionName Set-DbaDbFileGroup
            }
        }
    }
} $SqlInstance $SqlCredential $Database $FileGroup $Default $ReadOnly $AutoGrowAllFiles $InputObject $EnableException $__boundSqlInstance $__boundDatabase $__boundFileGroup $__boundDefault $__boundReadOnly $__boundAutoGrowAllFiles $__realCmdlet $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
