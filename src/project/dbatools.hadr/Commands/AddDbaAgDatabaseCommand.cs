#nullable enable

using System.Collections;
using System.Management.Automation;
using System.Security;
using Dataplat.Dbatools.Parameter;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Adds databases to an availability group, orchestrating seeding mode, TDE certificate
/// validation, backup/restore staging and the join/synchronization waits.
/// Port of public/Add-DbaAgDatabase.ps1; surface pinned by
/// migration/baselines/Add-DbaAgDatabase.json.
/// </summary>
// The source declares NO default parameter set and NO output type: an ambiguous
// invocation must fail set resolution exactly like the function, and Get-Command
// metadata must not grow an OutputType the function never declared.
[Cmdlet(VerbsCommon.Add, "DbaAgDatabase", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Low)]
public sealed partial class AddDbaAgDatabaseCommand : DbaBaseCmdlet
{
    /// <summary>The primary SQL Server instance hosting the availability group.</summary>
    [Parameter(ParameterSetName = "NonPipeline", Mandatory = true, Position = 0)]
    public DbaInstanceParameter? SqlInstance { get; set; }

    /// <summary>Login to the primary instance using alternative credentials.</summary>
    [Parameter(ParameterSetName = "NonPipeline")]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The availability group the databases are added to.</summary>
    [Parameter(ParameterSetName = "NonPipeline", Mandatory = true)]
    [Parameter(ParameterSetName = "Pipeline", Mandatory = true, Position = 0)]
    [PsStringCast]
    public string? AvailabilityGroup { get; set; }

    /// <summary>The databases to add to the availability group.</summary>
    [Parameter(ParameterSetName = "NonPipeline", Mandatory = true)]
    public string[]? Database { get; set; }

    /// <summary>The secondary replica instance or instances.</summary>
    [Parameter(ParameterSetName = "NonPipeline")]
    [Parameter(ParameterSetName = "Pipeline")]
    public DbaInstanceParameter[]? Secondary { get; set; }

    /// <summary>Login to the secondary replicas using alternative credentials.</summary>
    [Parameter(ParameterSetName = "NonPipeline")]
    [Parameter(ParameterSetName = "Pipeline")]
    public PSCredential? SecondarySqlCredential { get; set; }

    /// <summary>Database objects piped in, for example from Get-DbaDatabase.</summary>
    [Parameter(ValueFromPipeline = true, ParameterSetName = "Pipeline", Mandatory = true)]
    public Microsoft.SqlServer.Management.Smo.Database[]? InputObject { get; set; }

    /// <summary>The seeding mode to apply to every replica before adding the databases.</summary>
    [Parameter(ParameterSetName = "NonPipeline")]
    [Parameter(ParameterSetName = "Pipeline")]
    [ValidateSet("Automatic", "Manual")]
    [PsStringCast]
    public string? SeedingMode { get; set; }

    /// <summary>Network path readable by every replica, used for backup/restore staging.</summary>
    [Parameter(ParameterSetName = "NonPipeline")]
    [Parameter(ParameterSetName = "Pipeline")]
    public string? SharedPath { get; set; }

    /// <summary>Uses the last existing backup chain instead of taking new backups.</summary>
    [Parameter(ParameterSetName = "NonPipeline")]
    [Parameter(ParameterSetName = "Pipeline")]
    public SwitchParameter UseLastBackup { get; set; }

    /// <summary>Additional parameters splatted through to Backup-DbaDatabase.</summary>
    [Parameter(ParameterSetName = "NonPipeline")]
    [Parameter(ParameterSetName = "Pipeline")]
    public Hashtable? AdvancedBackupParams { get; set; }

    /// <summary>Returns without waiting for synchronization to finish.</summary>
    [Parameter(ParameterSetName = "NonPipeline")]
    [Parameter(ParameterSetName = "Pipeline")]
    public SwitchParameter NoWait { get; set; }

    /// <summary>Restores to the replica's default paths instead of reusing the source folder structure.</summary>
    [Parameter(ParameterSetName = "NonPipeline")]
    [Parameter(ParameterSetName = "Pipeline")]
    public SwitchParameter SkipReuseSourceFolderStructure { get; set; }

    /// <summary>Password for the master key, used when copying a TDE certificate to replicas.</summary>
    [Parameter(ParameterSetName = "NonPipeline")]
    [Parameter(ParameterSetName = "Pipeline")]
    public SecureString? MasterKeySecurePassword { get; set; }

    /// <summary>The source declares EnableException a member of both named sets; the
    /// virtual base override reproduces that exact set surface.</summary>
    [Parameter(ParameterSetName = "NonPipeline")]
    [Parameter(ParameterSetName = "Pipeline")]
    public override SwitchParameter EnableException { get; set; }

    private Hashtable? _state;

    protected override void BeginProcessing()
    {
        if (Interrupted)
        {
            return;
        }

        foreach (PSObject? item in NestedCommand.InvokeScoped(this, BeginScript,
            SkipReuseSourceFolderStructure.ToBool(),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
        {
            Hashtable? sentinel = item?.BaseObject as Hashtable;
            if (sentinel is not null && sentinel.ContainsKey("__w4001State"))
            {
                _state = sentinel["__w4001State"] as Hashtable;
                continue;
            }
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                continue;
            }
            WriteObject(item);
        }
    }

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        // [DEF-001] closed via InvokeScopedStreaming (ab7492c). Streaming changes -WhatIf transcript
        // capture (documented observability change, not behaviour); the parity runner strips the
        // transcript gate-message. Fleet-confirmed non-blocker (C's streamed ShouldProcess wave, MSTest 487/487).
        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            Hashtable? sentinel = item?.BaseObject as Hashtable;
            if (sentinel is not null && sentinel.ContainsKey("__w4001State"))
            {
                _state = sentinel["__w4001State"] as Hashtable;
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
            SqlInstance, SqlCredential, AvailabilityGroup, Database, Secondary,
            SecondarySqlCredential, InputObject, SeedingMode, SharedPath,
            UseLastBackup.ToBool(), AdvancedBackupParams, NoWait.ToBool(),
            MasterKeySecurePassword, EnableException.ToBool(), _state, this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"),
            BoundRawParameter("ProgressAction"));
    }

    private object? BoundRawParameter(string name)
    {
        return MyInvocation.BoundParameters.TryGetValue(name, out object? value) ? value : null;
    }

    // PS: the begin block VERBATIM - four configuration snapshots the process hops read
    // through the sentinel (a mid-pipeline config change must not affect later records,
    // matching the function's single begin evaluation). The sentinel also seeds the
    // carried SkipReuseSourceFolderStructure value: the source mutates that PARAMETER
    // inside the restore loop (platform-mismatch auto-set) and function scope persists
    // the mutation across records, so the port carries it in state.
    private const string BeginScript = """
param($__skipReuse, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param($__skipReuse, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

        # We have three while loops, that need a timeout to not loop forever if somethings goes wrong:
        # while ($agDb.State -ne 'Existing')         - should only take milliseconds, so we set a default timeout of one minute
        # while ($replicaAgDb.State -ne 'Existing')  - should only take milliseconds, so we set a default timeout of one minute
        # while ($stillWaiting)                      - can take a long time with automatic seeding, but progress is displayed, so we set a default timeout of one day
        # We will use two timeout configuration values, as we don't want to add more timeout parameters to the command. We will store the timeouts in seconds.
        # The timeout for synchronization can be set to a lower value to end the command even when the synchronization is not finished yet.
        # The synchronization will continue even the command or the powershell session stops.
        # Even when the SQL Server instance is restarted, the synchronization will continue after the restart.
        # Set-DbatoolsConfig -FullName commands.add-dbaagdatabase.timeout.existing -Value 60
        # Set-DbatoolsConfig -FullName commands.add-dbaagdatabase.timeout.synchronization -Value 86400
        $timeoutExisting = Get-DbatoolsConfigValue -FullName commands.add-dbaagdatabase.timeout.existing -Fallback 60
        $timeoutSynchronization = Get-DbatoolsConfigValue -FullName commands.add-dbaagdatabase.timeout.synchronization -Fallback 86400

        # While in a while loop, configure the time in milliseconds to wait for the next test:
        # Set-DbatoolsConfig -FullName commands.add-dbaagdatabase.wait.while -Value 100
        $waitWhile = Get-DbatoolsConfigValue -FullName commands.add-dbaagdatabase.wait.while -Fallback 100

        # With automatic seeding we add the current seeding progress in verbose output and a progress bar. This can be disabled:
        # Set-DbatoolsConfig -FullName commands.add-dbaagdatabase.report.seeding -Value $true
        $reportSeeding = Get-DbatoolsConfigValue -FullName commands.add-dbaagdatabase.report.seeding -Fallback $true

    @{ __w4001State = @{
        timeoutExisting        = $timeoutExisting
        timeoutSynchronization = $timeoutSynchronization
        waitWhile              = $waitWhile
        reportSeeding          = $reportSeeding
        skipReuse              = $__skipReuse
    } }
} $__skipReuse $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
