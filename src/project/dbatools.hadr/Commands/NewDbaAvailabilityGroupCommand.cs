#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Configuration;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Creates an availability group: validates the prerequisites across primary and
/// secondaries, creates the group and its replicas, optionally adds databases
/// (seeding them from backups), configures the listener and joins the secondaries.
/// Port of public/New-DbaAvailabilityGroup.ps1; surface pinned by
/// migration/baselines/New-DbaAvailabilityGroup.json.
/// </summary>
[Cmdlet(VerbsCommon.New, "DbaAvailabilityGroup", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High)]
public sealed partial class NewDbaAvailabilityGroupCommand : DbaBaseCmdlet
{
    /// <summary>The primary SQL Server instance.</summary>
    [Parameter(ValueFromPipeline = true, Position = 0)]
    public DbaInstanceParameter? Primary { get; set; }

    /// <summary>Login to the primary instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? PrimarySqlCredential { get; set; }

    /// <summary>The secondary replica instances.</summary>
    [Parameter(Position = 2)]
    public DbaInstanceParameter[]? Secondary { get; set; }

    /// <summary>Login to the secondary instances using alternative credentials.</summary>
    [Parameter(Position = 3)]
    public PSCredential? SecondarySqlCredential { get; set; }

    /// <summary>The name of the availability group.</summary>
    [Parameter(Mandatory = true, Position = 4)]
    [PsStringCast]
    public string? Name { get; set; }

    /// <summary>The cluster type backing the availability group.</summary>
    [Parameter(Position = 5)]
    [ValidateSet("Wsfc", "External", "None")]
    [PsStringCast]
    public string ClusterType { get; set; } = ConfigValueOrFallback("AvailabilityGroups.Default.ClusterType", "Wsfc");

    /// <summary>Which replica backups are preferred to run on.</summary>
    [Parameter(Position = 6)]
    [ValidateSet("None", "Primary", "Secondary", "SecondaryOnly")]
    [PsStringCast]
    public string AutomatedBackupPreference { get; set; } = "Secondary";

    /// <summary>The failure condition level that triggers automatic failover.</summary>
    [Parameter(Position = 7)]
    [ValidateSet("OnAnyQualifiedFailureCondition", "OnCriticalServerErrors", "OnModerateServerErrors", "OnServerDown", "OnServerUnresponsive")]
    [PsStringCast]
    public string FailureConditionLevel { get; set; } = ConfigValueOrFallback("AvailabilityGroups.Default.FailureConditionLevel", "OnCriticalServerErrors");

    /// <summary>Health check timeout in milliseconds.</summary>
    [Parameter(Position = 8)]
    public int HealthCheckTimeout { get; set; } = 30000;

    /// <summary>The databases to add to the availability group.</summary>
    [Parameter(Position = 9)]
    [PsStringArrayCast]
    public string[]? Database { get; set; }

    /// <summary>Network share readable by every replica, used to stage seeding backups.</summary>
    [Parameter(Position = 10)]
    public string? SharedPath { get; set; }

    /// <summary>The replica availability mode.</summary>
    [Parameter(Position = 11)]
    [ValidateSet("AsynchronousCommit", "SynchronousCommit")]
    [PsStringCast]
    public string AvailabilityMode { get; set; } = "SynchronousCommit";

    /// <summary>The replica failover mode.</summary>
    [Parameter(Position = 12)]
    [ValidateSet("Automatic", "Manual", "External")]
    [PsStringCast]
    public string FailoverMode { get; set; } = "Automatic";

    /// <summary>The replica backup priority.</summary>
    [Parameter(Position = 13)]
    public int BackupPriority { get; set; } = 50;

    /// <summary>Connection access allowed while the replica is primary.</summary>
    [Parameter(Position = 14)]
    [ValidateSet("AllowAllConnections", "AllowReadWriteConnections")]
    [PsStringCast]
    public string ConnectionModeInPrimaryRole { get; set; } = "AllowAllConnections";

    /// <summary>Connection access allowed while the replica is secondary.</summary>
    [Parameter(Position = 15)]
    [ValidateSet("AllowNoConnections", "AllowReadIntentConnectionsOnly", "AllowAllConnections", "No", "Read-intent only", "Yes")]
    [PsStringCast]
    public string ConnectionModeInSecondaryRole { get; set; } = ConfigValueOrFallback("AvailabilityGroups.Default.ConnectionModeInSecondaryRole", "AllowNoConnections");

    /// <summary>How the secondary databases are seeded.</summary>
    [Parameter(Position = 16)]
    [ValidateSet("Automatic", "Manual")]
    [PsStringCast]
    public string SeedingMode { get; set; } = "Manual";

    /// <summary>The mirroring endpoint name.</summary>
    [Parameter(Position = 17)]
    public string? Endpoint { get; set; }

    /// <summary>Explicit endpoint URLs, one per replica (primary first).</summary>
    [Parameter(Position = 18)]
    [PsStringArrayCast]
    public string[]? EndpointUrl { get; set; }

    /// <summary>Certificate used to authenticate the mirroring endpoint.</summary>
    [Parameter(Position = 19)]
    public string? Certificate { get; set; }

    /// <summary>Static IP addresses for the listener.</summary>
    [Parameter(Position = 20)]
    public System.Net.IPAddress[]? IPAddress { get; set; }

    /// <summary>Subnet mask for the listener.</summary>
    [Parameter(Position = 21)]
    public System.Net.IPAddress SubnetMask { get; set; } = System.Net.IPAddress.Parse("255.255.255.0");

    /// <summary>Listener port.</summary>
    [Parameter(Position = 22)]
    public int Port { get; set; } = 1433;

    /// <summary>The cluster connection option.</summary>
    [Parameter(Position = 23)]
    public string? ClusterConnectionOption { get; set; }

    /// <summary>Password protecting the database master key.</summary>
    [Parameter(Position = 24)]
    public System.Security.SecureString? MasterKeySecurePassword { get; set; }

    /// <summary>Creates a contained availability group.</summary>
    [Parameter]
    public SwitchParameter IsContained { get; set; }

    /// <summary>Reuses existing contained system databases.</summary>
    [Parameter]
    public SwitchParameter ReuseSystemDatabases { get; set; }

    /// <summary>Enables DTC support.</summary>
    [Parameter]
    public SwitchParameter DtcSupport { get; set; }

    /// <summary>Creates a basic availability group.</summary>
    [Parameter]
    public SwitchParameter Basic { get; set; }

    /// <summary>Enables the database health trigger.</summary>
    [Parameter]
    public SwitchParameter DatabaseHealthTrigger { get; set; }

    /// <summary>Returns the unsaved availability group object instead of creating it.</summary>
    [Parameter]
    public SwitchParameter Passthru { get; set; }

    /// <summary>Seeds from the existing backup chain instead of taking new backups.</summary>
    [Parameter]
    public SwitchParameter UseLastBackup { get; set; }

    /// <summary>Drops an existing group of the same name and suppresses prompts.</summary>
    [Parameter]
    public SwitchParameter Force { get; set; }

    /// <summary>Configures the AlwaysOn extended events session.</summary>
    [Parameter]
    public SwitchParameter ConfigureXESession { get; set; }

    /// <summary>Uses DHCP for the listener instead of a static address.</summary>
    [Parameter]
    public SwitchParameter Dhcp { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    private Hashtable? _state;

    // The source evaluates three parameter defaults through Get-DbatoolsConfigValue at bind
    // time. The property initializers read the same configuration store the compiled config
    // commands already use, falling back to the source's literal fallback when the setting is
    // absent. NOTE: unlike the Add-DbaAgReplica helper this does NOT coerce stored
    // "Mandatory"/"Optional" values - that coercion reproduces a switch-parse guard which
    // belongs to that command's source and has no counterpart here.
    private static string ConfigValueOrFallback(string fullName, string fallback)
    {
        if (ConfigurationHost.Configurations.TryGetValue(fullName, out Config? config) && config?.Value is not null)
        {
            return LanguagePrimitives.ConvertTo<string>(config.Value);
        }
        return fallback;
    }

    protected override void BeginProcessing()
    {
        base.BeginProcessing();

        // C1 transplant condition: loud fail before any record if the engine field is gone.
        PromptStateTransplant.AssertResolvable("New-DbaAvailabilityGroup");
    }

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        // WHOLE-RECORD hop per the W3-005/W4-011 convention: the begin block's
        // Force -> ConfirmPreference suppression rides at the hop top and every ShouldProcess
        // gate runs on the INNER scriptblock's own $Pscmdlet (hop-scope-local, so -Force still
        // suppresses). The many loop-less validation Stop-Function+return sites exit the record
        // via the dot-block frame; the in-loop sites are -Continue.
        //
        // Cross-record state riding the __w4043State sentinel:
        //   1. ShouldProcess Yes/No-to-All - the W3-082 prompt-state transplant (Class-2
        //      signature: VFP Primary + per-record ProcessRecord + inner-$Pscmdlet gate +
        //      source gate at function scope in process{}).
        //   2. $EndpointUrl - the source shifts it destructively ($epUrl, $EndpointUrl =
        //      $EndpointUrl) once per replica, so the array SHORTENS; parameters are
        //      function-scope, so a later piped record sees the shortened array and then trips
        //      the element-count validation. Reproduced bug-for-bug, not fixed.
        // Analysed and deliberately NOT carried: $ConnectionModeInSecondaryRole is also
        // reassigned in process{}, but its switch carries a default returning the value
        // unchanged, so re-normalising an already-mapped value converges - a carry would be a
        // no-op. $Primary is the ValueFromPipeline parameter and is therefore RE-BOUND by the
        // binder every record, so its assignment does not cross records either.
        // Inventory tool: migration/tools/Get-ParamMutationInventory.ps1.
        // [DEF-001] closed via InvokeScopedStreaming (ab7492c). Streaming changes -WhatIf transcript
        // capture (documented observability change, not behaviour); the parity runner strips the
        // transcript gate-message. Fleet-confirmed non-blocker (C's streamed ShouldProcess wave, MSTest 487/487).
        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            Hashtable? sentinel = item?.BaseObject as Hashtable;
            if (sentinel is not null && sentinel.ContainsKey("__w4043State"))
            {
                _state = sentinel["__w4043State"] as Hashtable;
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
            Primary, PrimarySqlCredential, Secondary, SecondarySqlCredential, Name,
            ClusterType, AutomatedBackupPreference, FailureConditionLevel, HealthCheckTimeout,
            Database, SharedPath, AvailabilityMode, FailoverMode, BackupPriority,
            ConnectionModeInPrimaryRole, ConnectionModeInSecondaryRole, SeedingMode,
            Endpoint, EndpointUrl, Certificate, IPAddress, SubnetMask, Port,
            ClusterConnectionOption, MasterKeySecurePassword,
            IsContained.ToBool(), ReuseSystemDatabases.ToBool(), DtcSupport.ToBool(),
            Basic.ToBool(), DatabaseHealthTrigger.ToBool(), Passthru.ToBool(),
            UseLastBackup.ToBool(), Force.ToBool(), ConfigureXESession.ToBool(),
            Dhcp.ToBool(), EnableException.ToBool(),
            TestBound(nameof(UseLastBackup)), _state,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    private const string ProcessScript = ProcessScriptHead + "\r\n" + ProcessScriptTail;
}