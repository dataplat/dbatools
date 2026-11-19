#nullable enable

using System;
using System.Collections.Generic;
using System.Collections.Specialized;
using System.Management.Automation;
using System.Text;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

// Copies server-level triggers between instances through SMO (port of public/Copy-DbaInstanceTrigger.ps1).
/// <summary>Copies server-level triggers between SQL Server instances for migration or standardization</summary>
[Cmdlet(VerbsCommon.Copy, "DbaInstanceTrigger", DefaultParameterSetName = "Default",
    SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
public sealed class CopyDbaInstanceTriggerCommand : DbaBaseCmdlet
{
    /// <summary>The source SQL Server instance. Requires sysadmin and SQL Server 2005 or higher.</summary>
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

    /// <summary>Only copy the server triggers with these names.</summary>
    [Parameter(Position = 4)]
    public object[]? ServerTrigger { get; set; }

    /// <summary>Skip the server triggers with these names.</summary>
    [Parameter(Position = 5)]
    public object[]? ExcludeServerTrigger { get; set; }

    /// <summary>Drop and recreate server triggers that already exist on the destination.</summary>
    [Parameter]
    public SwitchParameter Force { get; set; }

    private const string CommandName = "Copy-DbaInstanceTrigger";

    private Server? _sourceServer;
    private ServerDdlTriggerCollection? _serverTriggers;

    protected override void BeginProcessing()
    {
        // PS: try { Connect-DbaInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential -MinimumVersion 9 }
        //     catch { Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $Source; return }
        _sourceServer = Connect(Source, SourceSqlCredential, false);
        if (_sourceServer is null)
            return;
        _serverTriggers = _sourceServer.Triggers;
    }

    protected override void ProcessRecord()
    {
        // PS: if (Test-FunctionInterrupt) { return }
        if (Interrupted || _sourceServer is null || _serverTriggers is null)
            return;
        string eol = Environment.NewLine;

        foreach (DbaInstanceParameter destinstance in Destination)
        {
            CancellationToken.ThrowIfCancellationRequested();
            Server? destServer = Connect(destinstance, DestinationSqlCredential, true);
            if (destServer is null)
                continue;

            if (destServer.VersionMajor < _sourceServer.VersionMajor)
            {
                StopFunction(string.Format("Migration from version {0} to version {1} is not supported.",
                    destServer.VersionMajor, _sourceServer.VersionMajor));
                return;
            }
            ServerDdlTriggerCollection destTriggers = destServer.Triggers;

            foreach (ServerDdlTrigger trigger in _serverTriggers)
            {
                CancellationToken.ThrowIfCancellationRequested();
                string triggerName = trigger.Name;
                // PS: [DbaDateTime](Get-Date), taken when the status object is built, before the filters.
                DateTime timestamp = DateTime.Now;

                // PS: if ($ServerTrigger -and $triggerName -notin $ServerTrigger -or $triggerName -in $ExcludeServerTrigger) { continue }
                if ((LanguagePrimitives.IsTrue(ServerTrigger) && !ContainsValue(ServerTrigger, triggerName)) ||
                    ContainsValue(ExcludeServerTrigger, triggerName))
                    continue;

                if (DestinationHasTrigger(destTriggers, triggerName))
                {
                    if (!Force)
                    {
                        if (Approve(destinstance, string.Format("Server trigger {0} exists at destination. Use -Force to drop and migrate", triggerName)))
                        {
                            WriteMessage(MessageLevel.Verbose, string.Format("Server trigger {0} exists at destination. Use -Force to drop and migrate.", triggerName));
                            Emit(destServer, triggerName, timestamp, "Skipped", "Already exists on destination");
                        }
                        continue;
                    }
                    if (Approve(destinstance, string.Format("Dropping server trigger {0} and recreating", triggerName)))
                    {
                        try
                        {
                            WriteMessage(MessageLevel.Verbose, string.Format("Dropping server trigger {0}", triggerName));
                            ServerDdlTrigger? existing = destServer.Triggers[triggerName];
                            if (existing is null)
                                throw new RuntimeException("You cannot call a method on a null-valued expression.");
                            Call(() => existing.Drop(), "Drop", 0);
                        }
                        catch (PipelineStoppedException) { throw; }
                        catch (Exception ex)
                        {
                            Emit(destServer, triggerName, timestamp, "Failed", ErrorText(ex));
                            WriteMessage(MessageLevel.Verbose, string.Format("Issue dropping trigger {0} on {1} | {2}", triggerName, destinstance, ex.Message));
                            continue;
                        }
                    }
                }

                if (Approve(destinstance, string.Format("Creating server trigger {0}", triggerName)))
                {
                    try
                    {
                        WriteMessage(MessageLevel.Verbose, string.Format("Copying server trigger {0}", triggerName));
                        StringCollection script = Call(() => trigger.Script(), "Script", 0);
                        // Correction script-batches: SMO returns each batch of the definition as its own string
                        // (SET options, CREATE TRIGGER, ENABLE or DISABLE TRIGGER), so each runs as one batch. The
                        // pinned function joined them with Out-String and cut the text again before every
                        // "CREATE " and "ENABLE TRIGGER" anywhere in it (pinned :182-187).
                        StringBuilder text = new StringBuilder();
                        foreach (string? line in script)
                            text.Append(line).Append(eol);
                        WriteMessage(MessageLevel.Debug, text.ToString());
                        foreach (string? query in script)
                            Query(destServer, query ?? string.Empty);
                        Emit(destServer, triggerName, timestamp, "Successful", null);
                    }
                    catch (PipelineStoppedException) { throw; }
                    catch (Exception ex)
                    {
                        Emit(destServer, triggerName, timestamp, "Failed", ErrorText(ex));
                        WriteMessage(MessageLevel.Verbose, string.Format("Issue creating trigger {0} on {1} | {2}", triggerName, destinstance, ex.Message));
                    }
                }
            }
        }
    }

    private Server? Connect(DbaInstanceParameter instance, PSCredential? credential, bool continueLoop)
    {
        SmoConnectionRequest request = new SmoConnectionRequest
        {
            Instance = instance,
            SqlCredential = credential,
            // PS: Connect-DbaInstance -MinimumVersion 9 (:113, :128).
            MinimumVersion = 9,
            // Correction azure-unsupported: Azure SQL Database has no server-level triggers, so both ends refuse it
            // as Connect-DbaInstance -AzureUnsupported does.
            AzureUnsupported = true,
            BoundParameters = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "SqlInstance", "SqlCredential", "MinimumVersion", "AzureUnsupported" },
            MessageCallback = (level, message) => WriteAttributedMessage("Connect-DbaInstance", level, message)
        };
        WriteAttributedMessage("Connect-DbaInstance", MessageLevel.Debug, "Starting process block");
        try
        {
            Server server = ConnectionService.GetServer(request);
            SetActiveConnection(server.ConnectionContext);
            WriteAttributedMessage("Connect-DbaInstance", MessageLevel.Debug, "We are finished with this instance");
            return server;
        }
        catch (PipelineStoppedException) { throw; }
        catch (Exception ex)
        {
            ErrorRecord record = new ErrorRecord(ex, "dbatools_" + CommandName, ErrorCategory.ConnectionError, instance);
            StopFunction("Failure", target: instance, errorRecord: record, category: ErrorCategory.ConnectionError, continueLoop: continueLoop);
            return null;
        }
    }

    // PS: if ($Force) { $ConfirmPreference = 'none' } in begin, so -Force answers every ShouldProcess without a prompt.
    // The agent satellite's AgentConfirmation.WithConfirmationSuppressed is internal to that assembly.
    private bool Approve(DbaInstanceParameter target, string action)
    {
        if (!Force)
            return ShouldProcess(target.ToString(), action);
        object? previous = SessionState.PSVariable.GetValue("ConfirmPreference");
        try
        {
            SessionState.PSVariable.Set("ConfirmPreference", ConfirmImpact.None);
            return ShouldProcess(target.ToString(), action);
        }
        finally
        {
            SessionState.PSVariable.Set("ConfirmPreference", previous);
        }
    }

    // PS: $name -in $values over an [object[]] parameter: each value is the left operand of -eq.
    private static bool ContainsValue(object[]? values, string name)
    {
        foreach (object? value in values ?? Array.Empty<object>())
        {
            if (value is not null && LanguagePrimitives.Equals(value, name, true))
                return true;
        }
        return false;
    }

    // PS: $destTriggers.Name -contains $triggerName
    private static bool DestinationHasTrigger(ServerDdlTriggerCollection triggers, string name)
    {
        foreach (ServerDdlTrigger trigger in triggers)
        {
            if (LanguagePrimitives.Equals(trigger.Name, name, true))
                return true;
        }
        return false;
    }

    // A .NET method called from PowerShell fails as MethodInvocationException around the original exception.
    private static T Call<T>(Func<T> call, string method, int arguments)
    {
        try { return call(); }
        catch (PipelineStoppedException) { throw; }
        catch (RuntimeException) { throw; }
        catch (Exception ex)
        {
            throw new MethodInvocationException(string.Format("Exception calling \"{0}\" with \"{1}\" argument(s): \"{2}\"", method, arguments, ex.Message), ex);
        }
    }

    private static void Call(Action call, string method, int arguments)
    {
        Call<object?>(() => { call(); return null; }, method, arguments);
    }

    // PS: $destServer.Query($query) | Out-Null. The Server.Query script method (xml/dbatools.Types.ps1xml) runs
    // ConnectionContext.ExecuteWithResults and on failure throws the inner exception messages, concatenated; the
    // call site then sees it as a MethodInvocationException around that RuntimeException.
    private static void Query(Server server, string query)
    {
        try
        {
            server.ConnectionContext.ExecuteWithResults(query);
        }
        catch (PipelineStoppedException) { throw; }
        catch (Exception ex)
        {
            StringBuilder message = new StringBuilder();
            Exception inner = ex;
            while (inner.InnerException is not null)
            {
                message.Append(inner.Message);
                inner = inner.InnerException;
            }
            message.Append(inner.Message);
            // PS: throw '' halts with the message ScriptHalted.
            string text = message.Length == 0 ? "ScriptHalted" : message.ToString();
            RuntimeException thrown = new RuntimeException(text);
            throw new MethodInvocationException(string.Format("Exception calling \"Query\" with \"1\" argument(s): \"{0}\"", text), thrown);
        }
    }

    // PS: Get-ErrorMessage -Record $_
    private static string? ErrorText(Exception ex)
    {
        return MessageService.GetErrorMessage(new ErrorRecord(ex, "dbatools_" + CommandName, ErrorCategory.NotSpecified, null));
    }

    // PS: [PSCustomObject]@{ ... } | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
    private void Emit(Server destServer, string name, DateTime timestamp, string status, string? notes)
    {
        PSObject result = new PSObject();
        result.Properties.Add(new PSNoteProperty("SourceServer", _sourceServer!.Name));
        result.Properties.Add(new PSNoteProperty("DestinationServer", destServer.Name));
        result.Properties.Add(new PSNoteProperty("Name", name));
        result.Properties.Add(new PSNoteProperty("Type", "Server Trigger"));
        result.Properties.Add(new PSNoteProperty("Status", status));
        result.Properties.Add(new PSNoteProperty("Notes", notes));
        result.Properties.Add(new PSNoteProperty("DateTime", new DbaDateTime(timestamp)));
        OutputHelper.InsertTypeName(result, "MigrationObject");
        OutputHelper.SetDefaultDisplayPropertySet(result, "DateTime", "SourceServer", "DestinationServer", "Name", "Type", "Status", "Notes");
        WriteObject(result);
    }
}
