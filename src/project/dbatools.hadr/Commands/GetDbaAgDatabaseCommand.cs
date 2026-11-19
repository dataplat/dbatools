#nullable enable

using System;
using System.Collections.Generic;
using System.Management.Automation;
using System.Text.RegularExpressions;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

// Port of public/Get-DbaAgDatabase.ps1 at refs/pins/dbatools-2026-10-22. The nested
// Get-DbaAvailabilityGroup call is absorbed by the shared AvailabilityGroupReaderCmdlet base:
// its connect, HADR check, group filter and group decoration run there, and its Stop-Function
// warnings keep its name and never throw, because the pinned call passes no -EnableException.
/// <summary>Retrieves availability group database information and synchronization status from SQL Server instances.</summary>
/// <para>Retrieves detailed information about databases participating in SQL Server availability groups, including their synchronization state, failover readiness, and replica-specific status. This function queries the availability group configuration from each SQL Server instance to return database-level health and status information that varies depending on whether the replica is primary or secondary.</para>
/// <para>Use this command to monitor availability group database health, troubleshoot synchronization issues, verify failover readiness, or generate compliance reports showing which databases are properly synchronized across your availability group replicas. The returned data includes critical operational details like suspension status, join state, and synchronization health that help DBAs quickly identify databases requiring attention.</para>
/// <list type="alertSet">
///   <item>
///     <term></term>
///     <description>
///       <para>Tags: AG, HA</para>
///       <para>Author: Shawn Melton (@wsmelton), wsmelton.github.io</para>
///       <para>Website: https://dbatools.io</para>
///       <para>Copyright: (c) 2018 by dbatools, licensed under MIT</para>
///       <para>License: MIT https://opensource.org/licenses/MIT</para>
///     </description>
///   </item>
/// </list>
/// <example>
///   <prefix>PS C:\&gt;</prefix>
///   <code>Get-DbaAgDatabase -SqlInstance sql2017a</code>
///   <para>Returns all the databases in each availability group found on sql2017a</para>
/// </example>
/// <example>
///   <prefix>PS C:\&gt;</prefix>
///   <code>Get-DbaAgDatabase -SqlInstance sql2017a -AvailabilityGroup AG101</code>
///   <para>Returns all the databases in the availability group AG101 on sql2017a</para>
/// </example>
/// <example>
///   <prefix>PS C:\&gt;</prefix>
///   <code>Get-DbaAgDatabase -SqlInstance sql2017a -ExcludeDatabase TestDB,StagingDB</code>
///   <para>Returns all the databases in each availability group found on sql2017a, excluding TestDB and StagingDB.</para>
/// </example>
/// <example>
///   <prefix>PS C:\&gt;</prefix>
///   <code>Get-DbaAgDatabase -SqlInstance sql2017a -Pattern "^dbatools_"</code>
///   <para>Returns all databases in each availability group found on sql2017a that match the regex pattern "^dbatools_" (e.g., dbatools_example1, dbatools_example2)</para>
/// </example>
/// <example>
///   <prefix>PS C:\&gt;</prefix>
///   <code>Get-DbaAvailabilityGroup -SqlInstance sqlcluster -AvailabilityGroup SharePoint | Get-DbaAgDatabase -Database Sharepoint_Config</code>
///   <para>Returns the database Sharepoint_Config found in the availability group SharePoint on server sqlcluster</para>
/// </example>
/// <seealso href="https://dbatools.io/Get-DbaAgDatabase"/>
[Cmdlet(VerbsCommon.Get, "DbaAgDatabase")]
[OutputType(typeof(AvailabilityDatabase))]
public sealed class GetDbaAgDatabaseCommand : AvailabilityGroupReaderCmdlet
{
    // Positions follow the pinned function's automatic positional binding: every
    // non-switch parameter in declaration order.

    /// <para>The target SQL Server instance or instances. Server version must be SQL Server version 2012 or higher.</para>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <para>Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).</para>
    /// <para>Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.</para>
    /// <para>For MFA support, please use Connect-DbaInstance.</para>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <para>Specifies which availability groups to query for database information. Accepts multiple availability group names.</para>
    /// <para>Use this to limit results to specific availability groups when you have multiple AGs on the same instance.</para>
    [Parameter(Position = 2)]
    public string[]? AvailabilityGroup { get; set; }

    /// <para>Specifies which availability group databases to return information for. Accepts multiple database names with tab completion.</para>
    /// <para>Use this to focus on specific databases when troubleshooting AG issues or monitoring particular applications.</para>
    [Parameter(Position = 3)]
    public string[]? Database { get; set; }

    /// <para>Specifies one or more databases to exclude from the results using exact name matching.</para>
    /// <para>Use this to filter out specific databases like test or staging environments from your results.</para>
    [Parameter(Position = 4)]
    public string[]? ExcludeDatabase { get; set; }

    /// <para>Specifies a pattern for filtering databases using regular expressions.</para>
    /// <para>Use this when you need to match databases by pattern, such as &quot;^dbatools_&quot; or &quot;.*_prod$&quot;.</para>
    /// <para>This parameter supports standard .NET regular expression syntax.</para>
    [Parameter(Position = 5)]
    public string[]? Pattern { get; set; }

    /// <para>Accepts availability group objects from Get-DbaAvailabilityGroup via pipeline input.</para>
    /// <para>Use this when you want to chain commands to get database details from already retrieved availability groups.</para>
    [Parameter(ValueFromPipeline = true, Position = 6)]
    public AvailabilityGroup[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet.

    protected override void ProcessRecord()
    {
        // The pinned process block has no Test-FunctionInterrupt check, so a stop in an earlier
        // record does not end later ones.
        if (!TestBound(nameof(SqlInstance), nameof(InputObject)))
        {
            StopFunction("You must supply either -SqlInstance or an Input Object");
            return;
        }

        // PS: $InputObject += Get-DbaAvailabilityGroup ... - per record, the bound groups first.
        List<AvailabilityGroup> groups = new List<AvailabilityGroup>();
        if (InputObject is not null)
        {
            groups.AddRange(InputObject);
        }
        if (SqlInstance is not null && LanguagePrimitives.IsTrue(SqlInstance))
        {
            // Correction azure-unsupported: Azure SQL Database is refused as Connect-DbaInstance
            // -AzureUnsupported does; availability groups do not exist there.
            groups.AddRange(GetAvailabilityGroups(SqlInstance, SqlCredential, AvailabilityGroup, azureUnsupported: true));
        }

        // PS: foreach ($db in $InputObject.AvailabilityDatabases)
        foreach (AvailabilityGroup? group in groups)
        {
            if (group is null)
            {
                continue;
            }
            foreach (AvailabilityDatabase db in group.AvailabilityDatabases)
            {
                if (FilterHelper.IsActive(Database) && !ContainsName(Database!, db.Name))
                {
                    continue;
                }
                if (FilterHelper.IsActive(ExcludeDatabase) && ContainsName(ExcludeDatabase!, db.Name))
                {
                    continue;
                }
                if (FilterHelper.IsActive(Pattern) && !MatchesPattern(db.Name, Pattern!))
                {
                    continue;
                }

                AvailabilityGroup ag = db.Parent;
                Server server = ag.Parent;
                PSObject wrapped = PSObject.AsPSObject(db);
                // PS: Add-Member -Force replaces earlier values.
                foreach (string name in new[] { "ComputerName", "InstanceName", "SqlInstance", "AvailabilityGroup", "LocalReplicaRole" })
                {
                    wrapped.Properties.Remove(name);
                }
                OutputHelper.AddInstanceProperties(wrapped, server);
                wrapped.Properties.Add(new PSNoteProperty("AvailabilityGroup", ag.Name));
                wrapped.Properties.Add(new PSNoteProperty("LocalReplicaRole", ag.LocalReplicaRole));
                OutputHelper.SetDefaultDisplayPropertySet(wrapped,
                    "ComputerName", "InstanceName", "SqlInstance", "AvailabilityGroup", "LocalReplicaRole", "Name",
                    "SynchronizationState", "IsFailoverReady", "IsJoined", "IsSuspended");
                WriteObject(wrapped);
            }
        }
    }

    // PS: the begin block's $matchesPattern: $name -match $pattern for any pattern. An invalid
    // pattern makes -match raise the regex parser's exception as a statement-terminating fault:
    // outside a caller try the engine writes it and the loop tries the next pattern; a caller try
    // catches it and the command ends.
    private bool MatchesPattern(string? name, string[] patterns)
    {
        foreach (string? pattern in patterns)
        {
            try
            {
                if (Regex.IsMatch(name ?? string.Empty, pattern ?? string.Empty, RegexOptions.IgnoreCase))
                {
                    return true;
                }
            }
            catch (ArgumentException ex)
            {
                // PS: the -match statement surfaces the runtime's own exception (ArgumentException on .NET Framework,
                // RegexParseException on .NET) as the record's exception, its type name as the error id, OperationStopped
                // and no target.
                ReportPatternFault(new ErrorRecord(ex, ex.GetType().ToString(), ErrorCategory.OperationStopped, null));
            }
        }
        return false;
    }

    // Accepted differences kept by the keep-going section's point 3: -EnableException stops here with this record, where the
    // pin writes it and goes on; -ErrorAction Stop has the effect PowerShell gives WriteError.
    private void ReportPatternFault(ErrorRecord fault)
    {
        if (EnableException.ToBool())
        {
            // caller-try: terminate -- -EnableException asks for the stop
            ThrowTerminatingError(fault); // style-ok: cs-raw-streams statement fault outside Stop-Function, as in the source
        }

        // A plain call writes the record and tries the next pattern; under a caller try the record ends the command.
        StatementFault.Surface(this, fault);
    }
}
