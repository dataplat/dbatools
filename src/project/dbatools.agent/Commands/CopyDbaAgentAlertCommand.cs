#nullable enable

using System;
using System.Collections.Generic;
using System.Collections.Specialized;
using System.Data;
using System.Globalization;
using System.Management.Automation;
using System.Text.RegularExpressions;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;
using Microsoft.SqlServer.Management.Smo.Agent;
using SmoAlert = Microsoft.SqlServer.Management.Smo.Agent.Alert;
using Job = Microsoft.SqlServer.Management.Smo.Agent.Job;

namespace Dataplat.Dbatools.Commands;

/// <summary>Copies SQL Server Agent alerts from source instance to destination instances</summary>
[Cmdlet(VerbsCommon.Copy, "DbaAgentAlert", DefaultParameterSetName = "Default",
    SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
public sealed class CopyDbaAgentAlertCommand : DbaBaseCmdlet
{
    /// <summary>The source SQL Server instance.</summary>
    [Parameter(Mandatory = true, Position = 0)]
    public DbaInstanceParameter Source { get; set; } = null!;

    /// <summary>Alternative credential for the source instance.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SourceSqlCredential { get; set; }

    /// <summary>The destination SQL Server instances.</summary>
    [Parameter(Mandatory = true, Position = 2)]
    public DbaInstanceParameter[] Destination { get; set; } = null!;

    /// <summary>Alternative credential for destination instances.</summary>
    [Parameter(Position = 3)]
    public PSCredential? DestinationSqlCredential { get; set; }

    /// <summary>Only copy alerts with these names.</summary>
    [Parameter(Position = 4)]
    public object[]? Alert { get; set; }

    /// <summary>Exclude alerts with these names.</summary>
    [Parameter(Position = 5)]
    public object[]? ExcludeAlert { get; set; }

    /// <summary>Copy SQL Agent alert-system defaults.</summary>
    [Parameter]
    public SwitchParameter IncludeDefaults { get; set; }

    /// <summary>Drop and recreate alerts that already exist.</summary>
    [Parameter]
    public SwitchParameter Force { get; set; }


    private Server? _source;
    private AlertCollection? _alerts;

    protected override void BeginProcessing()
    {
        _source = Connect(Source, SourceSqlCredential, false);
        if (_source is null) return;
        _alerts = _source.JobServer.Alerts;
    }

    protected override void ProcessRecord()
    {
        if (Interrupted || _source is null || _alerts is null) return;
        foreach (DbaInstanceParameter destination in Destination)
        {
            CancellationToken.ThrowIfCancellationRequested();
            Server? server = Connect(destination, DestinationSqlCredential, true);
            if (server is null) continue;
            AlertCollection destinationAlerts = server.JobServer.Alerts;

            if (IncludeDefaults && Confirm(destination, "Creating Alert Defaults"))
            {
                PSObject defaults = Status(server, "Alert Defaults", "Alert Defaults");
                try
                {
                    WriteMessage(MessageLevel.Verbose, "Creating Alert Defaults");
                    string sql = ScriptText(_source.JobServer.AlertSystem.Script());
                    string oldLiteral = string.Concat("'", Source.ToString().Replace("'", "''"), "'");
                    string newLiteral = string.Concat("'", destination.ToString().Replace("'", "''"), "'");
                    sql = Regex.Replace(sql, Regex.Escape(oldLiteral), match => newLiteral, RegexOptions.IgnoreCase);
                    Execute(server, sql);
                    // Source emits defaults status only on failure.
                    defaults.Properties["Status"].Value = "Successful";
                }
                catch (PipelineStoppedException) { throw; }
                catch (Exception ex)
                {
                    Emit(defaults, "Failed");
                    WriteMessage(MessageLevel.Verbose, string.Format("Issue creating alert defaults on {0} | {1}", destination, ex.Message));
                }
            }

            OperatorCollection operators = server.JobServer.Operators;
            foreach (SmoAlert sourceAlert in _alerts)
            {
                CancellationToken.ThrowIfCancellationRequested();
                string name = sourceAlert.Name;
                PSObject status = Status(server, name, "Agent Alert");
                if ((Alert is not null && Alert.Length > 0 && !Contains(Alert, name)) ||
                    (ExcludeAlert is not null && ExcludeAlert.Length > 0 && Contains(ExcludeAlert, name)))
                    continue;

                if (sourceAlert.HasNotification != 0)
                {
                    DataTable? notifications = Uncaught(() => sourceAlert.EnumNotifications(), "EnumNotifications");
                    List<object> operatorNames = new List<object>();
                    foreach (Operator item in operators) operatorNames.Add(item.Name);
                    object? destinationNames = operatorNames.Count == 0 ? null :
                        operatorNames.Count == 1 ? operatorNames[0] : operatorNames.ToArray();
                    // Preserve the pinned property-enumeration shape and -notin gate.
                    bool checkMissing = true;
                    if (notifications is not null)
                    {
                        foreach (DataRow notification in notifications.Rows)
                        {
                            if (LanguagePrimitives.Equals(notification["OperatorName"], destinationNames, true))
                            { checkMissing = false; break; }
                        }
                    }
                    List<string> missing = new List<string>();
                    if (notifications is not null)
                    {
                        foreach (DataRow notification in notifications.Rows)
                        {
                            if (!checkMissing) break;
                            string operatorName = Convert.ToString(notification["OperatorName"], CultureInfo.CurrentCulture) ?? "";
                            bool found = false;
                            foreach (Operator item in operators)
                                if (LanguagePrimitives.Equals(item.Name, operatorName, true)) { found = true; break; }
                            if (!found) missing.Add(operatorName);
                        }
                    }
                    if (missing.Count > 0)
                    {
                        string names = string.Join(",", missing);
                        if (Confirm(destination, "Missing operator(s) at destination."))
                        {
                            Emit(status, "Skipped", string.Format("Operator(s) [{0}] do not exist on destination", names));
                            WriteMessage(MessageLevel.Warning, string.Format("One or more operators alerted by [{0}] is not present at the destination. Alert will not be copied. Use Copy-DbaAgentOperator to copy the operator(s) to the destination. Missing operator(s): {1}", name, names));
                        }
                        continue;
                    }
                }

                SmoAlert? existing = FindAlert(destinationAlerts, name);
                if (existing is not null)
                {
                    if (!Force)
                    {
                        string action = string.Format("Alert [{0}] exists at destination. Use -Force to drop and migrate.", name);
                        if (Confirm(destination, action))
                        {
                            Emit(status, "Skipped", "Already exists on destination");
                            WriteMessage(MessageLevel.Verbose, action);
                        }
                        continue;
                    }
                    if (Confirm(destination, string.Format("Dropping alert {0} and recreating", name)))
                    {
                        try
                        {
                            WriteMessage(MessageLevel.Verbose, string.Format("Dropping Alert {0} on {1}.", name, server));
                            WriteMessage(MessageLevel.Debug, string.Format("EXEC msdb.dbo.sp_delete_alert @name = N'{0}';", name.Replace("'", "''")));
                            existing.Drop();
                            destinationAlerts.Refresh();
                        }
                        catch (PipelineStoppedException) { throw; }
                        catch (Exception ex)
                        {
                            Emit(status, "Failed");
                            WriteMessage(MessageLevel.Verbose, string.Format("Issue dropping/recreating alert {0} on {1} | {2}", name, destination, ex.Message));
                            continue;
                        }
                    }
                }

                bool conflict = false;
                foreach (SmoAlert item in destinationAlerts)
                {
                    int? severity = null;
                    try { severity = item.Severity; }
                    catch (Microsoft.SqlServer.Management.Common.ExecutionFailureException)
                    {
                        // The pin's adapted getter yields no value; the copy and refreshes report the denial.
                    }
                    if (severity == sourceAlert.Severity && item.MessageID == sourceAlert.MessageID &&
                        LanguagePrimitives.Equals(item.DatabaseName, sourceAlert.DatabaseName, true) &&
                        LanguagePrimitives.Equals(item.EventDescriptionKeyword, sourceAlert.EventDescriptionKeyword, true))
                    { conflict = true; break; }
                }
                if (conflict)
                {
                    if (Confirm(destination, "Checking for conflicts"))
                    {
                        string message = string.Format("Alert [{0}] has already been defined to use", name);
                        if (sourceAlert.Severity > 0) message += " severity " + sourceAlert.Severity;
                        if (sourceAlert.MessageID > 0) message += " error number " + sourceAlert.MessageID;
                        if (!string.IsNullOrEmpty(sourceAlert.DatabaseName)) message += string.Format(" on database '{0}'", sourceAlert.DatabaseName);
                        if (!string.IsNullOrEmpty(sourceAlert.EventDescriptionKeyword)) message += string.Format(" with error text '{0}'", sourceAlert.EventDescriptionKeyword);
                        message += ". Skipping.";
                        WriteMessage(MessageLevel.Verbose, message);
                        Emit(status, "Skipped", message);
                    }
                    continue;
                }
                if (!string.IsNullOrEmpty(sourceAlert.JobName) && FindJob(server.JobServer.Jobs, sourceAlert.JobName) is null)
                {
                    WriteMessage(MessageLevel.Verbose, string.Format("Alert [{0}] has job [{1}] configured as response. The job does not exist on destination {2}. Skipping.", name, sourceAlert.JobName, server));
                    if (Confirm(destination, "Checking for conflicts")) Emit(status, "Skipped");
                    continue;
                }

                if (Confirm(destination, "Creating Alert " + name))
                {
                    try
                    {
                        WriteMessage(MessageLevel.Verbose, "Copying Alert " + name);
                        // SMO omits only the job response, leaving all alert text untouched.
                        Execute(server, ScriptText(sourceAlert.Script(new ScriptingOptions { AgentJobId = false })));
                        Emit(status, "Successful");
                    }
                    catch (PipelineStoppedException) { throw; }
                    catch (Exception ex)
                    {
                        Emit(status, "Failed");
                        WriteMessage(MessageLevel.Verbose, string.Format("Issue creating alert {0} on {1} | {2}", name, destination, ex.Message));
                    }
                }

                Uncaught(() => { server.JobServer.Alerts.Refresh(); return true; }, "Refresh");
                Uncaught(() => { server.JobServer.Jobs.Refresh(); return true; }, "Refresh");
                SmoAlert? newAlert = server.JobServer.Alerts[name];
                DataTable? alertNotifications = Uncaught(() => sourceAlert.EnumNotifications(), "EnumNotifications");
                string jobName = sourceAlert.JobName;

                if (sourceAlert.JobID != Guid.Empty)
                {
                    PSObject association = Status(server, name, "Agent Alert Job Association");
                    association.Properties["Notes"].Value = "Associated with " + jobName;
                    if (Confirm(destination, string.Format("Adding {0} to {1}", name, jobName)))
                    {
                        try
                        {
                            WriteMessage(MessageLevel.Verbose, string.Format("Adding {0} to {1}", name, jobName));
                            Job newJob = server.JobServer.Jobs[jobName];
                            newAlert!.JobID = newJob.JobID;
                            WriteMessage(MessageLevel.Debug, string.Format("EXEC msdb.dbo.sp_update_alert @name=N'{0}', @job_id=N'{1}'", name.Replace("'", "''"), newJob.JobID));
                            newAlert.Alter();
                            Emit(association, "Successful", "Associated with " + jobName);
                        }
                        catch (PipelineStoppedException) { throw; }
                        catch (Exception ex)
                        {
                            Emit(association, "Failed", "Associated with " + jobName);
                            WriteMessage(MessageLevel.Verbose, string.Format("Issue adding alert to job to {0} | {1}", destination, ex.Message));
                            continue;
                        }
                    }
                }

                if (Confirm(destination, "Moving Notifications " + name))
                {
                    PSObject notificationStatus = Status(server, name, "Agent Alert Notification");
                    if (alertNotifications is null)
                    {
                        // A failed read did not copy notifications; preserve the pin's Failed row shape and null Notes.
                        Emit(notificationStatus, "Failed");
                        continue;
                    }
                    try
                    {
                        foreach (DataRow notification in alertNotifications.Rows)
                        {
                            NotifyMethods methods = NotifyMethods.None;
                            if (LanguagePrimitives.IsTrue(notification["UseNetSend"]))
                            {
                                WriteMessage(MessageLevel.Verbose, "Adding net send");
                                methods |= NotifyMethods.NetSend;
                            }
                            if (LanguagePrimitives.IsTrue(notification["UseEmail"]))
                            {
                                WriteMessage(MessageLevel.Verbose, "Adding email");
                                methods |= NotifyMethods.NotifyEmail;
                            }
                            if (LanguagePrimitives.IsTrue(notification["UsePager"]))
                            {
                                WriteMessage(MessageLevel.Verbose, "Adding pager");
                                methods |= NotifyMethods.Pager;
                            }
                            newAlert!.AddNotification(Convert.ToString(notification["OperatorName"], CultureInfo.CurrentCulture) ?? "", methods);
                        }
                        Emit(notificationStatus, "Successful");
                    }
                    catch (PipelineStoppedException) { throw; }
                    catch (Exception ex)
                    {
                        Emit(notificationStatus, "Failed");
                        WriteMessage(MessageLevel.Verbose, string.Format("Issue moving notifications to {0} for the alert {1} | {2}", destination, name, ex.Message));
                    }
                }
            }
        }
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
            StopFunction("Failure", target: instance, errorRecord: new ErrorRecord(ex, "dbatools_Copy-DbaAgentAlert", ErrorCategory.ConnectionError, instance),
                category: ErrorCategory.ConnectionError, continueLoop: continueLoop);
            return null;
        }
    }

    private bool Confirm(DbaInstanceParameter instance, string action)
    {
        return Force ? AgentConfirmation.WithConfirmationSuppressed(SessionState, () => ShouldProcess(instance.ToString(), action))
            : ShouldProcess(instance.ToString(), action);
    }

    private void Execute(Server server, string sql)
    {
        WriteMessage(MessageLevel.Debug, sql);
        server.ConnectionContext.ExecuteNonQuery(sql);
    }

    private T Uncaught<T>(Func<T> call, string method)
    {
        try { return call(); }
        catch (PipelineStoppedException) { throw; }
        catch (Exception ex)
        {
            MethodInvocationException wrapped = new MethodInvocationException(
                string.Format("Exception calling \"{0}\" with \"0\" argument(s): \"{1}\"", method, ex.Message), ex);
            ErrorRecord record = new ErrorRecord(wrapped, ex.GetType().Name, ErrorCategory.NotSpecified, null);
            if (EnableException)
                // caller-try: terminate -- EnableException explicitly requests the statement fault to stop.
                ThrowTerminatingError(record); // style-ok: cs-raw-streams source method faults are outside Stop-Function
            StatementFault.Surface(this, record);
            return default!;
        }
    }

    private static string ScriptText(StringCollection script)
    {
        List<string> lines = new List<string>();
        foreach (string? line in script) lines.Add(line ?? "");
        return string.Join(Environment.NewLine, lines) + Environment.NewLine;
    }

    private static bool Contains(object[] values, string name)
    {
        foreach (object value in values) if (LanguagePrimitives.Equals(value, name, true)) return true;
        return false;
    }

    private static SmoAlert? FindAlert(AlertCollection alerts, string name)
    {
        foreach (SmoAlert alert in alerts) if (LanguagePrimitives.Equals(alert.Name, name, true)) return alert;
        return null;
    }

    private static Job? FindJob(JobCollection jobs, string name)
    {
        foreach (Job job in jobs) if (LanguagePrimitives.Equals(job.Name, name, true)) return job;
        return null;
    }

    private PSObject Status(Server destination, string name, string type)
    {
        PSObject result = new PSObject();
        result.Properties.Add(new PSNoteProperty("SourceServer", _source!.Name));
        result.Properties.Add(new PSNoteProperty("DestinationServer", destination.Name));
        result.Properties.Add(new PSNoteProperty("Name", name));
        result.Properties.Add(new PSNoteProperty("Type", type));
        result.Properties.Add(new PSNoteProperty("Notes", null));
        result.Properties.Add(new PSNoteProperty("Status", null));
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
