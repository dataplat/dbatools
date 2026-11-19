#nullable enable

using System;
using System.Collections.Generic;
using System.Linq;
using System.Management.Automation;
using System.Text;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;
using SmoEndpoint = Microsoft.SqlServer.Management.Smo.Endpoint;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>Copies SQL Server endpoints from source instance to destination instances for migration scenarios.</summary>
[Cmdlet(VerbsCommon.Copy, "DbaEndpoint", DefaultParameterSetName = "Default",
    SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
public sealed class CopyDbaEndpointCommand : DbaBaseCmdlet
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

    /// <summary>Only copy the endpoints with these names.</summary>
    [Parameter(Position = 4)]
    public object[]? Endpoint { get; set; }

    /// <summary>Skip the endpoints with these names.</summary>
    [Parameter(Position = 5)]
    public object[]? ExcludeEndpoint { get; set; }

    /// <summary>Drop and recreate endpoints that already exist on the destination.</summary>
    [Parameter]
    public SwitchParameter Force { get; set; }

    private Server? _source;
    private readonly List<SmoEndpoint> _endpoints = new List<SmoEndpoint>();
    private WildcardNameMatcher _included = null!;
    private WildcardNameMatcher _excluded = null!;

    protected override void BeginProcessing()
    {
        _source = Connect(Source, SourceSqlCredential, false);
        if (_source is null) return;
        foreach (SmoEndpoint endpoint in _source.Endpoints)
            if (!endpoint.IsSystemObject) _endpoints.Add(endpoint);
        IEnumerable<string> scope = _endpoints.Select(endpoint => endpoint.Name);
        _included = WildcardNameFilter.CreateMatcher(Endpoint ?? Array.Empty<object>(), true,
            (value, name) => LanguagePrimitives.Equals(value, name, true), scope);
        _excluded = WildcardNameFilter.CreateMatcher(ExcludeEndpoint ?? Array.Empty<object>(), false,
            (value, name) => LanguagePrimitives.Equals(value, name, true), scope);
    }

    protected override void ProcessRecord()
    {
        if (Interrupted || _source is null) return;
        foreach (DbaInstanceParameter destination in Destination)
        {
            CancellationToken.ThrowIfCancellationRequested();
            Server? server = Connect(destination, DestinationSqlCredential, true);
            if (server is null) continue;
            foreach (SmoEndpoint endpoint in _endpoints)
            {
                CancellationToken.ThrowIfCancellationRequested();
                string name = endpoint.Name;
                DateTime timestamp = DateTime.Now;
                if ((LanguagePrimitives.IsTrue(Endpoint) && !_included.Matches(name)) || _excluded.Matches(name)) continue;
                SmoEndpoint? existing = server.Endpoints[name];
                if (existing is not null)
                {
                    if (!Force)
                    {
                        string action = string.Format("Server endpoint {0} exists at destination. Use -Force to drop and migrate.", name);
                        if (Approve(destination, action))
                        {
                            Emit(server, name, timestamp, "Skipped", "Already exists on destination");
                            WriteMessage(MessageLevel.Verbose, action);
                        }
                        continue;
                    }
                    if (Approve(destination, string.Format("Dropping server endpoint {0} and recreating.", name)))
                    {
                        try
                        {
                            WriteMessage(MessageLevel.Verbose, string.Format("Dropping server endpoint {0}.", name));
                            existing.Drop();
                        }
                        catch (PipelineStoppedException) { throw; }
                        catch (Exception ex)
                        {
                            Emit(server, name, timestamp, "Failed", MessageService.GetErrorMessage(
                                new ErrorRecord(ex, "CopyDbaEndpointDrop", ErrorCategory.NotSpecified, existing)));
                            WriteMessage(MessageLevel.Verbose, string.Format("Issue dropping server endpoint {0} on {1} | {2}", name, destination, ex.Message));
                            continue;
                        }
                    }
                }
                if (!Approve(destination, string.Format("Creating server endpoint {0}.", name))) continue;
                try
                {
                    WriteMessage(MessageLevel.Verbose, string.Format("Copying server endpoint {0}.", name));
                    StringBuilder script = new StringBuilder();
                    foreach (string? batch in endpoint.Script()) script.AppendLine(batch);
                    server.ConnectionContext.ExecuteNonQuery(script.ToString());
                    Emit(server, name, timestamp, "Successful", null);
                }
                catch (PipelineStoppedException) { throw; }
                catch (Exception ex)
                {
                    Emit(server, name, timestamp, "Failed", MessageService.GetErrorMessage(
                        new ErrorRecord(ex, "CopyDbaEndpointCreate", ErrorCategory.NotSpecified, endpoint)));
                    WriteMessage(MessageLevel.Verbose, string.Format("Issue creating server endpoint {0} on {1} | {2}", name, destination, ex.Message));
                }
            }
        }
    }

    private Server? Connect(DbaInstanceParameter target, PSCredential? credential, bool continueLoop)
    {
        SmoConnectionRequest request = new SmoConnectionRequest
        {
            Instance = target, SqlCredential = credential, MinimumVersion = 9, AzureUnsupported = true,
            BoundParameters = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "SqlInstance", "SqlCredential", "MinimumVersion", "AzureUnsupported" },
            MessageCallback = (level, text) => WriteAttributedMessage("Connect-DbaInstance", level, text)
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
            ErrorRecord record = new ErrorRecord(ex, "dbatools_Copy-DbaEndpoint", ErrorCategory.ConnectionError, target);
            StopFunction("Failure", errorRecord: record, target: target, category: ErrorCategory.ConnectionError, continueLoop: continueLoop);
            return null;
        }
    }

    private bool Approve(DbaInstanceParameter target, string action)
    {
        return Force ? WithConfirmationSuppressed(SessionState, () => ShouldProcess(target.ToString(), action))
            : ShouldProcess(target.ToString(), action);
    }

    private static bool WithConfirmationSuppressed(SessionState sessionState, Func<bool> shouldProcess)
    {
        object? previousPreference = sessionState.PSVariable.GetValue("ConfirmPreference");
        try
        {
            sessionState.PSVariable.Set("ConfirmPreference", ConfirmImpact.None);
            return shouldProcess();
        }
        finally
        {
            sessionState.PSVariable.Set("ConfirmPreference", previousPreference);
        }
    }

    private void Emit(Server destination, string name, DateTime timestamp, string status, string? notes)
    {
        PSObject result = new PSObject();
        string[] properties = { "SourceServer", "DestinationServer", "Name", "Type", "Status", "Notes", "DateTime" };
        object?[] values = { _source!.Name, destination.Name, name, "Endpoint", status, notes, new DbaDateTime(timestamp) };
        for (int i = 0; i < properties.Length; i++) result.Properties.Add(new PSNoteProperty(properties[i], values[i]));
        OutputHelper.InsertTypeName(result, "MigrationObject");
        OutputHelper.SetDefaultDisplayPropertySet(result, "DateTime", "SourceServer", "DestinationServer", "Name", "Type", "Status", "Notes");
        WriteObject(result);
    }
}
