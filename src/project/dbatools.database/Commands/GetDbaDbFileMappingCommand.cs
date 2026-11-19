#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Returns a map of logical file name to physical file path for each database. Port of
/// public/Get-DbaDbFileMapping.ps1; the workflow remains a module-scoped PowerShell compatibility hop.
///
/// A process-only port (both SqlInstance and InputObject are ValueFromPipeline; the -SqlInstance path gathers
/// databases via Get-DbaDatabase). No begin/end, no accumulator, no interrupt. The neither-bound guard runs
/// Write-Message then exits via a bare return (not continue), which leaves the hop scriptblock cleanly, so no
/// continue-guard wrapper is needed. Two Test-Bound reads become carried boundness flags: the compound
/// Test-Bound -not 'SqlInstance','InputObject' becomes (-not $__boundSqlInstance) -and (-not $__boundInputObject),
/// and Test-Bound -Not -ParameterName InputObject becomes -not $__boundInputObject (each keeping the if's own
/// parentheses; flags from C# TestBound(nameof(...))). Body edits also add -FunctionName Get-DbaDbFileMapping to
/// the three Write-Message. Surface pinned by migration/baselines/Get-DbaDbFileMapping.json (positions 0-3, both
/// SqlInstance/InputObject VFP, no ShouldProcess).
/// </summary>
[Cmdlet(VerbsCommon.Get, "DbaDbFileMapping")]
public sealed class GetDbaDbFileMappingCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(ValueFromPipeline = true, Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The database(s) to process.</summary>
    [Parameter(Position = 2)]
    [PsStringArrayCast]
    public string[]? Database { get; set; }

    /// <summary>Database object(s) piped in.</summary>
    [Parameter(ValueFromPipeline = true, Position = 3)]
    public Microsoft.SqlServer.Management.Smo.Database[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    protected override void ProcessRecord()
    {
        if (Interrupted)
            return;

        foreach (PSObject? item in NestedCommand.InvokeScoped(this, ProcessScript,
            SqlInstance, SqlCredential, Database, InputObject, EnableException.ToBool(),
            TestBound(nameof(SqlInstance)), TestBound(nameof(InputObject)),
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
    // PS: the process block VERBATIM. Edits: the two Test-Bound reads -> carried boundness flags (each
    // keeping the if parentheses), and -FunctionName Get-DbaDbFileMapping on the three Write-Message. The
    // neither-bound guard exits via a bare return that leaves the hop scriptblock cleanly (not dot-sourced).
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Database, $InputObject, $EnableException, $__boundSqlInstance, $__boundInputObject, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [string[]]$Database, [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject, $EnableException, $__boundSqlInstance, $__boundInputObject, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

        if ((-not $__boundSqlInstance) -and (-not $__boundInputObject)) {
            Write-Message -Level Warning -Message "You must specify either a SQL instance or supply an InputObject" -FunctionName Get-DbaDbFileMapping -ModuleName "dbatools"
            return
        }

        if (-not $__boundInputObject) {
            $InputObject += Get-DbaDatabase -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database
        }

        foreach ($db in $InputObject) {
            if ($db.IsAccessible) {
                Write-Message -Level Verbose -Message "Processing database: $db" -FunctionName Get-DbaDbFileMapping -ModuleName "dbatools"
                $fileMap = @{ }

                foreach ($file in $db.FileGroups.Files) {
                    $fileMap[$file.Name] = $file.FileName
                }
                foreach ($file in $db.LogFiles) {
                    $fileMap[$file.Name] = $file.FileName
                }

                [PSCustomObject]@{
                    ComputerName = $db.ComputerName
                    InstanceName = $db.InstanceName
                    SqlInstance  = $db.SqlInstance
                    Database     = $db.Name
                    FileMapping  = $fileMap
                }
            } else {
                Write-Message -Level Verbose -Message "Skipping processing of database: $db as database is not accessible" -FunctionName Get-DbaDbFileMapping -ModuleName "dbatools"
            }
        }
} $SqlInstance $SqlCredential $Database $InputObject $EnableException $__boundSqlInstance $__boundInputObject $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
