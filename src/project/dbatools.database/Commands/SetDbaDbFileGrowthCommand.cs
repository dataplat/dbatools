#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Sets the file growth setting on database data and log files. Port of
/// public/Set-DbaDbFileGrowth.ps1; the workflow remains a module-scoped PowerShell compatibility hop.
///
/// A process-only port (InputObject is ValueFromPipeline, so process fires per record; the
/// -SqlInstance path gathers databases via Get-DbaDatabase). Three things this port has to get right,
/// none of which the simpler Test-Dba* rows in this satellite needed:
///
/// (1) THREE Test-Bound reads ride inside the body and Test-Bound scope-walks the caller, so it cannot
/// survive the hop. Each is flag-substituted from a carried value computed in C#:
///     Test-Bound -Not Database, InputObject  ->  (-not $__boundDatabase) -and (-not $__boundInputObject)
///     Test-Bound Database                    ->  $__boundDatabase
///     Test-Bound SqlInstance                 ->  $__boundSqlInstance
/// The -Not form is true only when NEITHER is bound, which the two-flag conjunction reproduces exactly.
///
/// (2) ShouldProcess is real here (the baseline records supportsShouldProcess true, confirmImpact
/// Medium), so the gate must be the REAL cmdlet: $PSCmdlet.ShouldProcess(...) becomes
/// $__realCmdlet.ShouldProcess(...) with the target and action strings copied byte-for-byte, so
/// -WhatIf and -Confirm behave identically and the WhatIf output the source deliberately preserves
/// (see its own comment about keeping results in the WhatIf) still appears.
///
/// (3) Both opening guards use `return`, not `continue`, so no foreach continue-guard wrapper is
/// needed: a return inside the hop scriptblock ends the body for that pipeline record, which is what
/// the source's process-block return does.
///
/// Only other body edit is -FunctionName Set-DbaDbFileGrowth on the direct Write-Message and
/// Stop-Function sites. The source's own comments (the SMO-weird-errors note and the
/// Get-DbaDbFileGrowth-in-a-loop note) are carried verbatim, as is the T-SQL string.
///
/// Surface pinned by migration/baselines/Set-DbaDbFileGrowth.json: SqlInstance 0, SqlCredential 1,
/// Database 2 (String[]), GrowthType 3, Growth 4, FileType 5, InputObject 6 ValueFromPipeline;
/// defaults GrowthType MB, Growth 64, FileType All; no parameter sets; outputType empty.
/// </summary>
[Cmdlet(VerbsCommon.Set, "DbaDbFileGrowth", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
public sealed class SetDbaDbFileGrowthCommand : DbaBaseCmdlet
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

    /// <summary>The unit the growth value is expressed in.</summary>
    [Parameter(Position = 3)]
    [PsStringCast]
    [ValidateSet("KB", "MB", "GB", "TB")]
    public string GrowthType { get; set; } = "MB";

    /// <summary>The growth value to apply.</summary>
    [Parameter(Position = 4)]
    public int Growth { get; set; } = 64;

    /// <summary>Which files to modify.</summary>
    [Parameter(Position = 5)]
    [PsStringCast]
    [ValidateSet("All", "Data", "Log")]
    public string FileType { get; set; } = "All";

    /// <summary>Database object(s) piped in.</summary>
    [Parameter(ValueFromPipeline = true, Position = 6)]
    public Microsoft.SqlServer.Management.Smo.Database[]? InputObject { get; set; }

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
            SqlInstance, SqlCredential, Database, GrowthType, Growth, FileType, InputObject,
            EnableException.ToBool(),
            TestBound(nameof(Database)), TestBound(nameof(InputObject)), TestBound(nameof(SqlInstance)),
            this, NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the process block verbatim. Edits: the three Test-Bound reads -> carried bound flags,
    // $PSCmdlet -> $__realCmdlet so the gate is the real cmdlet, and -FunctionName Set-DbaDbFileGrowth
    // on the direct Write-Message and Stop-Function sites.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Database, $GrowthType, $Growth, $FileType, $InputObject, $EnableException, $__boundDatabase, $__boundInputObject, $__boundSqlInstance, $__realCmdlet, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [string[]]$Database, [string]$GrowthType, [int]$Growth, [string]$FileType, [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject, $EnableException, $__boundDatabase, $__boundInputObject, $__boundSqlInstance, $__realCmdlet, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    if ((-not $__boundDatabase) -and (-not $__boundInputObject)) {
        Stop-Function -Message "You must specify InputObject or Database" -FunctionName Set-DbaDbFileGrowth
        return
    }

    if ($__boundDatabase -and -not $__boundSqlInstance) {
        Stop-Function -Message "You must specify SqlInstance when specifying Database" -FunctionName Set-DbaDbFileGrowth
        return
    }

    if ($SqlInstance) {
        $InputObject = Get-DbaDatabase -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database | Where-Object IsAccessible
    }

    foreach ($db in $InputObject) {

        $allfiles = @()
        if ($FileType -in ('Log', 'All')) {
            $allfiles += $db.LogFiles
        }
        if ($FileType -in ('Data', 'All')) {
            $allfiles += $db.FileGroups.Files
        }

        foreach ($file in $allfiles) {
            if ($__realCmdlet.ShouldProcess($db.Parent.Name, "Setting filegrowth for $($file.Name) in $($db.name) to $($Growth)$($GrowthType)")) {
                # SMO gave me some weird errors so I'm just gonna go with T-SQL
                try {
                    $sql = "ALTER DATABASE $db MODIFY FILE ( NAME = N'$($file.Name)', FILEGROWTH = $($Growth)$($GrowthType) )"
                    Write-Message -Level Verbose -Message $sql -FunctionName Set-DbaDbFileGrowth -ModuleName "dbatools"
                    $db.Query($sql)
                    $db.Refresh()
                    $db.Parent.Refresh()
                    # this executes Get-DbaDbFileGrowth a bunch of times because it's in a loop, but it's needed to keep the output results in the WhatIf
                    $db | Get-DbaDbFileGrowth | Where-Object File -eq $file.Name
                } catch {
                    Stop-Function -Message "Could not modify $db on $($db.Parent.Name)" -ErrorRecord $_ -Continue -FunctionName Set-DbaDbFileGrowth
                }
            }
        }
    }
} $SqlInstance $SqlCredential $Database $GrowthType $Growth $FileType $InputObject $EnableException $__boundDatabase $__boundInputObject $__boundSqlInstance $__realCmdlet $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
