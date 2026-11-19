#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Management.Automation;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Microsoft.SqlServer.Management.Common;
using Microsoft.SqlServer.Management.Smo;
using SmoDatabase = Microsoft.SqlServer.Management.Smo.Database;

namespace Dataplat.Dbatools.Commands;

public sealed partial class InvokeDbaQueryCommand
{
    protected override void ProcessRecord()
    {
        // PS: if (Test-FunctionInterrupt) { return }
        if (Interrupted)
            return;

        if (TestBoundAll("Database", "InputObject"))
        {
            StopFunction("You can't use -Database with piped databases", category: ErrorCategory.InvalidArgument);
            return;
        }
        if (TestBoundAll("SqlInstance", "InputObject"))
        {
            StopFunction("You can't use -SqlInstance with piped databases", category: ErrorCategory.InvalidArgument);
            return;
        }
        // PS: Test-Bound -Not multi-name = NONE of them bound
        if (!TestBound("SqlInstance", "InputObject"))
        {
            StopFunction("Please provide either SqlInstance or InputObject", category: ErrorCategory.InvalidArgument);
            return;
        }

        if (InputObject is not null)
        {
            foreach (SmoDatabase db in InputObject)
            {
                if (!LanguagePrimitives.IsTrue(SmoServerExtensionsGetProperty(db, "IsAccessible")))
                {
                    WriteMessage(MessageLevel.Warning, "Database " + PsText(db) + " is not accessible. Skipping.");
                    continue;
                }
                Server server = db.Parent;
                ServerConnection conncontext = server.ConnectionContext;
                if (!PsString.Eq(conncontext.DatabaseName, db.Name))
                {
                    // Save StatementTimeout because it might be reset on GetDatabaseConnection
                    int savedStatementTimeout = conncontext.StatementTimeout;
                    conncontext = conncontext.Copy().GetDatabaseConnection(db.Name);
                    conncontext.StatementTimeout = savedStatementTimeout;
                }
                try
                {
                    if (LanguagePrimitives.IsTrue(File) || LanguagePrimitives.IsTrue(SqlObject))
                    {
                        foreach (string? item in _files)
                        {
                            if (item is null)
                                continue;
                            string filePath = GetLiteralProviderPath(item);
                            string queryFromFile = System.IO.File.ReadAllText(filePath);
                            RunAsync(conncontext, queryFromFile);
                        }
                    }
                    else
                    {
                        RunAsync(conncontext, null);
                    }
                }
                catch (PipelineStoppedException)
                {
                    throw;
                }
                catch (Exception ex)
                {
                    StopFunction("[" + PsText(db) + "] Failed during execution", target: server, errorRecord: RecordFrom(ex), continueLoop: true);
                    continue;
                }
            }
        }

        if (SqlInstance is null)
            return;
        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            // Verbose output in Invoke-DbaQuery is special, because it's the only way to assure on all versions of Powershell to have separate outputs (results and messages) coming from the TSQL Query.
            // We suppress the verbosity of all other functions in order to be sure the output is consistent with what you get, e.g., executing the same in SSMS
            WriteMessage(MessageLevel.Debug, "SqlInstance passed in, will work on: " + PsText(instance));
            object? server;
            bool startedWithAnOpenConnection;
            try
            {
                object? inputObject = instance.InputObject;
                if (inputObject is PSObject wrapped)
                    inputObject = wrapped.BaseObject;
                Server? smoInput = inputObject as Server;
                // we want to bypass Connect-DbaInstance if we have a Server SMO object and no
                // readonly intent is requested and the database is not set or the currently
                // connected and we don't use AppendConnectionString and we don't use a
                // DIFFERENT operating system user than the current logged in
                startedWithAnOpenConnection =
                    PsString.Eq(inputObject?.GetType().Name, "Server") &&
                    !ReadOnly.IsPresent &&
                    (!LanguagePrimitives.IsTrue(Database) || PsString.Eq(smoInput?.ConnectionContext.DatabaseName, Database)) &&
                    !LanguagePrimitives.IsTrue(AppendConnectionString) &&
                    PsString.Eq(smoInput?.ConnectionContext.ConnectAsUserName, "");
                if (startedWithAnOpenConnection)
                {
                    WriteMessage(MessageLevel.Debug, "Current connection will be reused");
                    server = inputObject;
                }
                else
                {
                    Hashtable connectParams = new();
                    connectParams["SqlInstance"] = instance;
                    connectParams["SqlCredential"] = SqlCredential;
                    connectParams["Database"] = Database;
                    connectParams["NonPooledConnection"] = true; // see #8491 for details, also #7725 is still relevant
                    connectParams["Verbose"] = false;
                    if (ReadOnly.IsPresent)
                        connectParams["ApplicationIntent"] = "ReadOnly";
                    if (LanguagePrimitives.IsTrue(AppendConnectionString))
                    {
                        connectParams["AppendConnectionString"] = AppendConnectionString;
                        connectParams["SqlInstance"] = PsText(instance); // pass down "as a string" so it's forced to open a new one
                    }
                    _connectParamsCreated = true;
                    Collection<PSObject> connected = InvokeNestedPreservingWarnings("Connect-DbaInstance", connectParams, null, out ErrorRecord? connectFailure);
                    if (connectFailure is not null)
                    {
                        StopFunction("Failure", target: instance, errorRecord: connectFailure, continueLoop: true);
                        continue;
                    }
                    // PS: $server takes whatever the nested call emitted - null when it
                    // emitted nothing; property access below stays null-tolerant (codex r1 F1).
                    object? serverValue = connected.Count > 0 ? connected[0] : null;
                    if (serverValue is PSObject wrappedServer)
                        serverValue = wrappedServer.BaseObject;
                    server = serverValue;
                }
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch (Exception ex)
            {
                StopFunction("Failure", target: instance, errorRecord: RecordFrom(ex), continueLoop: true);
                continue;
            }
            // PS: $conncontext = $server.ConnectionContext - a null/foreign $server reads
            // null, and the null lands on Invoke-DbaAsync's ValidateNotNullOrEmpty binder
            // inside the try (the "[instance] Failed during execution" path), not before it.
            object? conncontextValue = server is null ? null : PsProperty.Get(server, "ConnectionContext");
            if (conncontextValue is PSObject wrappedContext)
                conncontextValue = wrappedContext.BaseObject;
            ServerConnection? conncontext = conncontextValue as ServerConnection;
            bool continueInstance = false;
            try
            {
                if (conncontext is null)
                    throw new RuntimeException("Cannot validate argument on parameter 'SqlConnection'. The argument is null or empty. Provide an argument that is not null or empty, and then try the command again.");
                if (LanguagePrimitives.IsTrue(File) || LanguagePrimitives.IsTrue(SqlObject))
                {
                    foreach (string? item in _files)
                    {
                        if (item is null)
                            continue;
                        string filePath = GetLiteralProviderPath(item);
                        string queryFromFile = System.IO.File.ReadAllText(filePath);
                        RunAsync(conncontext, queryFromFile);
                    }
                }
                else
                {
                    RunAsync(conncontext, null);
                }
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch (Exception ex)
            {
                StopFunction("[" + PsText(instance) + "] Failed during execution", target: instance, errorRecord: RecordFrom(ex), continueLoop: true);
                continueInstance = true;
            }
            // PS: Stop-Function -Continue in the catch above jumps PAST the disconnect.
            if (continueInstance)
                continue;
            // if the given connection started out open, don't close it.
            // PS reads $connDbaInstanceParams.NonPooledConnection, which persists across
            // instance iterations once any Connect path ran.
            if (_connectParamsCreated && !startedWithAnOpenConnection)
            {
                // Close non-pooled connection as this is not done automatically. If it is a reused Server SMO, connection will be opened again automatically on next request.
                Hashtable disconnectParams = new();
                disconnectParams["Verbose"] = false;
                // This closes the non-pooled connection THIS command opened for itself - the port's
                // own resource, not the caller's. The retired function's nested call resolved
                // $WhatIfPreference and $ConfirmPreference in module scope and so never saw a
                // caller-local dry run; a cmdlet's hop does, and a suppressed disconnect leaks a
                // real server session that nothing else closes.
                disconnectParams["WhatIf"] = new SwitchParameter(false);
                disconnectParams["Confirm"] = new SwitchParameter(false);
                NestedCommand.Invoke(this, "Disconnect-DbaInstance", disconnectParams, server);
            }
        }
    }

    /// <summary>PS property read over an SMO object honoring ETS decorations.</summary>
    private static object? SmoServerExtensionsGetProperty(object smoObject, string name)
    {
        return Connection.SmoServerExtensions.GetPSProperty(smoObject, name);
    }
}
