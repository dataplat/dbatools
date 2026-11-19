#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Collections.Specialized;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;
using Microsoft.SqlServer.Management.Smo.Agent;
using SmoJobCategory = Microsoft.SqlServer.Management.Smo.Agent.JobCategory;
using SmoAlertCategory = Microsoft.SqlServer.Management.Smo.Agent.AlertCategory;
using SmoOperatorCategory = Microsoft.SqlServer.Management.Smo.Agent.OperatorCategory;

namespace Dataplat.Dbatools.Commands;

/// <summary>Copies custom SQL Agent categories for jobs, alerts, and operators between SQL Server instances.</summary>
[Cmdlet(VerbsCommon.Copy, "DbaAgentJobCategory", DefaultParameterSetName = "Default",
    SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
public sealed class CopyDbaAgentJobCategoryCommand : DbaBaseCmdlet
{
    /// <summary>The source SQL Server instance.</summary>
    [Parameter(Mandatory = true)]
    public DbaInstanceParameter Source { get; set; } = null!;

    /// <summary>Alternative credential for the source instance.</summary>
    [Parameter]
    public PSCredential? SourceSqlCredential { get; set; }

    /// <summary>The destination SQL Server instances.</summary>
    [Parameter(Mandatory = true)]
    public DbaInstanceParameter[] Destination { get; set; } = null!;

    /// <summary>Alternative credential for destination instances.</summary>
    [Parameter]
    public PSCredential? DestinationSqlCredential { get; set; }

    /// <summary>Category types to copy.</summary>
    [Parameter(ParameterSetName = "SpecificAlerts")]
    [ValidateSet("Job", "Alert", "Operator")]
    public string[]? CategoryType { get; set; }

    /// <summary>Job category names to copy.</summary>
    [Parameter]
    public string[]? JobCategory { get; set; }

    /// <summary>Alert category names to copy.</summary>
    [Parameter]
    [Alias("AgentCategory")]
    public string[]? AlertCategory { get; set; }

    /// <summary>Operator category names to copy.</summary>
    [Parameter]
    public string[]? OperatorCategory { get; set; }

    /// <summary>Drop and recreate categories that already exist.</summary>
    [Parameter]
    public SwitchParameter Force { get; set; }


    private Server? _source;

    protected override void BeginProcessing()
    {
        _source = Connect(Source, SourceSqlCredential, false);
    }

    protected override void ProcessRecord()
    {
        if (Interrupted || _source is null) return;
        foreach (DbaInstanceParameter destination in Destination)
        {
            CancellationToken.ThrowIfCancellationRequested();
            Server? server = Connect(destination, DestinationSqlCredential, true);
            if (server is null) continue;
            if (CategoryType is not null && CategoryType.Length > 0)
            {
                foreach (string type in CategoryType) CopyCategories(server, destination, type, null);
                continue;
            }
            if ((OperatorCategory?.Length ?? 0) + (AlertCategory?.Length ?? 0) + (JobCategory?.Length ?? 0) > 0)
            {
                if (OperatorCategory is not null && OperatorCategory.Length > 0) CopyCategories(server, destination, "Operator", OperatorCategory);
                if (AlertCategory is not null && AlertCategory.Length > 0) CopyCategories(server, destination, "Alert", AlertCategory);
                if (JobCategory is not null && JobCategory.Length > 0) CopyCategories(server, destination, "Job", JobCategory);
                continue;
            }
            CopyCategories(server, destination, "Operator", null);
            CopyCategories(server, destination, "Alert", null);
            CopyCategories(server, destination, "Job", null);
        }
    }

    private void CopyCategories(Server server, DbaInstanceParameter destination, string type, string[]? names)
    {
        bool job = LanguagePrimitives.Equals(type, "Job", true, CultureInfo.InvariantCulture);
        bool alert = LanguagePrimitives.Equals(type, "Alert", true, CultureInfo.InvariantCulture);
        string title = job ? "Job" : alert ? "Alert" : "Operator";
        string lower = title.ToLowerInvariant();
        if (alert && (_source!.VersionMajor < 9 || server.VersionMajor < 9))
        {
            const string message = "Server AlertCategories are only supported in SQL Server 2005 and above. Quitting.";
            // caller-try: terminate -- the source explicitly throws before category discovery on unsupported versions
            ThrowTerminatingError(new ErrorRecord(new RuntimeException(message), message, ErrorCategory.OperationStopped, message)); // style-ok: cs-raw-streams preserve explicit source throw independently of EnableException
            return;
        }

        List<CategoryBase> sourceCategories = Categories(_source!, title);
        List<CategoryBase> destinationCategories = Categories(server, title);
        foreach (CategoryBase category in sourceCategories)
        {
            CancellationToken.ThrowIfCancellationRequested();
            string name = category.Name;
            PSObject status = Status(server, name, title);
            if (names is not null && names.Length > 0 && !AgentNameFilter.ContainsName(names, name)) continue;
            CategoryBase? existing = null;
            foreach (CategoryBase candidate in destinationCategories)
                if (LanguagePrimitives.Equals(candidate.Name, name, true, CultureInfo.InvariantCulture)) { existing = candidate; break; }
            if (existing is not null)
            {
                if (!Force)
                {
                    string action = string.Format("{0} category {1} exists at destination. Use -Force to drop and migrate.", title, name);
                    if (Confirm(destination, action))
                    {
                        Emit(status, "Skipped", "Already exists on destination");
                        WriteMessage(MessageLevel.Verbose, action);
                    }
                    continue;
                }
                string dropAction = string.Format("Dropping {0} category {1}", lower, name);
                if (!job) dropAction += " and recreating";
                if (Confirm(destination, dropAction))
                {
                    try
                    {
                        WriteMessage(MessageLevel.Verbose, string.Format("Dropping {0} category {1}", title, name));
                        existing.Drop();
                        if (!job)
                        {
                            CopyDefinition(server, category, title, alert);
                            Emit(status, "Successful");
                        }
                    }
                    catch (PipelineStoppedException) { throw; }
                    catch (Exception ex)
                    {
                        Emit(status, "Failed");
                        WriteMessage(MessageLevel.Verbose, string.Format("Issue dropping {0} category {1} on {2} | {3}", lower, name, destination, ex.Message));
                        continue;
                    }
                }
                if (!job) continue;
            }

            if (Confirm(destination, string.Format("Creating {0} category {1}", title, name)))
            {
                try
                {
                    CopyDefinition(server, category, title, job);
                    Emit(status, "Successful");
                }
                catch (PipelineStoppedException) { throw; }
                catch (Exception ex)
                {
                    Emit(status, "Failed");
                    WriteMessage(MessageLevel.Verbose, string.Format("Issue {0} {1} category {2} on {3} | {4}",
                        alert ? "creating" : "copying", lower, name, destination, ex.Message));
                }
            }
        }
    }

    private void CopyDefinition(Server server, CategoryBase category, string title, bool sqlPrefix)
    {
        WriteMessage(MessageLevel.Verbose, string.Format("Copying {0} category {1}", title, category.Name));
        StringCollection script = category.Script();
        List<string> lines = new List<string>();
        foreach (string? line in script) lines.Add(line ?? "");
        string sql = string.Join(Environment.NewLine, lines) + Environment.NewLine;
        WriteMessage(MessageLevel.Debug, sqlPrefix ? "SQL Statement: " + sql : sql);
        server.ConnectionContext.ExecuteNonQuery(sql);
    }

    private static List<CategoryBase> Categories(Server server, string type)
    {
        IEnumerable collection = type == "Job" ? (IEnumerable)server.JobServer.JobCategories :
            type == "Alert" ? server.JobServer.AlertCategories : server.JobServer.OperatorCategories;
        List<CategoryBase> result = new List<CategoryBase>();
        foreach (CategoryBase category in collection)
        {
            int id = category is SmoJobCategory job ? job.ID :
                category is SmoAlertCategory alert ? alert.ID : ((SmoOperatorCategory)category).ID;
            if (id >= 100) result.Add(category);
        }
        return result;
    }

    private Server? Connect(DbaInstanceParameter instance, PSCredential? credential, bool continueLoop)
    {
        WriteAttributedMessage("Connect-DbaInstance", MessageLevel.Debug, "Starting process block");
        try
        {
            Server server = ConnectionService.GetServer(new SmoConnectionRequest
            {
                Instance = instance, SqlCredential = credential, AzureUnsupported = true,
                BoundParameters = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "SqlInstance", "SqlCredential", "AzureUnsupported" },
                MessageCallback = (level, message) => WriteAttributedMessage("Connect-DbaInstance", level, message)
            });
            SetActiveConnection(server.ConnectionContext);
            WriteAttributedMessage("Connect-DbaInstance", MessageLevel.Debug, "We are finished with this instance");
            return server;
        }
        catch (PipelineStoppedException) { throw; }
        catch (Exception ex)
        {
            StopFunction("Failure", target: instance, errorRecord: new ErrorRecord(ex, "dbatools_Copy-DbaAgentJobCategory", ErrorCategory.ConnectionError, instance),
                category: ErrorCategory.ConnectionError, continueLoop: continueLoop);
            return null;
        }
    }

    private bool Confirm(DbaInstanceParameter instance, string action)
    {
        return Force ? AgentConfirmation.WithConfirmationSuppressed(SessionState, () => ShouldProcess(instance.ToString(), action))
            : ShouldProcess(instance.ToString(), action);
    }

    private PSObject Status(Server destination, string name, string type)
    {
        PSObject result = new PSObject();
        result.Properties.Add(new PSNoteProperty("SourceServer", _source!.Name));
        result.Properties.Add(new PSNoteProperty("DestinationServer", destination.Name));
        if (type == "Job") result.Properties.Add(new PSNoteProperty("Name", name));
        result.Properties.Add(new PSNoteProperty("Type", string.Format("Agent {0} Category", type)));
        if (type != "Job") result.Properties.Add(new PSNoteProperty("Name", name));
        result.Properties.Add(new PSNoteProperty("Status", null));
        result.Properties.Add(new PSNoteProperty("Notes", null));
        result.Properties.Add(new PSNoteProperty("DateTime", new DbaDateTime(DateTime.Now)));
        OutputHelper.SetDefaultDisplayPropertySet(result, "DateTime", "SourceServer", "DestinationServer", "Name", "Type", "Status", "Notes");
        OutputHelper.InsertTypeName(result, "MigrationObject");
        return result;
    }

    private void Emit(PSObject result, string status, string? notes = null)
    {
        result.Properties["Status"].Value = status;
        result.Properties["Notes"].Value = notes;
        WriteObject(result);
    }
}
