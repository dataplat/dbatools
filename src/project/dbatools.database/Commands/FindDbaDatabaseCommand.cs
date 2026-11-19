#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Finds databases across one or more instances by matching a property (Name, ServiceBrokerGuid, or
/// Owner) against a regex pattern. Port of public/Find-DbaDatabase.ps1; the workflow remains a
/// module-scoped PowerShell compatibility hop.
///
/// SqlInstance is ValueFromPipeline so the source is a single process-only block that fires per record;
/// the port is one process hop, no begin/end. There is no ShouldProcess, no early return, and the one
/// Stop-Function (connection failure) is -Continue, so no interrupt carry is needed.
///
/// One subtlety drives the design: the non-Exact branch wraps `-match $pattern` in try/catch, and the
/// catch strips wildcard characters (* and %) from $Pattern before retrying (for users who typed LIKE
/// wildcards). In the source's shared function scope that mutation PERSISTS across piped records; a
/// naive per-record hop would re-initialize $Pattern from the C# property each record and lose it. The
/// catch is BROAD (it can also fire on transient database enumeration / property-access failures, not
/// only on an invalid-regex pattern), so a valid `*`/`%` pattern could be stripped on one record;
/// restoring the original pattern on a later record could then change matches. The possibly-mutated
/// $Pattern is therefore carried record-to-record via a sentinel Hashtable (the process hop re-emits it,
/// C# stores it in _pattern, the next record restores it) to reproduce the shared-scope behavior
/// exactly. The only body edit is -FunctionName Find-DbaDatabase on the direct Stop-Function.
/// Surface pinned by migration/baselines/Find-DbaDatabase.json (positions 0-3, Property ValidateSet,
/// no ShouldProcess).
/// </summary>
[Cmdlet(VerbsCommon.Find, "DbaDatabase")]
public sealed class FindDbaDatabaseCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The database property to match against.</summary>
    [Parameter(Position = 2)]
    [ValidateSet("Name", "ServiceBrokerGuid", "Owner")]
    [PsStringCast]
    public string Property { get; set; } = "Name";

    /// <summary>The regular-expression pattern to match.</summary>
    [Parameter(Mandatory = true, Position = 3)]
    [PsStringCast]
    public string Pattern { get; set; } = null!;

    /// <summary>Match the property value exactly instead of by regex.</summary>
    [Parameter]
    public SwitchParameter Exact { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // The process body's catch may strip wildcards from $Pattern; in the source's shared scope that
    // persists across piped records, so the (possibly-mutated) pattern is carried record-to-record.
    private string? _pattern;

    protected override void ProcessRecord()
    {
        if (Interrupted)
            return;

        string patternForRecord = _pattern ?? Pattern;

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is Hashtable sentinel && sentinel.ContainsKey("__findDbaDatabaseState"))
            {
                if (sentinel["__findDbaDatabaseState"] is Hashtable state)
                {
                    _pattern = state["Pattern"] as string;
                }
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
            SqlInstance, SqlCredential, Property, patternForRecord, Exact.ToBool(), EnableException.ToBool(),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the process block VERBATIM. Edit: -FunctionName Find-DbaDatabase on the direct Stop-Function.
    // The block re-emits a sentinel with the (possibly-mutated) $Pattern so it carries to the next record.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Property, $Pattern, $Exact, $EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [string]$Property, [string]$Pattern, $Exact, $EnableException, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -FunctionName Find-DbaDatabase -Continue
            }

            if ($exact -eq $true) {
                $dbs = $server.Databases | Where-Object IsAccessible | Where-Object { $_.$property -eq $pattern }
            } else {
                try {
                    $dbs = $server.Databases | Where-Object IsAccessible | Where-Object { $_.$property.ToString() -match $pattern }
                } catch {
                    # they probably put asterisks thinking it's a like
                    $Pattern = $Pattern -replace '\*', ''
                    $Pattern = $Pattern -replace '\%', ''
                    $dbs = $server.Databases | Where-Object IsAccessible | Where-Object { $_.$property.ToString() -match $pattern }
                }
            }

            foreach ($db in $dbs) {

                $extendedproperties = @()
                foreach ($xp in $db.ExtendedProperties) {
                    $extendedproperties += [PSCustomObject]@{
                        Name  = $db.ExtendedProperties[$xp.Name].Name
                        Value = $db.ExtendedProperties[$xp.Name].Value
                    }
                }

                if ($extendedproperties.count -eq 0) { $extendedproperties = 0 }

                $res = $db.Query("
                SELECT 'proc' AS t, COUNT(*) AS numFound FROM sys.procedures WHERE is_ms_shipped = 0
                UNION ALL
                SELECT 'tables' AS t, COUNT(*) AS numFound FROM sys.tables WHERE is_ms_shipped = 0
                UNION ALL
                SELECT 'views' AS t, COUNT(*) AS numFound FROM sys.views WHERE is_ms_shipped = 0")

                [PSCustomObject]@{
                    ComputerName       = $server.ComputerName
                    InstanceName       = $server.ServiceName
                    SqlInstance        = $server.Name
                    Name               = $db.Name
                    Id                 = $db.Id
                    Size               = [dbasize]($db.Size * 1024 * 1024)
                    Owner              = $db.Owner
                    CreateDate         = $db.CreateDate
                    ServiceBrokerGuid  = $db.ServiceBrokerGuid
                    Tables             = ($res | Where-Object t -eq 'tables').numFound
                    StoredProcedures   = ($res | Where-Object t -eq 'proc').numFound
                    Views              = ($res | Where-Object t -eq 'views').numFound
                    ExtendedProperties = $extendedproperties
                }
            }
        }

    @{ __findDbaDatabaseState = @{ Pattern = $Pattern } }
} $SqlInstance $SqlCredential $Property $Pattern $Exact $EnableException $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
