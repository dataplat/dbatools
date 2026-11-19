#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Data;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;
// the sibling namespace Dataplat.Dbatools.Database shadows Smo.Database inside
// Dataplat.Dbatools.Commands (the W1-020 namespace trap) - alias the SMO type
using SmoDatabase = Microsoft.SqlServer.Management.Smo.Database;

namespace Dataplat.Dbatools.Commands;

// Port of public/Find-DbaDbGrowthEvent.ps1: the database list, the default trace query and the output rows run here in
// C#. The begin block's template assembly is kept exactly: the event-class whittling under the any-bound Test-Bound
// gate and the UseLocalTime fragment. The SQL fragments are byte-verbatim.
/// <summary>Retrieves database auto-growth and auto-shrink events from the SQL Server Default Trace</summary>
[Cmdlet(VerbsCommon.Find, "DbaDbGrowthEvent")]
public sealed class FindDbaDbGrowthEventCommand : DbaInstanceCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public override DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public override PSCredential? SqlCredential { get; set; }

    /// <summary>The database(s) to process.</summary>
    [Parameter(Position = 2)]
    public object[]? Database { get; set; }

    /// <summary>The database(s) to exclude.</summary>
    [Parameter(Position = 3)]
    public object[]? ExcludeDatabase { get; set; }

    /// <summary>Growth or Shrink.</summary>
    [Parameter(Position = 4)]
    [PsStringCast]
    [ValidateSet("Growth", "Shrink")]
    public string? EventType { get; set; }

    /// <summary>Data or Log.</summary>
    [Parameter(Position = 5)]
    [PsStringCast]
    [ValidateSet("Data", "Log")]
    public string? FileType { get; set; }

    /// <summary>Keeps trace times in server-local time instead of UTC.</summary>
    [Parameter]
    public SwitchParameter UseLocalTime { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    private string _sqlTemplate = "";

    protected override void BeginProcessing()
    {
        // PS: 92..95 ArrayList; ANY of EventType/FileType bound gates BOTH whittles.
        List<int> eventClass = new List<int> { 92, 93, 94, 95 };
        if (TestBound("EventType", "FileType"))
        {
            if (PsString.Eq(FileType, "Data"))
            {
                eventClass.Remove(93);
                eventClass.Remove(95);
            }
            else if (PsString.Eq(FileType, "Log"))
            {
                eventClass.Remove(92);
                eventClass.Remove(94);
            }
            if (PsString.Eq(EventType, "Growth"))
            {
                eventClass.Remove(94);
                eventClass.Remove(95);
            }
            else if (PsString.Eq(EventType, "Shrink"))
            {
                eventClass.Remove(92);
                eventClass.Remove(93);
            }
        }
        string eventClassFilter = string.Join(",", eventClass);

        string timeFragment = UseLocalTime.ToBool() ? LocalTimeFragment : UtcTimeFragment;
        _sqlTemplate = SqlTemplateHead + timeFragment + SqlTemplateTailA + eventClassFilter + SqlTemplateTailB;
    }

    private static readonly string[] Defaults =
    {
        "ComputerName", "InstanceName", "SqlInstance", "EventClass", "DatabaseName", "Filename", "Duration", "StartTime",
        "EndTime", "ChangeInSize", "ApplicationName", "HostName"
    };

    protected override void ProcessRecord()
    {
        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            // PS: try { Connect-DbaInstance } catch { Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue }
            // Correction azure-unsupported: the default trace does not exist in Azure SQL Database, so the connect
            // refuses it as Connect-DbaInstance -AzureUnsupported does.
            Server? server = ConnectInstance(instance, "Failure", azureUnsupported: true);
            if (server is null)
                continue;

            // PS: $dbsList = "'$($($dbs | ForEach-Object {$_.Name}) -join "','")'" - kept for the message.
            List<string> names = DatabaseNames(server);
            string dbsList = String.Format(CultureInfo.InvariantCulture, "'{0}'", String.Join("','", names));
            WriteMessage(MessageLevel.Verbose, "Executing query against " + dbsList + " on " + PsText(instance));

            // PS: $sqlTemplate -replace '_DatabaseList_', $dbsList
            // Corrections database-list-quotes and database-list-unicode: each name becomes an N'' literal with its quotes
            // doubled, and is inserted literally rather than as a regex replacement.
            string sql = _sqlTemplate.Replace("_DatabaseList_", NameLiterals(names));
            WriteMessage(MessageLevel.Debug, "Executing SQL Statement:\n " + sql);

            DataTable? events;
            try
            {
                events = ServerQuery(server, sql);
            }
            catch (QueryFault fault)
            {
                // PS: Stop-Function -Message "Issue collecting data on $server" -Target $server -ErrorRecord $_
                //     -Exception $_.Exception.InnerException.InnerException.InnerException -Continue. The thrown string's
                //     RuntimeException has no inner exception, so -Exception is $null.
                StopFunction("Issue collecting data on " + PsText(server), target: server, errorRecord: fault.Record, continueLoop: true);
                continue;
            }

            // PS: Select-DefaultView -InputObject $server.Query($sql) -Property $defaults - Add-Member on the piped
            // DataTable decorates each row, and the output enumerates the rows.
            if (events is null)
                continue;
            foreach (DataRow eventRow in events.Rows)
            {
                PSObject row = PSObject.AsPSObject(eventRow);
                OutputHelper.SetDefaultDisplayPropertySet(row, Defaults);
                WriteObject(row);
            }
        }
    }

    // PS: $dbs = $server.Databases, then | Where-Object Name -In $Database and | Where-Object Name -NotIn $ExcludeDatabase
    // when they are given; a failing enumeration outside the try is the statement's fault.
    private List<string> DatabaseNames(Server server)
    {
        List<string> names = new();
        bool included = PsOps.IsTrue(Database);
        bool excluded = PsOps.IsTrue(ExcludeDatabase);
        IEnumerator? enumerator = null;
        try
        {
            enumerator = LanguagePrimitives.GetEnumerator(server.Databases);
            while (enumerator is not null && enumerator.MoveNext())
            {
                SmoDatabase candidate = (SmoDatabase)enumerator.Current!;
                object? name = Read(() => candidate.Name);
                if (included && !PsOps.In(name, Database))
                    continue;
                if (excluded && PsOps.In(name, ExcludeDatabase))
                    continue;
                names.Add(candidate.Name);
            }
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            // caller-try: terminate -- continuing would reuse $dbs from the previous instance and query its names here
            ThrowTerminatingError(EnumerationFault(failure, enumerator)); // style-ok: cs-raw-streams pipeline statement fault outside Stop-Function, as in the source
        }
        return names;
    }

    // The IN list of the trace query: one N'' literal per name, quotes doubled; an empty list stays N''.
    private static string NameLiterals(List<string> names)
    {
        if (names.Count == 0)
            return "N''";
        List<string> literals = new();
        foreach (string name in names)
            literals.Add(String.Format(CultureInfo.InvariantCulture, "N'{0}'", name.Replace("'", "''")));
        return String.Join(",", literals);
    }

    // PS: $server.Query($sql), the dbatools Server.Query script method without a database: ExecuteWithResults on the
    // connection, first table. Its catch concatenates the exception chain's messages and throws that text.
    private static DataTable? ServerQuery(Server server, string sql)
    {
        try
        {
            DataSet results = server.ConnectionContext.ExecuteWithResults(sql);
            return results.Tables.Count > 0 ? results.Tables[0] : null;
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            string message = String.Empty;
            Exception current = failure;
            while (current.InnerException is not null)
            {
                message += current.Message;
                current = current.InnerException;
            }
            message += current.Message;
            MethodInvocationException call = new(String.Format(CultureInfo.InvariantCulture,
                "Exception calling \"Query\" with \"1\" argument(s): \"{0}\"", message), new RuntimeException(message));
            throw new QueryFault(new ErrorRecord(call, "ScriptMethodRuntimeException", ErrorCategory.NotSpecified, null));
        }
    }

    /// <summary>PS string interpolation of a value.</summary>
    private static string PsText(object? value)
    {
        if (value is null)
            return "";
        return PSObject.AsPSObject(value).ToString();
    }

    // A property read through the member binder: a failing getter is $null.
    private static object? Read(Func<object?> getter)
    {
        try
        {
            return getter();
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            // Reported nowhere, as the binder reports nothing.
            return null;
        }
    }

    // The engine's record when the failure carries one (ExceptionInGetEnumerator); otherwise the record a failing
    // MoveNext gives (BadEnumeration, InvalidOperation, the enumerator as target).
    private static ErrorRecord EnumerationFault(Exception failure, IEnumerator? enumerator)
    {
        if (failure is IContainsErrorRecord container && container.ErrorRecord is not null)
            return new ErrorRecord(container.ErrorRecord, failure);
        RuntimeException fault = new(String.Format(CultureInfo.InvariantCulture,
            "An error occurred while enumerating through a collection: {0}.", failure.Message), failure);
        return new ErrorRecord(fault, "BadEnumeration", ErrorCategory.InvalidOperation, enumerator);
    }

    // Carries the Query script method's fault to the catch that Stop-Function reports it from.
    private sealed class QueryFault : Exception
    {
        public QueryFault(ErrorRecord record)
            : base(record.Exception.Message, record.Exception)
        {
            Record = record;
        }

        public ErrorRecord Record { get; }
    }

    private const string SqlTemplateHead = @"
            BEGIN TRY
                IF (SELECT CONVERT(INT,[value_in_use]) FROM sys.configurations WHERE [name] = 'default trace enabled' ) = 1
                    BEGIN
                        DECLARE @curr_tracefilename VARCHAR(500);
                        DECLARE @base_tracefilename VARCHAR(500);
                        DECLARE @indx INT;

                        SELECT @curr_tracefilename = [path]
                        FROM sys.traces
                        WHERE is_default = 1 ;

                        SET @curr_tracefilename = REVERSE(@curr_tracefilename);
                        SELECT @indx  = PATINDEX('%\%', @curr_tracefilename);
                        SET @curr_tracefilename = REVERSE(@curr_tracefilename);
                        SET @base_tracefilename = LEFT( @curr_tracefilename,LEN(@curr_tracefilename) - @indx) + '\log.trc';

                        SELECT
                            SERVERPROPERTY('MachineName') AS ComputerName,
                            ISNULL(SERVERPROPERTY('InstanceName'), 'MSSQLSERVER') AS InstanceName,
                            SERVERPROPERTY('ServerName') AS SqlInstance,
                            CONVERT(INT,(DENSE_RANK() OVER (ORDER BY [StartTime] DESC))%2) AS OrderRank,
                                CONVERT(INT, [EventClass]) AS EventClass,
                            [DatabaseName],
                            (SELECT database_id FROM sys.databases WHERE Name = [DatabaseName]) AS DatabaseId,
                            [Filename],
                            CONVERT(INT,(Duration/1000)) AS Duration,
                            ";

    private const string UtcTimeFragment = @"
                            DATEADD (MINUTE, DATEDIFF(MINUTE, GETDATE(), GETUTCDATE()), [StartTime]) AS StartTime,  -- Convert to UTC time
                            DATEADD (MINUTE, DATEDIFF(MINUTE, GETDATE(), GETUTCDATE()), [EndTime]) AS EndTime,  -- Convert to UTC time";

    private const string LocalTimeFragment = @"
                            [StartTime] AS StartTime,
                            [EndTime] AS EndTime,";

    private const string SqlTemplateTailA = @"
                            ([IntegerData]*8.0/1024) AS ChangeInSize,
                            ApplicationName,
                            HostName,
                            SessionLoginName,
                            SPID
                        FROM ::fn_trace_gettable( @base_tracefilename, DEFAULT )
                        WHERE
                            [EventClass] IN (";

    private const string SqlTemplateTailB = @")
                            AND [DatabaseName] IN (_DatabaseList_)
                        ORDER BY [StartTime] DESC;
                    END
                ELSE
                    SELECT
                        SERVERPROPERTY('MachineName') AS ComputerName,
                        ISNULL(SERVERPROPERTY('InstanceName'), 'MSSQLSERVER') AS InstanceName,
                        SERVERPROPERTY('ServerName') AS SqlInstance,
                        -100 AS [OrderRank],
                        -1 AS [OrderRank],
                        0 AS [EventClass],
                        0 [DatabaseName],
                        0 AS [Filename],
                        0 AS [Duration],
                        0 AS [StartTime],
                        0 AS [EndTime],
                        0 AS ChangeInSize,
                        0 AS [ApplicationName],
                        0 AS [HostName],
                        0 AS [SessionLoginName],
                        0 AS [SPID]
            END    TRY
            BEGIN CATCH
                SELECT
                    SERVERPROPERTY('MachineName') AS ComputerName,
                    ISNULL(SERVERPROPERTY('InstanceName'), 'MSSQLSERVER') AS InstanceName,
                    SERVERPROPERTY('ServerName') AS SqlInstance,
                    -100 AS [OrderRank],
                    -100 AS [OrderRank],
                    ERROR_NUMBER() AS [EventClass],
                    ERROR_SEVERITY() AS [DatabaseName],
                    ERROR_STATE() AS [Filename],
                    ERROR_MESSAGE() AS [Duration],
                    1 AS [StartTime],
                    1 AS [EndTime],
                    1 AS [ChangeInSize],
                    1 AS [ApplicationName],
                    1 AS [HostName],
                    1 AS [SessionLoginName],
                    1 AS [SPID]
            END CATCH";

}
