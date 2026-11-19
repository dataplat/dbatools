#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Compares each database owner against a target login and returns the databases that do not match.
/// Port of public/Test-DbaDbOwner.ps1; the workflow remains a module-scoped PowerShell compatibility hop.
///
/// A process-only port (InputObject is ValueFromPipeline, so process fires per record; the -SqlInstance
/// path gathers databases via Get-DbaDatabase). No begin/end, no accumulator, no interrupt handling of its
/// own. Points worth knowing:
///
/// (1) The source's opening guard tests the VARIABLES (`if (-not $InputObject -and -not $Sqlinstance)`),
/// not Test-Bound, so no carried bound-flags are needed for it. It calls Stop-Function WITHOUT -Continue
/// and WITHOUT a following return, so execution falls through: with neither input supplied nothing
/// resolves and the foreach emits nothing. That fall-through is preserved exactly - no return, and no
/// foreach continue-guard wrapper, because the body contains no bare continue.
///
/// (2) `Test-Bound -ParameterName TargetLogin -Not` DOES ride inside the loop, and Test-Bound scope-walks
/// the caller, so it cannot survive the hop. It is flag-substituted with the carried $__boundTargetLogin
/// (C# TestBound(nameof(TargetLogin))). The flag is constant for the call, which reproduces the source
/// behavior that $TargetLogin is re-derived on EVERY iteration when the caller did not supply it - so with
/// multiple databases the target is taken from each database's own server, not just the first.
///
/// (3) Source quirk preserved verbatim: the "is not a login on $instance" Write-Message and its
/// -Target $instance reference a variable that is never assigned in this command (the loop variable is
/// $db), so $instance is $null and the message renders with a trailing "on ". Parity means shipping that
/// as-is, not repairing it.
///
/// Body edits are only the two allowed ones: the Test-Bound flag substitution above and
/// -FunctionName Test-DbaDbOwner on the Stop-Function and the two Write-Message sites, all of which are
/// called DIRECTLY from the body (no nested named helper is involved, so the attribution rule stamps them).
/// Surface pinned by migration/baselines/Test-DbaDbOwner.json: SqlInstance is the only positional
/// parameter (0), Database/ExcludeDatabase are Object[], no parameter sets, no ShouldProcess.
/// </summary>
[Cmdlet(VerbsDiagnostic.Test, "DbaDbOwner")]
public sealed class TestDbaDbOwnerCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The database(s) to process.</summary>
    [Parameter]
    public object[]? Database { get; set; }

    /// <summary>The database(s) to exclude.</summary>
    [Parameter]
    public object[]? ExcludeDatabase { get; set; }

    /// <summary>The login that the databases should be owned by.</summary>
    [Parameter]
    public string? TargetLogin { get; set; }

    /// <summary>Database object(s) piped in.</summary>
    [Parameter(ValueFromPipeline = true)]
    public Microsoft.SqlServer.Management.Smo.Database[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    protected override void ProcessRecord()
    {

        foreach (PSObject? item in NestedCommand.InvokeScoped(this, ProcessScript,
            SqlInstance, SqlCredential, Database, ExcludeDatabase, TargetLogin, InputObject,
            EnableException.ToBool(), TestBound(nameof(TargetLogin)),
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

    // PS: the process block verbatim. Edits: Test-Bound -ParameterName TargetLogin -Not -> the carried
    // $__boundTargetLogin flag, and -FunctionName Test-DbaDbOwner on the Stop-Function and the two
    // Write-Message. The undefined $instance in the login-validation message is the source's own quirk and
    // is left untouched.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Database, $ExcludeDatabase, $TargetLogin, $InputObject, $EnableException, $__boundTargetLogin, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [object[]]$Database, [object[]]$ExcludeDatabase, [string]$TargetLogin, [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject, $EnableException, $__boundTargetLogin, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    if (-not $InputObject -and -not $Sqlinstance) {
        Stop-Function -Message 'You must specify a $SqlInstance parameter' -FunctionName Test-DbaDbOwner
    }

    if ($SqlInstance) {
        $InputObject += Get-DbaDatabase -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database -ExcludeDatabase $ExcludeDatabase
    }

    #for each database, create custom object for return set.
    foreach ($db in $InputObject) {
        $server = $db.Parent

        # dynamic sa name for orgs who have changed their sa name
        if (-not $__boundTargetLogin) {
            $TargetLogin = ($server.logins | Where-Object {
                    $_.id -eq 1
                }).Name
        }

        #Validate login
        if (($server.Logins.Name) -notmatch [Regex]::Escape($TargetLogin)) {
            Write-Message -Level Verbose -Message "$TargetLogin is not a login on $instance" -Target $instance -FunctionName Test-DbaDbOwner -ModuleName "dbatools"
        }

        Write-Message -Level Verbose -Message "Checking $db" -FunctionName Test-DbaDbOwner -ModuleName "dbatools"
        [PSCustomObject]@{
            ComputerName = $server.ComputerName
            InstanceName = $server.ServiceName
            SqlInstance  = $server.DomainInstanceName
            Server       = $server.DomainInstanceName
            Database     = $db.Name
            DBState      = $db.Status
            CurrentOwner = $db.Owner
            TargetOwner  = $TargetLogin
            OwnerMatch   = ($db.owner -eq $TargetLogin)
        } | Select-DefaultView -ExcludeProperty Server
    }
} $SqlInstance $SqlCredential $Database $ExcludeDatabase $TargetLogin $InputObject $EnableException $__boundTargetLogin $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
