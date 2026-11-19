#nullable enable

using System;
using System.Collections.Generic;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

// Port of public/Get-DbaAgReplica.ps1 at refs/pins/dbatools-2026-10-22. The nested
// Get-DbaAvailabilityGroup call runs through AvailabilityGroupReaderCmdlet; the pinned call adds
// -EnableException inside a try, so the first nested Stop-Function throws, ends the lookup, and
// this command's own Stop-Function reports it.
/// <summary>Retrieves availability group replica configuration and status information from SQL Server instances.</summary>
/// <para>
/// Retrieves detailed information about availability group replicas including their current role, connection state, synchronization status, and failover configuration. This function helps DBAs monitor replica health, verify failover readiness, and troubleshoot availability group issues without manually querying system views. Returns comprehensive replica properties like backup priority, endpoint URLs, session timeouts, and read-only routing lists for availability group management and compliance reporting.
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaAgReplica -SqlInstance sql2017a
/// </code>
/// <para>
/// Returns basic information on all the availability group replicas found on sql2017a
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaAgReplica -SqlInstance sql2017a -AvailabilityGroup SharePoint
/// </code>
/// <para>
/// Shows basic information on the replicas found on availability group SharePoint on sql2017a
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaAgReplica -SqlInstance sql2017a | Select-Object *
/// </code>
/// <para>
/// Returns full object properties on all availability group replicas found on sql2017a
/// </para>
/// </example>
/// <list type="alertSet">
/// <item>
/// <term />
/// <description>
/// <para>
/// Tags: AG, HA
/// Author: Shawn Melton (@wsmelton) | Chrissy LeMaire (@cl)
/// </para>
/// <para>
/// Website: https://dbatools.io
/// Copyright: (c) 2018 by dbatools, licensed under MIT
/// License: MIT https://opensource.org/licenses/MIT
/// </para>
/// </description>
/// </item>
/// </list>
/// <seealso href="https://dbatools.io/Get-DbaAgReplica" />
[Cmdlet(VerbsCommon.Get, "DbaAgReplica")]
public sealed class GetDbaAgReplicaCommand : AvailabilityGroupReaderCmdlet
{
    // Positions follow the pinned function's automatic positional binding: every
    // non-switch parameter in declaration order.

    /// <para>
    /// The target SQL Server instance or instances. Server version must be SQL Server version 2012 or higher.
    /// </para>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <para>
    /// Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).
    /// </para>
    /// <para>
    /// Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.
    /// </para>
    /// <para>
    /// For MFA support, please use Connect-DbaInstance.
    /// </para>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <para>
    /// Specifies which availability groups to query for replica information. Accepts multiple values and wildcards for pattern matching.
    /// Use this when you need to focus on specific availability groups instead of retrieving replicas from all AGs on the instance.
    /// </para>
    [Parameter(Position = 2)]
    public string[]? AvailabilityGroup { get; set; }

    /// <para>
    /// Filters results to return only the specified replica names. Accepts multiple values for querying specific replicas across availability groups.
    /// Use this when troubleshooting specific replicas or when you only need information about particular secondary replicas in your environment.
    /// </para>
    [Parameter(Position = 3)]
    public string[]? Replica { get; set; }

    /// <para>
    /// Accepts availability group objects piped from Get-DbaAvailabilityGroup, allowing for more efficient processing in pipeline scenarios.
    /// Use this when chaining commands or when you already have availability group objects and want to retrieve their replica details without additional server queries.
    /// </para>
    [Parameter(ValueFromPipeline = true, Position = 4)]
    public AvailabilityGroup[]? InputObject { get; set; }

    // Overridden only to carry the pinned .PARAMETER EnableException help; same bare [Parameter] as the base.
    /// <para>
    /// By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
    /// This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
    /// Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.
    /// </para>
    [Parameter]
    public override SwitchParameter EnableException { get; set; }

    private static readonly string[] DefaultProperties =
    {
        "ComputerName", "InstanceName", "SqlInstance", "AvailabilityGroup", "Name", "Role", "ConnectionState",
        "RollupSynchronizationState", "AvailabilityMode", "BackupPriority", "EndpointUrl", "SessionTimeout",
        "FailoverMode", "ReadonlyRoutingList"
    };

    protected override void ProcessRecord()
    {
        // The pinned process block has no Test-FunctionInterrupt check, so a stop in an earlier
        // record does not end later ones.
        if (!TestBound(nameof(SqlInstance), nameof(InputObject)))
        {
            StopFunction("You must supply either -SqlInstance or an Input Object");
            return;
        }

        // PS: $InputObject += Get-DbaAvailabilityGroup ... -EnableException - per record, the bound groups first.
        List<AvailabilityGroup> groups = new List<AvailabilityGroup>();
        if (InputObject is not null)
        {
            groups.AddRange(InputObject);
        }
        if (SqlInstance is not null && LanguagePrimitives.IsTrue(SqlInstance))
        {
            ErrorRecord? lookupError = null;
            try
            {
                // Correction azure-unsupported: Azure SQL Database is refused as Connect-DbaInstance
                // -AzureUnsupported does; availability groups do not exist there.
                // Correction availabilitygroup-wildcards: the help documents -AvailabilityGroup wildcards.
                groups.AddRange(GetAvailabilityGroups(SqlInstance, SqlCredential, AvailabilityGroup,
                    azureUnsupported: true, nestedEnableException: true, wildcardNames: true));
            }
            catch (AvailabilityGroupLookupException nested)
            {
                lookupError = nested.ErrorRecord;
            }
            catch (Exception ex) when (ex is not PipelineStoppedException)
            {
                // Any other fault inside the nested call reaches the pin's catch as well.
                lookupError = new ErrorRecord(ex, ex.GetType().Name, ErrorCategory.NotSpecified, null);
            }

            if (lookupError is not null)
            {
                // PS: Stop-Function -Message "Failure on $SqlInstance to obtain the availability group $AvailabilityGroup" -ErrorRecord $_; return
                StopFunction(string.Format("Failure on {0} to obtain the availability group {1}",
                    LanguagePrimitives.ConvertTo<string>(SqlInstance),
                    AvailabilityGroup is null ? string.Empty : LanguagePrimitives.ConvertTo<string>(AvailabilityGroup)),
                    errorRecord: lookupError);
                return;
            }
        }

        // PS: $InputObject.AvailabilityReplicas, filtered by Where-Object { $_.Name -in $Replica } when $Replica is set.
        bool filtered = LanguagePrimitives.IsTrue(Replica);
        foreach (AvailabilityGroup? ag in groups)
        {
            if (ag is null)
            {
                continue;
            }

            foreach (AvailabilityReplica replica in ag.AvailabilityReplicas)
            {
                if (filtered && !ContainsName(Replica!, replica.Name))
                {
                    continue;
                }

                WriteObject(Decorate(replica));
            }
        }
    }

    // PS: Add-Member -Force ComputerName, InstanceName, SqlInstance (read from the parent group's
    // notes, absent on an undecorated group), AvailabilityGroup, Replica; Select-DefaultView.
    private static PSObject Decorate(AvailabilityReplica replica)
    {
        PSObject parent = PSObject.AsPSObject(replica.Parent);
        PSObject wrapped = PSObject.AsPSObject(replica);
        SetNote(wrapped, "ComputerName", parent.Properties["ComputerName"]?.Value);
        SetNote(wrapped, "InstanceName", parent.Properties["InstanceName"]?.Value);
        SetNote(wrapped, "SqlInstance", parent.Properties["SqlInstance"]?.Value);
        SetNote(wrapped, "AvailabilityGroup", replica.Parent.Name);
        SetNote(wrapped, "Replica", replica.Name); // backwards compat
        OutputHelper.SetDefaultDisplayPropertySet(wrapped, DefaultProperties);
        return wrapped;
    }

    // PS: Add-Member -Force -MemberType NoteProperty replaces a same-named instance member.
    private static void SetNote(PSObject target, string name, object? value)
    {
        target.Properties.Remove(name);
        target.Properties.Add(new PSNoteProperty(name, value));
    }
}
