#nullable enable

using System;
using System.Collections.Generic;
using System.Text;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;
using Microsoft.SqlServer.Management.Smo.Agent;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Copies SQL Server Agent operators between instances for migration and standardization.
/// </summary>
/// <para>
/// Copies SQL Server Agent operators from a source instance to one or more destination instances, preserving all operator properties including email addresses, pager numbers, and notification schedules. This is essential during server migrations, environment standardization, or when setting up identical alerting configurations across multiple instances.
/// </para>
/// <para>
/// All operators are copied by default, but you can target specific operators or exclude certain ones. Existing operators on the destination are skipped unless you use -Force to overwrite them. The function protects failsafe operators from being accidentally dropped during forced operations.
/// </para>
/// <para>
/// Each operator is scripted from the source using SQL Management Objects and recreated on the destination, ensuring all configuration details are preserved exactly as configured on the source instance.
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Copy-DbaAgentOperator -Source sqlserver2014a -Destination sqlcluster
/// </code>
/// <para>
/// Copies all operators from sqlserver2014a to sqlcluster using Windows credentials. If operators with the same name exist on sqlcluster, they will be skipped.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Copy-DbaAgentOperator -Source sqlserver2014a -Destination sqlcluster -Operator PSOperator -SourceSqlCredential $cred -Force
/// </code>
/// <para>
/// Copies only the PSOperator operator from sqlserver2014a to sqlcluster using SQL credentials for sqlserver2014a and Windows credentials for sqlcluster. If an operator with the same name exists on sqlcluster, it will be dropped and recreated because -Force was used.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Copy-DbaAgentOperator -Source sqlserver2014a -Destination sqlcluster -WhatIf -Force
/// </code>
/// <para>
/// Shows what would happen if the command were executed using force.
/// </para>
/// </example>
/// <list type="alertSet">
/// <item>
/// <term />
/// <description>
/// <para>
/// Tags: Migration, Agent, Operator
/// Author: Chrissy LeMaire (@cl), netnerds.net
/// </para>
/// <para>
/// Website: https://dbatools.io
/// Copyright: (c) 2018 by dbatools, licensed under MIT
/// License: MIT https://opensource.org/licenses/MIT
/// </para>
/// <para>
/// Requires: sysadmin access on SQL Servers
/// </para>
/// </description>
/// </item>
/// </list>
/// <seealso href="https://dbatools.io/Copy-DbaAgentOperator" />
[Cmdlet(VerbsCommon.Copy, "DbaAgentOperator", DefaultParameterSetName = "Default",
    SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
public sealed class CopyDbaAgentOperatorCommand : DbaBaseCmdlet
{
    /// <para>
    /// The SQL Server instance containing the operators you want to copy from. Must be SQL Server 2000 or higher.
    /// Use this to specify which instance has the existing operators that need to be migrated or replicated to other instances.
    /// </para>
    [Parameter(Mandatory = true, Position = 0)]
    public DbaInstanceParameter Source { get; set; } = null!;

    /// <para>
    /// Credentials for connecting to the source SQL Server instance when Windows Authentication is not available.
    /// Use this when the source server requires SQL Server Authentication or when running under a different user context than your current Windows session.
    /// </para>
    [Parameter(Position = 1)]
    public PSCredential? SourceSqlCredential { get; set; }

    /// <para>
    /// One or more SQL Server instances where the operators will be copied to. Must be SQL Server 2000 or higher.
    /// Accepts multiple instances to copy operators to several servers at once during migrations or standardization projects.
    /// </para>
    [Parameter(Mandatory = true, Position = 2)]
    public DbaInstanceParameter[] Destination { get; set; } = null!;

    /// <para>
    /// Credentials for connecting to the destination SQL Server instances when Windows Authentication is not available.
    /// Use this when the destination servers require SQL Server Authentication or when running under a different user context than your current Windows session.
    /// </para>
    [Parameter(Position = 3)]
    public PSCredential? DestinationSqlCredential { get; set; }

    /// <para>
    /// Specifies which operators to copy by name. Accepts wildcards and multiple operator names.
    /// Use this when you only need to migrate specific operators instead of copying all operators from the source instance.
    /// </para>
    [Parameter(Position = 4)]
    public object[]? Operator { get; set; }

    /// <para>
    /// Operators to skip during the copy operation. Accepts wildcards and multiple operator names.
    /// Use this to copy most operators while excluding specific ones, such as development-only or temporary operators.
    /// </para>
    [Parameter(Position = 5)]
    public object[]? ExcludeOperator { get; set; }

    /// <para>
    /// Drops and recreates operators that already exist on the destination instances.
    /// Use this when you need to overwrite existing operators with updated configurations from the source, but note that failsafe operators are protected and will be skipped.
    /// </para>
    [Parameter]
    public SwitchParameter Force { get; set; }

    private Server? _source;
    private OperatorCollection? _operators;

    protected override void BeginProcessing()
    {
        _source = OpenServer(Source, SourceSqlCredential, false);
        if (_source is not null) _operators = _source.JobServer.Operators;
    }

    /// <para>
    /// By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
    /// This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
    /// Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.
    /// </para>
    [Parameter]
    public override SwitchParameter EnableException { get; set; }

    protected override void ProcessRecord()
    {
        if (Interrupted || _source is null || _operators is null) return;
        List<string> scope = new List<string>();
        foreach (Operator sourceOperator in _operators) scope.Add(sourceOperator.Name);
        WildcardNameMatcher include = WildcardNameFilter.CreateMatcher(Operator, true,
            (value, name) => LanguagePrimitives.Equals(value, name, true), scope);
        WildcardNameMatcher exclude = WildcardNameFilter.CreateMatcher(ExcludeOperator, true,
            (value, name) => LanguagePrimitives.Equals(value, name, true), scope);
        foreach (DbaInstanceParameter destination in Destination)
        {
            CancellationToken.ThrowIfCancellationRequested();
            Server? server = OpenServer(destination, DestinationSqlCredential, true);
            if (server is null) continue;
            OperatorCollection existing = server.JobServer.Operators;
            string failsafe = server.JobServer.AlertSystem.FailSafeOperator;
            foreach (Operator sourceOperator in _operators)
            {
                CancellationToken.ThrowIfCancellationRequested();
                string name = sourceOperator.Name;
                if ((LanguagePrimitives.IsTrue(Operator) && !include.Matches(name)) ||
                    exclude.Matches(name)) continue;
                DateTime timestamp = DateTime.Now;
                Operator? target = null;
                foreach (Operator candidate in existing)
                    if (LanguagePrimitives.Equals(candidate.Name, name, true)) { target = candidate; break; }
                if (target is not null)
                {
                    if (!Force)
                    {
                        string action = string.Format("Operator {0} exists at destination. Use -Force to drop and migrate.", name);
                        if (Approve(destination, action))
                        {
                            Emit(server, name, timestamp, "Skipped", "Already exists on destination");
                            WriteMessage(MessageLevel.Verbose, action);
                        }
                        continue;
                    }
                    if (LanguagePrimitives.Equals(failsafe, name, true))
                    {
                        WriteMessage(MessageLevel.Verbose, name + " is the failsafe operator. Skipping drop.");
                        continue;
                    }
                    if (Approve(destination, string.Format("Dropping operator {0} and recreating", name)))
                    {
                        try
                        {
                            WriteMessage(MessageLevel.Verbose, "Dropping Operator " + name);
                            target.Drop();
                        }
                        catch (PipelineStoppedException) { throw; }
                        catch (Exception ex)
                        {
                            Emit(server, name, timestamp, "Failed");
                            WriteMessage(MessageLevel.Verbose, string.Format("Issue dropping operator {0} on {1} | {2}", name, destination, ex.Message));
                            continue;
                        }
                    }
                }
                if (!Approve(destination, "Creating Operator " + name)) continue;
                try
                {
                    WriteMessage(MessageLevel.Verbose, "Copying Operator " + name);
                    StringBuilder script = new StringBuilder();
                    foreach (string? batch in sourceOperator.Script()) script.AppendLine(batch);
                    string sql = script.ToString();
                    WriteMessage(MessageLevel.Debug, sql);
                    server.ConnectionContext.ExecuteNonQuery(sql);
                    server.JobServer.Operators.Refresh();
                    Emit(server, name, timestamp, "Successful");
                }
                catch (PipelineStoppedException) { throw; }
                catch (Exception ex)
                {
                    Emit(server, name, timestamp, "Failed");
                    WriteMessage(MessageLevel.Verbose, string.Format("Issue creating operator {0} on {1} | {2}", name, destination, ex.Message));
                }
            }
        }
    }

    private Server? OpenServer(DbaInstanceParameter instance, PSCredential? credential, bool continueLoop)
    {
        SmoConnectionRequest request = new SmoConnectionRequest
        {
            Instance = instance,
            SqlCredential = credential,
            AzureUnsupported = true,
            BoundParameters = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "SqlInstance", "SqlCredential", "AzureUnsupported" },
            MessageCallback = (level, message) => WriteAttributedMessage("Connect-DbaInstance", level, message)
        };
        WriteAttributedMessage("Connect-DbaInstance", MessageLevel.Debug, "Starting process block");
        try
        {
            Server connected = ConnectionService.GetServer(request);
            SetActiveConnection(connected.ConnectionContext);
            WriteAttributedMessage("Connect-DbaInstance", MessageLevel.Debug, "We are finished with this instance");
            return connected;
        }
        catch (PipelineStoppedException) { throw; }
        catch (Exception ex)
        {
            ErrorRecord failure = new ErrorRecord(ex, "dbatools_Copy-DbaAgentOperator", ErrorCategory.ConnectionError, instance);
            StopFunction("Failure", errorRecord: failure, target: instance, category: ErrorCategory.ConnectionError, continueLoop: continueLoop);
            return null;
        }
    }

    private bool Approve(DbaInstanceParameter destination, string action)
    {
        Func<bool> decide = () => ShouldProcess(destination.ToString(), action);
        return Force ? AgentConfirmation.WithConfirmationSuppressed(SessionState, decide) : decide();
    }

    private void Emit(Server destination, string name, DateTime timestamp, string status, string? notes = null)
    {
        PSObject result = new PSObject();
        string[] names = { "SourceServer", "DestinationServer", "Name", "Type", "Status", "Notes", "DateTime" };
        object?[] values = { _source!.Name, destination.Name, name, "Agent Operator", status, notes, new DbaDateTime(timestamp) };
        for (int index = 0; index < names.Length; index++)
            result.Properties.Add(new PSNoteProperty(names[index], values[index]));
        OutputHelper.InsertTypeName(result, "MigrationObject");
        OutputHelper.SetDefaultDisplayPropertySet(result, "DateTime", "SourceServer", "DestinationServer", "Name", "Type", "Status", "Notes");
        WriteObject(result);
    }
}
