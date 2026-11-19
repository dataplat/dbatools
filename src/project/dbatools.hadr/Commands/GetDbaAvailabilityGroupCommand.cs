#nullable enable

using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

// Port of public/Get-DbaAvailabilityGroup.ps1 at refs/pins/dbatools-2026-10-22. Its connect, HADR check,
// -AvailabilityGroup filter and decoration are the shared AvailabilityGroupReaderCmdlet lookup, which the
// commands that call this function nested already use; here the command's own -EnableException drives
// its Stop-Function, and each group is written as soon as it is read, as the pinned process block does.
/// <summary>Retrieves Availability Group configuration and status information from SQL Server instances.</summary>
/// <para>
/// Retrieves detailed Availability Group information including replica roles, cluster configuration, database membership, and listener details from SQL Server 2012+ instances.
/// </para>
/// <para>
/// This command helps DBAs monitor AG health, identify primary replicas for failover planning, and generate inventory reports for compliance or troubleshooting. The default view shows essential properties like replica roles, primary replica location, and cluster type, while the full object contains comprehensive AG configuration details.
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaAvailabilityGroup -SqlInstance sqlserver2014a
/// </code>
/// <para>
/// Returns basic information on all the Availability Group(s) found on sqlserver2014a.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaAvailabilityGroup -SqlInstance sqlserver2014a -AvailabilityGroup AG-a
/// </code>
/// <para>
/// Shows basic information on the Availability Group AG-a on sqlserver2014a.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaAvailabilityGroup -SqlInstance sqlserver2014a | Select-Object *
/// </code>
/// <para>
/// Returns full object properties on all Availability Group(s) on sqlserver2014a.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaAvailabilityGroup -SqlInstance sqlserver2014a | Select-Object -ExpandProperty PrimaryReplicaServerName
/// </code>
/// <para>
/// Returns the SQL Server instancename of the primary replica as a string
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaAvailabilityGroup -SqlInstance sqlserver2014a -AvailabilityGroup AG-a -IsPrimary
/// </code>
/// <para>
/// Returns true/false if the server, sqlserver2014a, is the primary replica for AG-a Availability Group.
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
/// <seealso href="https://dbatools.io/Get-DbaAvailabilityGroup" />
[Cmdlet(VerbsCommon.Get, "DbaAvailabilityGroup")]
public sealed class GetDbaAvailabilityGroupCommand : AvailabilityGroupReaderCmdlet
{
    // Positions follow the pinned function's automatic positional binding: every
    // non-switch parameter in declaration order.

    /// <para>
    /// The target SQL Server instance or instances. You must have sysadmin access and server version must be SQL Server version 2012 or higher.
    /// </para>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public DbaInstanceParameter[] SqlInstance { get; set; } = null!;

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
    /// Specifies one or more Availability Group names to filter results to specific AGs. Supports wildcards for pattern matching.
    /// Use this when you need to check status or configuration of particular AGs rather than retrieving information for all AGs on the instance.
    /// </para>
    [Parameter(Position = 2)]
    public string[]? AvailabilityGroup { get; set; }

    /// <para>
    /// Returns a boolean value indicating whether the queried SQL Server instance is currently serving as the Primary replica for each Availability Group.
    /// Use this switch when you need to quickly identify which replica in your AG topology is currently primary, particularly useful for automated failover scripts or health monitoring.
    /// </para>
    [Parameter]
    public SwitchParameter IsPrimary { get; set; }

    // Overridden only to carry the pinned .PARAMETER EnableException help; same bare [Parameter] as the base.
    /// <para>
    /// By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
    /// This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
    /// Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.
    /// </para>
    [Parameter]
    public override SwitchParameter EnableException { get; set; }

    protected override void ProcessRecord()
    {
        // The pinned process block has no Test-FunctionInterrupt check; every Stop-Function uses -Continue.
        // PS: foreach ($instance in $SqlInstance) { connect; HADR check; Where-Object Name -in; decorate; output }
        // Correction azure-unsupported: Azure SQL Database is refused as Connect-DbaInstance
        // -AzureUnsupported does; availability groups do not exist there.
        // Correction availabilitygroup-wildcards: the help documents -AvailabilityGroup wildcards.
        ReadAvailabilityGroups(SqlInstance, SqlCredential, AvailabilityGroup, (ag, wrapped) => WriteObject(wrapped),
            azureUnsupported: true, forwardEnableException: true, wildcardNames: true, isPrimary: IsPrimary.IsPresent);
    }
}
