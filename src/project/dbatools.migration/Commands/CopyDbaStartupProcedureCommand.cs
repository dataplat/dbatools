#nullable enable

using System;
using System.Collections.Generic;
using System.Data;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

/// <summary>Copies startup procedures from master database between SQL Server instances</summary>
[Cmdlet(VerbsCommon.Copy, "DbaStartupProcedure", DefaultParameterSetName = "Default",
    SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
public sealed class CopyDbaStartupProcedureCommand : DbaBaseCmdlet
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

    /// <summary>Only copy the startup procedures with these names.</summary>
    [Parameter(Position = 4)]
    public string[]? Procedure { get; set; }

    /// <summary>Skip the startup procedures with these names.</summary>
    [Parameter(Position = 5)]
    public string[]? ExcludeProcedure { get; set; }

    /// <summary>Drop and recreate procedures that already exist on the destination.</summary>
    [Parameter]
    public SwitchParameter Force { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // Get-DbaModule -SqlInstance $server -Type StoredProcedure -Database master: its query, run in master. The pinned
    // -ModifiedSince default (1900-01-01) keeps every module.
    private const string ModuleQuery = @"SELECT  DB_NAME() AS DatabaseName,
        so.name AS ModuleName,
        SCHEMA_NAME(so.schema_id) AS SchemaName,
        so.modify_date,
        OBJECTPROPERTY(so.object_id, 'ExecIsStartUp') AS startup
        FROM sys.sql_modules sm
        LEFT JOIN sys.objects so ON sm.object_id = so.object_id
        WHERE so.modify_date >= '19000101' AND type_desc IN ('SQL_STORED_PROCEDURE')
        ORDER BY so.modify_date";

    // Upstream correction quoted-names (injection): the pinned statements placed the server-supplied schema and procedure names into
    // [...] and '...' unescaped, so a name holding ] or ' broke the statement or ran as SQL. Both statements now name
    // the procedure as [schema].[name] with ] doubled (startup procedures live in dbo of master, Microsoft Learn,
    // sp_procoption), and the sp_procoption literal doubles each '.
    private const string DropStatement = "DROP PROCEDURE {0}";
    private const string StartupStatement = "EXEC sp_procoption N'{0}', 'STARTUP', 'ON'";

    private Server? _source;
    private readonly List<DataRow> _startupProcs = new();

    protected override void BeginProcessing()
    {
        _source = Connect(Source, SourceSqlCredential, false);
        if (_source is null)
            return;

        // | Where-Object ExecIsStartup
        foreach (DataRow row in Modules(_source))
        {
            if (LanguagePrimitives.IsTrue(row["startup"]))
                _startupProcs.Add(row);
        }
    }

    protected override void ProcessRecord()
    {
        if (Interrupted || _source is null)
            return;

        foreach (DbaInstanceParameter destInstance in Destination)
        {
            CancellationToken.ThrowIfCancellationRequested();
            Server? destServer = Connect(destInstance, DestinationSqlCredential, true);
            if (destServer is null)
                continue;

            List<DataRow> destStartupProcs = Modules(destServer);

            foreach (DataRow currentProc in _startupProcs)
            {
                CancellationToken.ThrowIfCancellationRequested();
                CopyProcedure(currentProc, destInstance, destServer, destStartupProcs);
            }
        }
    }

    private void CopyProcedure(DataRow currentProc, DbaInstanceParameter destInstance, Server destServer, List<DataRow> destStartupProcs)
    {
        string currentProcName = Text(currentProc["ModuleName"]) ?? "";
        string currentProcSchema = Text(currentProc["SchemaName"]) ?? "";
        string currentProcFullName = currentProcSchema + "." + currentProcName;
        PSObject copyStartupProcStatus = Status(destServer, currentProcName, currentProcSchema);

        if (LanguagePrimitives.IsTrue(Procedure) && !Contains(Procedure!, currentProcName))
            return;
        if (LanguagePrimitives.IsTrue(ExcludeProcedure) && Contains(ExcludeProcedure!, currentProcName))
            return;

        bool exists = false;
        foreach (DataRow destProc in destStartupProcs)
        {
            if (LanguagePrimitives.Equals(destProc["ModuleName"], currentProcName, true, CultureInfo.InvariantCulture))
            {
                exists = true;
                break;
            }
        }

        if (exists)
        {
            if (!Force)
            {
                string action = String.Format(CultureInfo.InvariantCulture,
                    "Startup procedure {0} exists at destination. Use -Force to drop and migrate.", currentProcFullName);
                if (Confirm(destInstance, action))
                {
                    Emit(copyStartupProcStatus, "Skipped", "Already exists on destination");
                    WriteMessage(MessageLevel.Verbose, action);
                }
                return;
            }
            if (Confirm(destInstance, String.Format(CultureInfo.InvariantCulture, "Dropping startup procedure {0} and recreating", currentProcFullName)))
            {
                try
                {
                    WriteMessage(MessageLevel.Verbose, "Dropping startup procedure " + currentProcFullName);
                    Query(destServer, String.Format(CultureInfo.InvariantCulture, DropStatement, QuotedName(currentProcSchema, currentProcName)));
                }
                catch (Exception failure) when (failure is not PipelineStoppedException)
                {
                    string notes = MessageService.GetErrorMessage(Record(failure));
                    Emit(copyStartupProcStatus, "Failed", notes);
                    WriteMessage(MessageLevel.Verbose, String.Format(CultureInfo.InvariantCulture,
                        "Issue dropping startup procedure {0} on {1} | {2}", currentProcFullName, destInstance, Record(failure)));
                    return;
                }
            }
        }

        if (!Confirm(destInstance, "Creating startup procedure " + currentProcFullName))
            return;

        try
        {
            WriteMessage(MessageLevel.Verbose, "Copying startup procedure " + currentProcFullName);
            StoredProcedure sp = _source!.Databases["master"].StoredProcedures[currentProcName, currentProcSchema];
            string sql = sp.TextHeader + sp.TextBody;
            WriteMessage(MessageLevel.Verbose, sql);
            destServer.Databases["master"].ExecuteNonQuery(sql);
            string startupSql = String.Format(CultureInfo.InvariantCulture, StartupStatement, QuotedName(currentProcSchema, currentProcName).Replace("'", "''"));
            WriteMessage(MessageLevel.Verbose, startupSql);
            destServer.Databases["master"].ExecuteNonQuery(startupSql);

            Emit(copyStartupProcStatus, "Successful", null);
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            Emit(copyStartupProcStatus, "Failed", MessageService.GetErrorMessage(Record(failure)));
            WriteMessage(MessageLevel.Verbose, String.Format(CultureInfo.InvariantCulture,
                "Issue creating startup procedure {0} on {1} | {2}", currentProcFullName, destInstance, Record(failure)));
        }
    }

    // PS: Connect-DbaInstance -SqlInstance $instance -SqlCredential $credential -MinimumVersion 9 in a try whose catch runs
    // Stop-Function -Message "Failure" -Category ConnectionError (-Continue for a destination).
    // Upstream correction azure-unsupported: startup procedures exist only in SQL Server, so both connects refuse Azure
    // SQL Database as Connect-DbaInstance -AzureUnsupported does.
    private Server? Connect(DbaInstanceParameter instance, PSCredential? credential, bool continueLoop)
    {
        WriteAttributedMessage("Connect-DbaInstance", MessageLevel.Debug, "Starting process block");
        try
        {
            Server server = ConnectionService.GetServer(new SmoConnectionRequest
            {
                Instance = instance,
                SqlCredential = credential,
                MinimumVersion = 9,
                AzureUnsupported = true,
                BoundParameters = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "SqlInstance", "SqlCredential" },
                MessageCallback = (level, message) => WriteAttributedMessage("Connect-DbaInstance", level, message)
            });
            SetActiveConnection(server.ConnectionContext);
            WriteAttributedMessage("Connect-DbaInstance", MessageLevel.Debug, "We are finished with this instance");
            return server;
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            StopFunction("Failure", target: instance,
                errorRecord: new ErrorRecord(failure, "dbatools_Copy-DbaStartupProcedure", ErrorCategory.ConnectionError, instance),
                category: ErrorCategory.ConnectionError, continueLoop: continueLoop);
            return null;
        }
    }

    // The stored procedures of master, as Get-DbaModule returns them. Get-DbaModule runs its query through the dbatools
    // Server.Query script method with a database, $server.Query($sql, $db.name), whose catch rethrows the concatenated
    // messages of the failure's exception chain; outside any try in Get-DbaModule, that is a statement fault.
    private List<DataRow> Modules(Server server)
    {
        List<DataRow> rows = new();
        DataSet result;
        try
        {
            result = server.Databases["master"].ExecuteWithResults(ModuleQuery);
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            // caller-try: terminate -- continuing would copy no startup procedure (source) or misread which ones the destination has, and still report success
            ThrowTerminatingError(new ServerQueryException(failure, 2).Record()); // style-ok: cs-raw-streams statement fault of the nested Get-DbaModule call, outside Stop-Function
            return rows;
        }
        if (result.Tables.Count > 0)
        {
            foreach (DataRow row in result.Tables[0].Rows)
                rows.Add(row);
        }
        return rows;
    }

    // -Force sets $ConfirmPreference to 'none' for the whole function in the pinned begin block.
    private bool Confirm(DbaInstanceParameter instance, string action)
    {
        if (!Force)
            return ShouldProcess(instance.ToString(), action);
        object? previousPreference = SessionState.PSVariable.GetValue("ConfirmPreference");
        try
        {
            SessionState.PSVariable.Set("ConfirmPreference", ConfirmImpact.None);
            return ShouldProcess(instance.ToString(), action);
        }
        finally
        {
            SessionState.PSVariable.Set("ConfirmPreference", previousPreference);
        }
    }

    // $server.Query($sql) on the connection's current database.
    private static void Query(Server server, string sql)
    {
        try
        {
            server.ConnectionContext.ExecuteWithResults(sql);
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            throw new ServerQueryException(failure);
        }
    }

    private static ErrorRecord Record(Exception failure)
    {
        if (failure is ServerQueryException query)
            return query.Record();
        if (failure is IContainsErrorRecord contained)
            return contained.ErrorRecord;
        return new ErrorRecord(failure, failure.GetType().Name, ErrorCategory.NotSpecified, null);
    }

    // [schema].[name], each part with ] doubled as QUOTENAME does.
    private static string QuotedName(string schema, string name)
    {
        return "[" + schema.Replace("]", "]]") + "].[" + name.Replace("]", "]]") + "]";
    }

    private static string? Text(object value)
    {
        if (value is null || value is DBNull)
            return null;
        return Convert.ToString(value, CultureInfo.InvariantCulture);
    }

    private static bool Contains(string[] values, string name)
    {
        foreach (string value in values)
        {
            if (LanguagePrimitives.Equals(value, name, true, CultureInfo.InvariantCulture))
                return true;
        }
        return false;
    }

    private PSObject Status(Server destServer, string name, string schema)
    {
        PSObject result = new();
        result.Properties.Add(new PSNoteProperty("SourceServer", _source!.Name));
        result.Properties.Add(new PSNoteProperty("DestinationServer", destServer.Name));
        result.Properties.Add(new PSNoteProperty("Name", name));
        result.Properties.Add(new PSNoteProperty("Schema", schema));
        result.Properties.Add(new PSNoteProperty("Status", null));
        result.Properties.Add(new PSNoteProperty("Notes", null));
        result.Properties.Add(new PSNoteProperty("Type", "Startup Stored Procedure"));
        result.Properties.Add(new PSNoteProperty("DateTime", new DbaDateTime(DateTime.Now)));
        return result;
    }

    // Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
    private void Emit(PSObject result, string status, string? notes)
    {
        result.Properties["Status"].Value = status;
        result.Properties["Notes"].Value = notes;
        OutputHelper.SetDefaultDisplayPropertySet(result, "DateTime", "SourceServer", "DestinationServer", "Name", "Type", "Status", "Notes");
        OutputHelper.InsertTypeName(result, "MigrationObject");
        WriteObject(result);
    }

    // The fault the pinned catch receives from $server.Query: the script method joins the messages of the failure
    // chain and throws that text, which the engine reports as a method fault of "Query" called with one argument.
    private sealed class ServerQueryException : Exception
    {
        private readonly string _text;
        private readonly int _arguments;

        // arguments: 1 for $server.Query($sql), 2 for $server.Query($sql, $database).
        public ServerQueryException(Exception failure, int arguments = 1)
            : base(Describe(Join(failure), arguments), failure)
        {
            _text = Join(failure);
            _arguments = arguments;
        }

        public ErrorRecord Record()
        {
            MethodInvocationException fault = new(Describe(_text, _arguments), new RuntimeException(_text));
            return new ErrorRecord(fault, "ScriptMethodRuntimeException", ErrorCategory.NotSpecified, null);
        }

        private static string Describe(string text, int arguments)
        {
            return String.Format(CultureInfo.InvariantCulture, "Exception calling \"Query\" with \"{0}\" argument(s): \"{1}\"", arguments, text);
        }

        private static string Join(Exception failure)
        {
            string message = "";
            Exception current = failure;
            while (current.InnerException is not null)
            {
                message += current.Message;
                current = current.InnerException;
            }
            return message + current.Message;
        }
    }
}
