#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Finds SharePoint content databases by reading the SharePoint configuration database. Port of
/// public/Get-DbaDbSharePoint.ps1; the workflow remains a module-scoped PowerShell compatibility hop.
///
/// A process-only port; InputObject is the only ValueFromPipeline parameter (SqlInstance is NOT VFP). The
/// -SqlInstance path gathers the config database(s) via Get-DbaDatabase and appends to $InputObject within the
/// record. ConfigDatabase carries the source default "SharePoint_Config" via a C# property initializer (the hop
/// passes params positionally, so an inner-param default would be overridden by the explicit positional value -
/// the default must live on the compiled property; surface baseline records no defaultValue, so this is
/// COMPATIBLE). No accumulator, no interrupt, no Test-Bound, no ShouldProcess. The single Stop-Function (no
/// -Continue, in the per-db catch, with no following return - verbatim) gets -FunctionName Get-DbaDbSharePoint.
/// Surface pinned by migration/baselines/Get-DbaDbSharePoint.json (positions 0-3, InputObject VFP pos3, no ShouldProcess).
/// </summary>
[Cmdlet(VerbsCommon.Get, "DbaDbSharePoint")]
public sealed class GetDbaDbSharePointCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances hosting the SharePoint config database.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The name of the SharePoint configuration database(s). Defaults to SharePoint_Config.</summary>
    [Parameter(Position = 2)]
    public string[]? ConfigDatabase { get; set; } = new[] { "SharePoint_Config" };

    /// <summary>Config database object(s) piped in from Get-DbaDatabase.</summary>
    [Parameter(ValueFromPipeline = true, Position = 3)]
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
            SqlInstance, SqlCredential, ConfigDatabase, InputObject, EnableException.ToBool(),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }
    // PS: the process block VERBATIM. Edit: -FunctionName Get-DbaDbSharePoint on the one Stop-Function (per-db
    // catch, no -Continue, no following return - preserved). $ConfigDatabase arrives with its SharePoint_Config
    // default already applied by the compiled property.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $ConfigDatabase, $InputObject, $EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [string[]]$ConfigDatabase, [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject, $EnableException, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

        foreach ($instance in $SqlInstance) {
            $InputObject += Get-DbaDatabase -SqlInstance $instance -SqlCredential $SqlCredential -Database $ConfigDatabase
        }

        foreach ($db in $InputObject) {
            try {
                $guid = $db.Query("SELECT Id FROM Classes WHERE FullName LIKE 'Microsoft.SharePoint.Administration.SPDatabase,%'").Id.Guid
                $dbid = $db.Query("[dbo].[proc_getObjectsByBaseClass] @BaseClassId = '$guid', @ParentId = NULL").Id.Guid -join "', '"
                $dbName = $db.Query("SELECT [Name] FROM [dbo].[Objects] WHERE Id IN ('$dbid')").Name
                Get-DbaDatabase -SqlInstance $db.Parent -Database $dbName
            } catch {
                Stop-Function -Message "Failure" -ErrorRecord $_ -FunctionName Get-DbaDbSharePoint
            }
        }
} $SqlInstance $SqlCredential $ConfigDatabase $InputObject $EnableException $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
