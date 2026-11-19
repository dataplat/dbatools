#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Compares each database collation against its server collation. Port of
/// public/Test-DbaDbCollation.ps1; the workflow remains a module-scoped PowerShell compatibility hop.
///
/// A process-only port with the same instance-loop shape as the Test-DbaDbCompatibility sibling.
/// -SqlInstance is Mandatory and ValueFromPipeline, so process fires per piped instance and the
/// body's own foreach walks the array form; there is no -InputObject, no accumulator, no begin/end.
/// No flag substitution is carried: the body contains no Test-Bound (the -Database and
/// -ExcludeDatabase branches test the VARIABLES, which survive the hop as carried values). No
/// continue-guard wrapper is needed either: the only -Continue is on Stop-Function inside the body's
/// own foreach over $SqlInstance, which has a real enclosing loop to continue.
///
/// Source quirk preserved verbatim: the per-database Write-Message interpolates $servername, a
/// variable this command never assigns (the connected server is $server and the loop variable is
/// $db), so the message renders with a trailing "on ." exactly as the function does today. Parity
/// means shipping that, not repairing it.
///
/// The only body edit is the attribution stamp -FunctionName Test-DbaDbCollation on the two sites
/// called directly from the body (the connection Stop-Function and the per-database Write-Message).
///
/// Surface pinned by migration/baselines/Test-DbaDbCollation.json: SqlInstance Mandatory
/// ValueFromPipeline at position 0, SqlCredential 1, Database 2, ExcludeDatabase 3 (both Object[],
/// not string[]), no parameter sets, no ShouldProcess, and outputType is EMPTY - unlike the
/// Test-DbaDbCompatibility sibling this source declares no [OutputType], so none is declared here.
/// </summary>
[Cmdlet(VerbsDiagnostic.Test, "DbaDbCollation")]
public sealed class TestDbaDbCollationCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The database(s) to process.</summary>
    [Parameter(Position = 2)]
    public object[]? Database { get; set; }

    /// <summary>The database(s) to exclude.</summary>
    [Parameter(Position = 3)]
    public object[]? ExcludeDatabase { get; set; }

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
            SqlInstance, SqlCredential, Database, ExcludeDatabase, EnableException.ToBool(),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the process block verbatim. Only edit: -FunctionName Test-DbaDbCollation on the
    // Stop-Function and the per-database Write-Message. The undefined $servername in that message is
    // the source's own quirk and is left untouched.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Database, $ExcludeDatabase, $EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [object[]]$Database, [object[]]$ExcludeDatabase, $EnableException, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    foreach ($instance in $SqlInstance) {
        try {
            $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Test-DbaDbCollation
        }

        $dbs = $server.Databases | Where-Object IsAccessible

        if ($Database) {
            $dbs = $dbs | Where-Object { $Database -contains $_.Name }
        }

        if ($ExcludeDatabase) {
            $dbs = $dbs | Where-Object Name -NotIn $ExcludeDatabase
        }

        foreach ($db in $dbs) {
            Write-Message -Level Verbose -Message "Processing $($db.name) on $servername." -FunctionName Test-DbaDbCollation -ModuleName "dbatools"
            [PSCustomObject]@{
                ComputerName      = $server.ComputerName
                InstanceName      = $server.ServiceName
                SqlInstance       = $server.DomainInstanceName
                Database          = $db.name
                ServerCollation   = $server.collation
                DatabaseCollation = $db.collation
                IsEqual           = $db.collation -eq $server.collation
            }
        }
    }
} $SqlInstance $SqlCredential $Database $ExcludeDatabase $EnableException $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
