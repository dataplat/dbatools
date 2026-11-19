#nullable enable

using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Configuration;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Adds a replica to an availability group, creating and starting the mirroring endpoint
/// when needed, applying the replica property matrix and granting cluster and endpoint
/// permissions. Port of public/Add-DbaAgReplica.ps1; surface pinned by
/// migration/baselines/Add-DbaAgReplica.json.
/// </summary>
[Cmdlet(VerbsCommon.Add, "DbaAgReplica", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Low)]
public sealed partial class AddDbaAgReplicaCommand : DbaBaseCmdlet
{
    /// <summary>The SQL Server instances to add as replicas.</summary>
    [Parameter(Mandatory = true, Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instances using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The replica name; defaults to the instance name.</summary>
    [Parameter(Position = 2)]
    public string? Name { get; set; }

    /// <summary>The cluster type backing the availability group.</summary>
    [Parameter(Position = 3)]
    [ValidateSet("Wsfc", "External", "None")]
    [PsStringCast]
    public string ClusterType { get; set; } = ConfigValueOrFallback("AvailabilityGroups.Default.ClusterType", "Wsfc");

    /// <summary>The availability mode of the replica.</summary>
    [Parameter(Position = 4)]
    [ValidateSet("AsynchronousCommit", "SynchronousCommit")]
    [PsStringCast]
    public string AvailabilityMode { get; set; } = "SynchronousCommit";

    /// <summary>The failover mode of the replica.</summary>
    [Parameter(Position = 5)]
    [ValidateSet("Automatic", "Manual", "External")]
    [PsStringCast]
    public string FailoverMode { get; set; } = "Automatic";

    /// <summary>The backup priority of the replica.</summary>
    [Parameter(Position = 6)]
    public int BackupPriority { get; set; } = 50;

    /// <summary>Connection mode when the replica is primary.</summary>
    [Parameter(Position = 7)]
    [ValidateSet("AllowAllConnections", "AllowReadWriteConnections")]
    [PsStringCast]
    public string ConnectionModeInPrimaryRole { get; set; } = "AllowAllConnections";

    /// <summary>Connection mode when the replica is secondary; friendly aliases are normalized in the body.</summary>
    [Parameter(Position = 8)]
    [ValidateSet("AllowNoConnections", "AllowReadIntentConnectionsOnly", "AllowAllConnections", "No", "Read-intent only", "Yes")]
    [PsStringCast]
    public string ConnectionModeInSecondaryRole { get; set; } = ConfigValueOrFallback("AvailabilityGroups.Default.ConnectionModeInSecondaryRole", "AllowNoConnections");

    /// <summary>The seeding mode of the replica.</summary>
    [Parameter(Position = 9)]
    [ValidateSet("Automatic", "Manual")]
    [PsStringCast]
    public string? SeedingMode { get; set; }

    /// <summary>The mirroring endpoint name to use or create.</summary>
    [Parameter(Position = 10)]
    public string? Endpoint { get; set; }

    /// <summary>Explicit endpoint URLs, one per instance.</summary>
    [Parameter(Position = 11)]
    public string[]? EndpointUrl { get; set; }

    /// <summary>Returns the uncreated replica object for further customization.</summary>
    [Parameter]
    public SwitchParameter Passthru { get; set; }

    /// <summary>The read-only routing list for the replica.</summary>
    [Parameter(Position = 12)]
    public string[]? ReadOnlyRoutingList { get; set; }

    /// <summary>The read-only routing connection URL for the replica.</summary>
    [Parameter(Position = 13)]
    public string? ReadonlyRoutingConnectionUrl { get; set; }

    /// <summary>Certificate securing the mirroring endpoint.</summary>
    [Parameter(Position = 14)]
    public string? Certificate { get; set; }

    /// <summary>Ensures the AlwaysOn_health extended events session is configured and running.</summary>
    [Parameter]
    public SwitchParameter ConfigureXESession { get; set; }

    /// <summary>The replica session timeout in seconds.</summary>
    [Parameter(Position = 15)]
    public int SessionTimeout { get; set; }

    /// <summary>The availability group object the replica is added to.</summary>
    [Parameter(Position = 16, ValueFromPipeline = true, Mandatory = true)]
    public Microsoft.SqlServer.Management.Smo.AvailabilityGroup? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    private Hashtable? _state;

    // The source evaluates two parameter defaults through Get-DbatoolsConfigValue at bind
    // time; the property initializers read the same configuration store the compiled
    // config commands already use, with the source's fallbacks and its existing-value
    // coercions: a stored "Mandatory" becomes $true and "Optional" becomes $false before
    // the [string] parameter constraint stringifies them (True/False), exactly like the
    // function's switch-parse guard.
    private static string ConfigValueOrFallback(string fullName, string fallback)
    {
        if (ConfigurationHost.Configurations.TryGetValue(fullName, out Config? config) && config?.Value is not null)
        {
            string text = LanguagePrimitives.ConvertTo<string>(config.Value);
            if (string.Equals(text, "Mandatory", System.StringComparison.OrdinalIgnoreCase))
            {
                return LanguagePrimitives.ConvertTo<string>(true);
            }
            if (string.Equals(text, "Optional", System.StringComparison.OrdinalIgnoreCase))
            {
                return LanguagePrimitives.ConvertTo<string>(false);
            }
            return text;
        }
        return fallback;
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
            if (sentinel is not null && sentinel.ContainsKey("__w4003State"))
            {
                _state = sentinel["__w4003State"] as Hashtable;
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
            SqlInstance, SqlCredential, Name, ClusterType, AvailabilityMode, FailoverMode,
            BackupPriority, ConnectionModeInPrimaryRole, ConnectionModeInSecondaryRole,
            SeedingMode, Endpoint, EndpointUrl, Passthru.ToBool(), ReadOnlyRoutingList,
            ReadonlyRoutingConnectionUrl, Certificate, ConfigureXESession.ToBool(),
            SessionTimeout, InputObject, EnableException.ToBool(), _state, this,
            BoundFlag("Name"),
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    private bool BoundFlag(string name)
    {
        return MyInvocation.BoundParameters.ContainsKey(name);
    }
}
