#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Collections.Specialized;
using System.Globalization;
using System.Management.Automation;
using System.Text;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;
using ISfcScript = Microsoft.SqlServer.Management.Sdk.Sfc.ISfcScript;
using SfcTSqlScript = Microsoft.SqlServer.Management.Sdk.Sfc.SfcTSqlScript;
using SqlStoreConnection = Microsoft.SqlServer.Management.Sdk.Sfc.SqlStoreConnection;
using XESession = Microsoft.SqlServer.Management.XEvent.Session;
using XEStore = Microsoft.SqlServer.Management.XEvent.XEStore;

namespace Dataplat.Dbatools.Commands;

// Port of public/Copy-DbaXESession.ps1: the source and destination stores are SMO XEStore objects over each
// connection, each session is scripted with ScriptCreate() and run on the destination, and a session running on the
// source is started on the destination.
/// <summary>Copies Extended Event sessions from one SQL Server instance to another, excluding system sessions.</summary>
[Cmdlet(VerbsCommon.Copy, "DbaXESession", DefaultParameterSetName = "Default", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
public sealed class CopyDbaXESessionCommand : DbaBaseCmdlet
{
    /// <summary>The source SQL Server instance.</summary>
    [Parameter(Mandatory = true, Position = 0)]
    public DbaInstanceParameter Source { get; set; } = null!;

    /// <summary>The destination SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, Position = 1)]
    [PsDbaInstanceArrayCast]
    public DbaInstanceParameter[] Destination { get; set; } = null!;

    /// <summary>Login to the source instance using alternative credentials.</summary>
    [Parameter(Position = 2)]
    public PSCredential? SourceSqlCredential { get; set; }

    /// <summary>Login to the destination instance(s) using alternative credentials.</summary>
    [Parameter(Position = 3)]
    public PSCredential? DestinationSqlCredential { get; set; }

    /// <summary>Only copy these named Extended Events sessions.</summary>
    [Parameter(Position = 4)]
    public object[]? XeSession { get; set; }

    /// <summary>Exclude these named Extended Events sessions from the copy.</summary>
    [Parameter(Position = 5)]
    public object[]? ExcludeXeSession { get; set; }

    /// <summary>Drop and recreate sessions that already exist on the destination.</summary>
    [Parameter]
    public SwitchParameter Force { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    private const string CommandName = "Copy-DbaXESession";

    // PS: Where-Object { $_.Name -notin 'AlwaysOn_health', 'system_health' }
    private static readonly string[] SystemSessions = { "AlwaysOn_health", "system_health" };

    private Server? _sourceServer;
    private readonly List<XESession> _storeSessions = new();

    protected override void BeginProcessing()
    {
        // PS: try { Connect-DbaInstance ... -MinimumVersion 11; SqlStoreConnection; XEStore }
        //     catch { Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $Source; return }
        XEStore? sourceStore;
        _sourceServer = Connect(Source, SourceSqlCredential, false, out sourceStore);
        if (_sourceServer is null || sourceStore is null)
            return;

        // PS: $storeSessions = $sourceStore.Sessions | Where-Object ... ; then the -In / -NotIn filters. SFC loads the
        // sessions from the server when the collection is enumerated, outside the pinned try.
        foreach (XESession session in SourceSessions(sourceStore))
        {
            string name = session.Name;
            if (ContainsValue(SystemSessions, name))
                continue;
            if (LanguagePrimitives.IsTrue(XeSession) && !ContainsValue(XeSession, name))
                continue;
            if (LanguagePrimitives.IsTrue(ExcludeXeSession) && ContainsValue(ExcludeXeSession, name))
                continue;
            _storeSessions.Add(session);
        }
    }

    // The source store's sessions, enumerated as the pinned pipeline does. A fault reading them is a statement fault of
    // the begin block; the engine's own record comes from LanguagePrimitives.GetEnumerator, which enumerates through the
    // same binder as the pipeline (ExceptionInGetEnumerator), or from a failing MoveNext ("BadEnumeration").
    private List<XESession> SourceSessions(XEStore sourceStore)
    {
        List<XESession> sessions = new();
        object collection;
        try
        {
            collection = sourceStore.Sessions;
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            // PowerShell's member binder reads a failing getter as $null, so the pin silently copied nothing; the port
            // reports the fault with the adapter's getter record instead.
            GetValueInvocationException fault = new(String.Format(CultureInfo.InvariantCulture,
                "Exception getting \"Sessions\": \"{0}\"", failure.Message), failure);
            // caller-try: terminate -- continuing would copy none of the source sessions to any destination and still report nothing wrong
            ThrowTerminatingError(new ErrorRecord(fault, "CatchFromBaseAdapterGetValue", ErrorCategory.NotSpecified, null)); // style-ok: cs-raw-streams source read fault outside Stop-Function, which the source loses to its member binder
            return sessions;
        }

        IEnumerator? enumerator = null;
        try
        {
            enumerator = LanguagePrimitives.GetEnumerator(collection);
            if (enumerator is null)
                return sessions;
            while (enumerator.MoveNext())
            {
                if (enumerator.Current is XESession session)
                    sessions.Add(session);
            }
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            ErrorRecord record;
            if (failure is IContainsErrorRecord container && container.ErrorRecord is not null)
                record = new ErrorRecord(container.ErrorRecord, failure);
            else
                record = new ErrorRecord(new RuntimeException(String.Format(CultureInfo.InvariantCulture,
                    "An error occurred while enumerating through a collection: {0}.", failure.Message), failure),
                    "BadEnumeration", ErrorCategory.InvalidOperation, enumerator);
            // caller-try: terminate -- continuing would copy none of the source sessions to any destination with only an error
            ThrowTerminatingError(record); // style-ok: cs-raw-streams pipeline enumeration fault of the begin block, outside Stop-Function
        }
        return sessions;
    }

    protected override void ProcessRecord()
    {
        // PS: if (Test-FunctionInterrupt) { return }
        if (Interrupted || _sourceServer is null)
            return;

        foreach (DbaInstanceParameter destinstance in Destination)
        {
            CancellationToken.ThrowIfCancellationRequested();
            XEStore? destStore;
            Server? destServer = Connect(destinstance, DestinationSqlCredential, true, out destStore);
            if (destServer is null || destStore is null)
                continue;

            WriteMessage(MessageLevel.Verbose, "Migrating sessions.");
            foreach (XESession session in _storeSessions)
            {
                CancellationToken.ThrowIfCancellationRequested();
                CopySession(session, destinstance, destServer, destStore);
            }
        }
    }

    private void CopySession(XESession session, DbaInstanceParameter destinstance, Server destServer, XEStore destStore)
    {
        string sessionName = session.Name;
        // PS: [DbaDateTime](Get-Date), taken when the status object is built.
        DateTime timestamp = DateTime.Now;

        if (destStore.Sessions[sessionName] is not null)
        {
            if (!Force)
            {
                if (Approve(destinstance, String.Format(CultureInfo.InvariantCulture, "Extended Event Session '{0}' was skipped because it already exists on {1}.", sessionName, destinstance)))
                {
                    Emit(destServer, sessionName, timestamp, "Skipped", "Already exists on destination");
                    WriteMessage(MessageLevel.Verbose, String.Format(CultureInfo.InvariantCulture, "Extended Event Session '{0}' was skipped because it already exists on {1}.", sessionName, destinstance));
                    WriteMessage(MessageLevel.Verbose, "Use -Force to drop and recreate.");
                }
                return;
            }
            if (Approve(destinstance, "Attempting to drop " + sessionName))
            {
                WriteMessage(MessageLevel.Verbose, String.Format(CultureInfo.InvariantCulture, "Extended Event Session '{0}' exists on {1}.", sessionName, destinstance));
                WriteMessage(MessageLevel.Verbose, String.Format(CultureInfo.InvariantCulture, "Force specified. Dropping {0}.", sessionName));
                try
                {
                    XESession existing = destStore.Sessions[sessionName] ?? throw new RuntimeException("You cannot call a method on a null-valued expression.");
                    Call(() => existing.Drop(), "Drop", 0);
                }
                catch (PipelineStoppedException) { throw; }
                catch (Exception ex)
                {
                    Emit(destServer, sessionName, timestamp, "Failed", ErrorText(ex));
                    WriteMessage(MessageLevel.Verbose, String.Format(CultureInfo.InvariantCulture, "Issue dropping Extended Event session {0} on {1} | {2}", sessionName, destinstance, ex.Message));
                    return;
                }
            }
        }

        if (!Approve(destinstance, "Migrating session " + sessionName))
            return;

        try
        {
            // PS: $sql = $session.ScriptCreate().GetScript() | Out-String
            StringCollection script = Call(() => Script(session), "GetScript", 0);
            StringBuilder text = new StringBuilder();
            foreach (string? line in script)
                text.Append(line).Append(Environment.NewLine);
            string sql = text.ToString();

            WriteMessage(MessageLevel.Debug, sql);
            WriteMessage(MessageLevel.Verbose, String.Format(CultureInfo.InvariantCulture, "Migrating session {0}.", sessionName));
            Query(destServer, sql);

            if (session.IsRunning)
            {
                Call(() => destStore.Sessions.Refresh(), "Refresh", 0);
                XESession created = destStore.Sessions[sessionName] ?? throw new RuntimeException("You cannot call a method on a null-valued expression.");
                Call(() => created.Start(), "Start", 0);
            }

            Emit(destServer, sessionName, timestamp, "Successful", null);
        }
        catch (PipelineStoppedException) { throw; }
        catch (Exception ex)
        {
            Emit(destServer, sessionName, timestamp, "Failed", ErrorText(ex));
            WriteMessage(MessageLevel.Verbose, String.Format(CultureInfo.InvariantCulture, "Issue creating Extended Event session {0} on {1} | {2}", sessionName, destinstance, ex.Message));
        }
    }

    // PS: Connect-DbaInstance -SqlInstance $instance -SqlCredential $credential -MinimumVersion 11, then
    // New-Object SqlStoreConnection $server.ConnectionContext.SqlConnectionObject and New-Object XEStore over it, all in
    // one try whose catch runs Stop-Function -Message "Failure" -Category ConnectionError (-Continue for a destination).
    private Server? Connect(DbaInstanceParameter instance, PSCredential? credential, bool continueLoop, out XEStore? store)
    {
        store = null;
        SmoConnectionRequest request = new SmoConnectionRequest
        {
            Instance = instance,
            SqlCredential = credential,
            MinimumVersion = 11,
            // Correction azure-unsupported: Azure SQL Database supports only database-scoped event sessions, never the
            // server-scoped ones this command copies, so both ends refuse it as Connect-DbaInstance -AzureUnsupported
            // does (as the pinned Get-DbaXESession already connects).
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
            SqlStoreConnection storeConnection = new SqlStoreConnection(server.ConnectionContext.SqlConnectionObject);
            store = new XEStore(storeConnection);
            return server;
        }
        catch (PipelineStoppedException) { throw; }
        catch (Exception ex)
        {
            store = null;
            ErrorRecord record = new ErrorRecord(ex, "dbatools_" + CommandName, ErrorCategory.ConnectionError, instance);
            StopFunction("Failure", target: instance, errorRecord: record, category: ErrorCategory.ConnectionError, continueLoop: continueLoop);
            return null;
        }
    }

    // $session.ScriptCreate().GetScript(): ScriptCreate returns an SfcTSqlScript, whose GetScript returns its batches.
    private static StringCollection Script(XESession session)
    {
        ISfcScript created = session.ScriptCreate();
        if (created is SfcTSqlScript tsql)
            return tsql.GetScript();
        throw new RuntimeException(String.Format(CultureInfo.InvariantCulture,
            "Method invocation failed because [{0}] does not contain a method named 'GetScript'.", created?.GetType().FullName));
    }

    // PS: if ($Force) { $ConfirmPreference = 'none' } in begin, so -Force answers every ShouldProcess without a prompt.
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

    // PS: $name -in $values (and -notin): each value is the left operand of a case-insensitive -eq.
    private static bool ContainsValue(object[]? values, string name)
    {
        foreach (object? value in values ?? Array.Empty<object>())
        {
            if (value is not null && LanguagePrimitives.Equals(value, name, true, CultureInfo.InvariantCulture))
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
            throw new MethodInvocationException(String.Format(CultureInfo.InvariantCulture, "Exception calling \"{0}\" with \"{1}\" argument(s): \"{2}\"", method, arguments, ex.Message), ex);
        }
    }

    private static void Call(Action call, string method, int arguments)
    {
        Call<object?>(() => { call(); return null; }, method, arguments);
    }

    // PS: $null = $destServer.Query($sql). The Server.Query script method (xml/dbatools.Types.ps1xml) runs
    // ConnectionContext.ExecuteWithResults and on failure throws the inner exception messages, concatenated; the call
    // site then sees it as a MethodInvocationException around that RuntimeException.
    private static void Query(Server server, string sql)
    {
        try
        {
            server.ConnectionContext.ExecuteWithResults(sql);
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
            throw new MethodInvocationException(String.Format(CultureInfo.InvariantCulture, "Exception calling \"Query\" with \"1\" argument(s): \"{0}\"", text), new RuntimeException(text));
        }
    }

    // PS: Get-ErrorMessage -Record $_
    private static string? ErrorText(Exception ex)
    {
        return MessageService.GetErrorMessage(new ErrorRecord(ex, "dbatools_" + CommandName, ErrorCategory.NotSpecified, null));
    }

    // PS: [PSCustomObject]@{ SourceServer; DestinationServer; Name; Type; Status; Notes; DateTime }
    //     | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
    private void Emit(Server destServer, string name, DateTime timestamp, string status, string? notes)
    {
        PSObject result = new PSObject();
        result.Properties.Add(new PSNoteProperty("SourceServer", _sourceServer!.Name));
        result.Properties.Add(new PSNoteProperty("DestinationServer", destServer.Name));
        result.Properties.Add(new PSNoteProperty("Name", name));
        result.Properties.Add(new PSNoteProperty("Type", "Extended Event"));
        result.Properties.Add(new PSNoteProperty("Status", status));
        result.Properties.Add(new PSNoteProperty("Notes", notes));
        result.Properties.Add(new PSNoteProperty("DateTime", new DbaDateTime(timestamp)));
        OutputHelper.InsertTypeName(result, "MigrationObject");
        OutputHelper.SetDefaultDisplayPropertySet(result, "DateTime", "SourceServer", "DestinationServer", "Name", "Type", "Status", "Notes");
        WriteObject(result);
    }
}
