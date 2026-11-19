#nullable enable

using System;
using System.Collections.Generic;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;
using Microsoft.SqlServer.Management.Smo.Agent;
using AgentJob = Microsoft.SqlServer.Management.Smo.Agent.Job;
using AgentOperator = Microsoft.SqlServer.Management.Smo.Agent.Operator;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Retrieves SQL Server Agent operators with their notification settings and related jobs and alerts.
/// </summary>
/// <para>
/// Retrieves detailed information about SQL Server Agent operators, including email addresses, enabled status, and relationships to jobs and alerts that notify them. Essential for auditing notification configurations, troubleshooting alert delivery issues, and maintaining disaster recovery contact lists. Shows which jobs notify each operator and tracks the last time each operator received email notifications, helping DBAs verify their monitoring and alerting infrastructure is properly configured.
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaAgentOperator -SqlInstance ServerA,ServerB\instanceB
/// </code>
/// <para>
/// Returns any SQL Agent operators on serverA and serverB\instanceB
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; 'ServerA','ServerB\instanceB' | Get-DbaAgentOperator
/// </code>
/// <para>
/// Returns all SQL Agent operators  on serverA and serverB\instanceB
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaAgentOperator -SqlInstance ServerA -Operator Dba1,Dba2
/// </code>
/// <para>
/// Returns only the SQL Agent Operators Dba1 and Dba2 on ServerA.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaAgentOperator -SqlInstance ServerA,ServerB -ExcludeOperator Dba3
/// </code>
/// <para>
/// Returns all the SQL Agent operators on ServerA and ServerB, except the Dba3 operator.
/// </para>
/// </example>
/// <list type="alertSet">
/// <item>
/// <term />
/// <description>
/// <para>
/// Tags: Agent, Operator
/// Author: Klaas Vandenberghe (@PowerDBAKlaas)
/// </para>
/// <para>
/// Website: https://dbatools.io
/// Copyright: (c) 2018 by dbatools, licensed under MIT
/// License: MIT https://opensource.org/licenses/MIT
/// </para>
/// </description>
/// </item>
/// </list>
/// <seealso href="https://dbatools.io/Get-DbaAgentOperator" />
[Cmdlet(VerbsCommon.Get, "DbaAgentOperator")]
[OutputType(typeof(AgentOperator))]
public sealed class GetDbaAgentOperatorCommand : DbaInstanceCmdlet
{
    /// <para>
    /// The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.
    /// </para>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    [PsDbaInstanceArrayCast]
    public override DbaInstanceParameter[] SqlInstance { get; set; } = null!;

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
    public override PSCredential? SqlCredential { get; set; }

    /// <para>
    /// Specifies which SQL Agent operators to retrieve by name. Accepts an array of operator names for targeting specific notification contacts.
    /// Use this when you need to check configuration or troubleshoot notification issues for particular operators instead of reviewing all operators on the instance.
    /// </para>
    [Parameter(Position = 2)]
    public object[]? Operator { get; set; }

    /// <para>
    /// Excludes specified SQL Agent operators from the results by name. Useful for filtering out test operators or disabled contacts during audits.
    /// Commonly used when reviewing active notification configurations while ignoring legacy or temporary operator accounts.
    /// </para>
    [Parameter(Position = 3)]
    public object[]? ExcludeOperator { get; set; }

    /// <para>
    /// By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
    /// This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
    /// Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.
    /// </para>
    [Parameter]
    public override SwitchParameter EnableException { get; set; }

    protected override void ProcessRecord()
    {
        if (Interrupted)
            return;

        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            if (Interrupted)
                return;

            Server? server = ConnectInstance(instance, azureUnsupported: true);
            if (server is null)
                continue;

            WriteMessage(MessageLevel.Verbose, String.Format("Getting Edition from {0}", server));
            WriteMessage(MessageLevel.Verbose, String.Format("{0} is a {1}", server, server.Edition));
            if (server.Edition.StartsWith("Express", StringComparison.OrdinalIgnoreCase))
            {
                StopFunction(String.Format("There is no SQL Agent on {0}, it's a {1}", server, server.Edition),
                    target: server, continueLoop: true);
                continue;
            }

            System.Collections.IEnumerable operators = server.JobServer.Operators;
            bool include = LanguagePrimitives.IsTrue(Operator);
            if (include || LanguagePrimitives.IsTrue(ExcludeOperator))
            {
                // The pin materializes filtered pipelines before callers can mutate the collection.
                List<AgentOperator> selected = new();
                foreach (AgentOperator agentOperator in server.JobServer.Operators)
                {
                    if (include ? ContainsName(Operator!, agentOperator.Name)
                        : !ContainsName(ExcludeOperator!, agentOperator.Name))
                        selected.Add(agentOperator);
                }
                operators = selected;
            }

            foreach (AgentOperator agentOperator in operators)
                WriteOperator(agentOperator, server);
        }
    }

    private static bool ContainsName(object[] names, string name)
    {
        foreach (object candidate in names)
        {
            if (LanguagePrimitives.Equals(candidate, name, true, CultureInfo.InvariantCulture))
                return true;
        }
        return false;
    }

    private void WriteOperator(AgentOperator agentOperator, Server server)
    {
        List<object> jobs = new();
        foreach (AgentJob job in server.JobServer.Jobs)
        {
            if (String.Equals(job.OperatorToEmail, agentOperator.Name, StringComparison.InvariantCultureIgnoreCase) ||
                String.Equals(job.OperatorToNetSend, agentOperator.Name, StringComparison.InvariantCultureIgnoreCase) ||
                String.Equals(job.OperatorToPage, agentOperator.Name, StringComparison.InvariantCultureIgnoreCase))
                jobs.Add(job);
        }

        List<object> alerts = new();
        DbaDateTime? alertLastEmail = null;
        foreach (Alert alert in server.JobServer.Alerts)
        {
            using System.Data.DataTable notifications = alert.EnumNotifications(agentOperator.Name);
            if (notifications.Rows.Count > 0)
            {
                alerts.Add(alert.Name);
                if (alertLastEmail is null || alert.LastOccurrenceDate > (DateTime)alertLastEmail)
                    alertLastEmail = new DbaDateTime(alert.LastOccurrenceDate);
            }
        }

        PSObject output = PSObject.AsPSObject(agentOperator);
        // SMO caches may return objects decorated by an earlier command invocation.
        foreach (string name in new[] { "ComputerName", "InstanceName", "SqlInstance", "RelatedJobs",
            "LastEmail", "RelatedAlerts", "AlertLastEmail", "IsEnabled" })
            output.Properties.Remove(name);

        OutputHelper.AddInstanceProperties(output, server);
        object? relatedJobs = jobs.Count == 0 ? null : jobs.Count == 1 ? jobs[0] : jobs.ToArray();
        output.Properties.Add(new PSNoteProperty("RelatedJobs", relatedJobs));
        output.Properties.Add(new PSNoteProperty("LastEmail", new DbaDateTime(agentOperator.LastEmailDate)));
        output.Properties.Add(new PSNoteProperty("RelatedAlerts", alerts.ToArray()));
        output.Properties.Add(new PSNoteProperty("AlertLastEmail", alertLastEmail));
        OutputHelper.AddAliasProperty(output, "IsEnabled", "Enabled");
        OutputHelper.SetDefaultDisplayPropertySet(output,
            "ComputerName", "InstanceName", "SqlInstance", "Name", "ID", "IsEnabled", "EmailAddress", "LastEmail");
        WriteObject(output);
    }
}
