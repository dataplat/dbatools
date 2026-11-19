#nullable enable

using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Compares server-level objects (logins, agent jobs, credentials, linked servers, agent
/// operators, agent alerts, agent proxies, custom errors) across the replicas of
/// availability groups, reporting objects missing from replicas and login property or
/// server-role differences. Port of public/Compare-DbaAgReplicaSync.ps1; surface pinned by
/// migration/baselines/Compare-DbaAgReplicaSync.json.
/// </summary>
[Cmdlet(VerbsData.Compare, "DbaAgReplicaSync")]
public sealed partial class CompareDbaAgReplicaSyncCommand : DbaBaseCmdlet
{
    /// <summary>The SQL Server instance or instances hosting the availability groups.</summary>
    [Parameter(ValueFromPipeline = true, Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instances using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>Restricts the comparison to these availability groups.</summary>
    [Parameter(Position = 2)]
    public string[]? AvailabilityGroup { get; set; }

    /// <summary>Object families to skip during the comparison.</summary>
    [Parameter(Position = 3)]
    [ValidateSet("AgentCategory", "AgentOperator", "AgentAlert", "AgentProxy", "AgentSchedule", "AgentJob", "Credentials", "CustomErrors", "DatabaseMail", "LinkedServers", "Logins", "SpConfigure", "SystemTriggers")]
    public string[]? Exclude { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        if (SqlInstance is null)
        {
            return;
        }

        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            foreach (PSObject? item in NestedCommand.InvokeScoped(this, ProcessScript,
                new DbaInstanceParameter[] { instance }, SqlCredential, AvailabilityGroup,
                Exclude, EnableException.ToBool(),
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
    }
}
