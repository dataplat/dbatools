#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Data;
using System.Globalization;
using System.Management.Automation;
using System.Text.RegularExpressions;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Microsoft.SqlServer.Management.Common;
using Microsoft.SqlServer.Management.Smo;
// the sibling namespace Dataplat.Dbatools.Database shadows Smo.Database inside Dataplat.Dbatools.Commands
using SmoDatabase = Microsoft.SqlServer.Management.Smo.Database;

namespace Dataplat.Dbatools.Commands;

// Port of public/Find-DbaObject.ps1: the query building, the database selection, the queries, the regex matching and
// the context restore run here in C#. Quirks kept: SqlInstance in the output is $server.ServiceName (Azure: correction azure-sqldb); -Database and
// -ExcludeDatabase compare exact names (-in / -notin), as the help documents no wildcards; the database filter keeps
// only databases whose Status -eq "normal".
/// <summary>Searches database objects by name or column name across SQL Server databases using regex patterns.</summary>
[Cmdlet(VerbsCommon.Find, "DbaObject")]
public sealed class FindDbaObjectCommand : DbaInstanceCmdlet
{
    private const string RestoreWarning = "The database context could not be restored to [{0}]: {1}";

    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public override DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public override PSCredential? SqlCredential { get; set; }

    /// <summary>The database(s) to search.</summary>
    [Parameter(Position = 2)]
    public object[]? Database { get; set; }

    /// <summary>The database(s) to exclude.</summary>
    [Parameter(Position = 3)]
    public object[]? ExcludeDatabase { get; set; }

    /// <summary>The regular-expression pattern to match object (and column) names against.</summary>
    [Parameter(Mandatory = true, Position = 4)]
    [PsStringCast]
    public string Pattern { get; set; } = null!;

    /// <summary>The object type(s) to search.</summary>
    [Parameter(Position = 5)]
    [ValidateSet("Table", "View", "StoredProcedure", "ScalarFunction", "TableValuedFunction", "Synonym", "Trigger", "All")]
    [PsStringArrayCast]
    public string[] ObjectType { get; set; } = new[] { "All" };

    /// <summary>Also search column names.</summary>
    [Parameter]
    public SwitchParameter IncludeColumns { get; set; }

    /// <summary>Include system objects in the search.</summary>
    [Parameter]
    public SwitchParameter IncludeSystemObjects { get; set; }

    /// <summary>Include system databases in the search.</summary>
    [Parameter]
    public SwitchParameter IncludeSystemDatabases { get; set; }

    private string _sqlObjects = "";
    private string _sqlColumns = "";
    private Regex? _regex;

    // PS: the begin block builds the two query strings from -ObjectType and -IncludeSystemObjects. The values are the
    // fixed type codes of $typeCodeMap, never caller text.
    protected override void BeginProcessing()
    {
        string typeFilter;
        if (PsOps.In("All", ObjectType))
        {
            typeFilter = "'U', 'V', 'P', 'FN', 'IF', 'TF', 'SN', 'TR'";
        }
        else
        {
            // PS: $typeCodes += $typeCodeMap[$type]; ($typeCodes | Select-Object -Unique) -join ", "
            List<string> typeCodes = new();
            foreach (string type in ObjectType ?? Array.Empty<string>())
            {
                foreach (string code in TypeCodes(type))
                {
                    if (!typeCodes.Contains(code))
                        typeCodes.Add(code);
                }
            }
            typeFilter = String.Join(", ", typeCodes);
        }

        bool includeDatabaseTriggers = PsOps.In("All", ObjectType) || PsOps.In("Trigger", ObjectType);
        string sysFilter = IncludeSystemObjects.ToBool() ? "" : "AND o.is_ms_shipped = 0";
        string triggerFilter = IncludeSystemObjects.ToBool() ? "" : "AND tr.is_ms_shipped = 0";

        _sqlObjects = @"
            SELECT
                OBJECT_SCHEMA_NAME(o.object_id) AS SchemaName,
                o.name                          AS ObjectName,
                RTRIM(o.type)                   AS ObjectTypeCode,
                o.type_desc                     AS ObjectType,
                o.create_date                   AS CreateDate,
                o.modify_date                   AS LastModified
            FROM sys.objects o
            WHERE o.type IN (" + typeFilter + @")
            " + sysFilter;

        if (includeDatabaseTriggers)
        {
            _sqlObjects += @"
            UNION ALL
            SELECT
                CAST(NULL AS sysname)            AS SchemaName,
                tr.name                          AS ObjectName,
                RTRIM(tr.type)                   AS ObjectTypeCode,
                tr.type_desc                     AS ObjectType,
                tr.create_date                   AS CreateDate,
                tr.modify_date                   AS LastModified
            FROM sys.triggers tr
            WHERE tr.parent_class = 0
            AND tr.type = 'TR'
            " + triggerFilter;
        }

        _sqlColumns = @"
            SELECT
                OBJECT_SCHEMA_NAME(c.object_id) AS SchemaName,
                OBJECT_NAME(c.object_id)        AS ObjectName,
                RTRIM(o.type)                   AS ObjectTypeCode,
                o.type_desc                     AS ObjectType,
                o.create_date                   AS CreateDate,
                o.modify_date                   AS LastModified,
                c.name                          AS ColumnName
            FROM sys.columns c
            INNER JOIN sys.objects o ON c.object_id = o.object_id
            WHERE o.type IN (" + typeFilter + @")
            " + sysFilter;
    }

    // PS: $typeCodeMap, a case-insensitive hashtable literal.
    private static string[] TypeCodes(string? type)
    {
        switch ((type ?? "").ToUpperInvariant())
        {
            case "TABLE": return new[] { "'U'" };
            case "VIEW": return new[] { "'V'" };
            case "STOREDPROCEDURE": return new[] { "'P'" };
            case "SCALARFUNCTION": return new[] { "'FN'" };
            case "TABLEVALUEDFUNCTION": return new[] { "'IF'", "'TF'" };
            case "SYNONYM": return new[] { "'SN'" };
            case "TRIGGER": return new[] { "'TR'" };
            default: return Array.Empty<string>();
        }
    }

    protected override void ProcessRecord()
    {
        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            // PS: try { Connect-DbaInstance } catch { Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue }
            Server? server = ConnectInstance(instance, "Failure");
            if (server is null)
                continue;

            if (server.VersionMajor < 9)
            {
                WriteMessage(MessageLevel.Warning, "This command only supports SQL Server 2005 and above.");
                continue;
            }

            List<SmoDatabase> dbs = SelectDatabases(server);

            // Working through a Database object moves the connection into that database and never moves it back, so
            // the caller's database is put back when the work is done (#10555).
            string callerDatabase = server.ConnectionContext.CurrentDatabase;
            try
            {
                foreach (SmoDatabase db in dbs)
                    SearchDatabase(server, instance, db);
            }
            finally
            {
                RestoreDatabaseContext(server.ConnectionContext, callerDatabase);
            }
        }
    }

    // PS: $dbs = $server.Databases | Where-Object { $_.Status -eq "normal" [-and $_.IsSystemObject -eq $false] };
    //     then Where-Object Name -In $Database and Where-Object Name -NotIn $ExcludeDatabase.
    private List<SmoDatabase> SelectDatabases(Server server)
    {
        List<SmoDatabase> dbs = new();
        IEnumerator? enumerator = null;
        try
        {
            enumerator = LanguagePrimitives.GetEnumerator(server.Databases);
            while (enumerator is not null && enumerator.MoveNext())
            {
                if (enumerator.Current is not SmoDatabase candidate)
                    continue;
                bool normal = PsOps.Eq(Read(() => candidate.Status), "normal");
                bool selected = IncludeSystemDatabases.ToBool()
                    ? normal
                    : normal && PsOps.Eq(Read(() => candidate.IsSystemObject), false);
                if (selected)
                    dbs.Add(candidate);
            }
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            // caller-try: terminate -- continuing would search the databases of the previous instance under this one
            ThrowTerminatingError(EnumerationFault(failure, enumerator)); // style-ok: cs-raw-streams pipeline statement fault outside Stop-Function, as in the source
        }

        if (PsOps.IsTrue(Database))
            dbs = dbs.FindAll(db => PsOps.In(Read(() => db.Name), Database));

        if (PsOps.IsTrue(ExcludeDatabase))
            dbs = dbs.FindAll(db => !PsOps.In(Read(() => db.Name), ExcludeDatabase));

        return dbs;
    }

    private void SearchDatabase(Server server, DbaInstanceParameter instance, SmoDatabase db)
    {
        WriteMessage(MessageLevel.Verbose, String.Format(CultureInfo.InvariantCulture,
            "Searching object names in database {0} on {1}", db, instance));
        WriteMessage(MessageLevel.Debug, _sqlObjects);
        DataTable? objectRows = DatabaseQuery(db, _sqlObjects);

        foreach (DataRow row in Rows(objectRows))
        {
            if (Matches(row["ObjectName"]))
                WriteObject(Output(server, db, row, "ObjectName", null));
        }

        if (IncludeColumns.ToBool())
        {
            WriteMessage(MessageLevel.Verbose, String.Format(CultureInfo.InvariantCulture,
                "Searching column names in database {0} on {1}", db, instance));
            WriteMessage(MessageLevel.Debug, _sqlColumns);
            DataTable? columnRows = DatabaseQuery(db, _sqlColumns);

            foreach (DataRow row in Rows(columnRows))
            {
                if (Matches(row["ColumnName"]))
                    WriteObject(Output(server, db, row, "ColumnName", row["ColumnName"]));
            }
        }
    }

    private static IEnumerable<DataRow> Rows(DataTable? table)
    {
        if (table is null)
            yield break;
        foreach (DataRow row in table.Rows)
            yield return row;
    }

    // PS: [PSCustomObject]@{ ... } in the source's property order.
    private static PSObject Output(Server server, SmoDatabase db, DataRow row, string matchType, object? columnName)
    {
        PSObject output = new();
        output.Properties.Add(new PSNoteProperty("ComputerName", Dataplat.Dbatools.Connection.SmoServerExtensions.GetComputerName(server))); // style-ok: cs-output-props the pinned [PSCustomObject] has ComputerName and SqlInstance only, no InstanceName and no display set
        output.Properties.Add(new PSNoteProperty("SqlInstance", SqlInstanceValue(server))); // style-ok: cs-output-props the pinned SqlInstance is $server.ServiceName
        output.Properties.Add(new PSNoteProperty("Database", db.Name));
        output.Properties.Add(new PSNoteProperty("Schema", row["SchemaName"]));
        output.Properties.Add(new PSNoteProperty("Name", row["ObjectName"]));
        output.Properties.Add(new PSNoteProperty("ObjectType", row["ObjectType"]));
        output.Properties.Add(new PSNoteProperty("MatchType", matchType));
        output.Properties.Add(new PSNoteProperty("ColumnName", columnName));
        output.Properties.Add(new PSNoteProperty("CreateDate", row["CreateDate"]));
        output.Properties.Add(new PSNoteProperty("LastModified", row["LastModified"]));
        return output;
    }

    // PS: SqlInstance = $server.ServiceName.
    // Correction azure-sqldb: Azure SQL Database has no SQL Server service, and SMO raises "ServiceName: unknown
    // property." there, so the pinned statement failed for every match and the command returned nothing. On that engine
    // the logical server is the instance, reported as dbatools reports SqlInstance elsewhere (DomainInstanceName).
    private static string SqlInstanceValue(Server server)
    {
        if (server.DatabaseEngineType == DatabaseEngineType.SqlAzureDatabase)
            return Dataplat.Dbatools.Connection.SmoServerExtensions.GetDomainInstanceName(server);
        return server.ServiceName;
    }

    // PS: $value -match $Pattern, which builds a case-insensitive Regex and converts the value to a string.
    private bool Matches(object? value)
    {
        if (_regex is null)
        {
            try
            {
                _regex = new Regex(Pattern, RegexOptions.IgnoreCase);
            }
            catch (ArgumentException invalid)
            {
                RuntimeException fault = new(String.Format(CultureInfo.CurrentCulture,
                    "The regular expression pattern {0} is not valid.", Pattern), invalid);
                // caller-try: terminate -- the -match statement fault fails every row alike, so continuing emits nothing more
                ThrowTerminatingError(new ErrorRecord(fault, "InvalidRegularExpression", ErrorCategory.InvalidOperation, Pattern)); // style-ok: cs-raw-streams operator fault outside Stop-Function, as in the source
            }
        }
        string text = (string)LanguagePrimitives.ConvertTo(value, typeof(string), CultureInfo.InvariantCulture);
        return _regex!.IsMatch(text);
    }

    // PS: $db.Query($sql), the dbatools Database.Query script method: ExecuteWithResults on the server's own
    // connection, first table, and the previous database put back in its finally.
    private DataTable? DatabaseQuery(SmoDatabase database, string sql)
    {
        ServerConnection connection = database.Parent.ConnectionContext;
        string previous = connection.CurrentDatabase;
        try
        {
            DataSet results = database.ExecuteWithResults(sql);
            return results.Tables.Count > 0 ? results.Tables[0] : null;
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            MethodInvocationException call = new(String.Format(CultureInfo.InvariantCulture,
                "Exception calling \"ExecuteWithResults\" with \"1\" argument(s): \"{0}\"", failure.Message), failure);
            MethodInvocationException query = new(String.Format(CultureInfo.InvariantCulture,
                "Exception calling \"Query\" with \"1\" argument(s): \"{0}\"", call.Message), call);
            // caller-try: terminate -- continuing would match the rows of the previous database under this one
            ThrowTerminatingError(new ErrorRecord(query, "ScriptMethodRuntimeException", ErrorCategory.NotSpecified, null)); // style-ok: cs-raw-streams method fault outside Stop-Function, as in the source
            return null;
        }
        finally
        {
            if (!String.IsNullOrEmpty(previous) && !String.Equals(connection.CurrentDatabase, previous, StringComparison.Ordinal))
            {
                string? failed = UseDatabase(connection, previous);
                if (failed is not null)
                    ScriptMethodWarning(String.Format(CultureInfo.InvariantCulture, RestoreWarning, previous, failed));
            }
        }
    }

    // PS: Restore-DatabaseContext -Server $server -Database $callerDatabase
    private void RestoreDatabaseContext(ServerConnection connection, string callerDatabase)
    {
        // -ceq on purpose: database names follow the instance collation.
        if (String.IsNullOrEmpty(callerDatabase) || String.Equals(connection.CurrentDatabase, callerDatabase, StringComparison.Ordinal))
            return;
        string? failed = UseDatabase(connection, callerDatabase);
        if (failed is not null)
            WriteAttributedMessage("Restore-DatabaseContext", MessageLevel.Warning, String.Format(CultureInfo.InvariantCulture, RestoreWarning, callerDatabase, failed));
    }

    // $null = $connection.ExecuteNonQuery("USE [...]"); the method fault's message when it fails, null when it worked.
    private static string? UseDatabase(ServerConnection connection, string database)
    {
        try
        {
            connection.ExecuteNonQuery("USE [" + database.Replace("]", "]]") + "]");
            return null;
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            return String.Format(CultureInfo.InvariantCulture,
                "Exception calling \"ExecuteNonQuery\" with \"1\" argument(s): \"{0}\"", failure.Message);
        }
    }

    // The script method warns through plain Write-Warning and raises a Stop or Inquire preference to Continue for it.
    private void ScriptMethodWarning(string text)
    {
        try
        {
            WriteWarning(text); // style-ok: cs-raw-streams the Database.Query script method calls plain Write-Warning, not Write-Message
        }
        catch (ActionPreferenceStopException stopped)
        {
            // The preference the script method raises to Continue must not end the command here.
            WriteMessage(MessageLevel.Debug, stopped.Message);
        }
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
}
