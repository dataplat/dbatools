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
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Common;
using Microsoft.SqlServer.Management.Smo;
// the sibling namespace Dataplat.Dbatools.Database shadows Smo.Database inside Dataplat.Dbatools.Commands
using SmoDatabase = Microsoft.SqlServer.Management.Smo.Database;

namespace Dataplat.Dbatools.Commands;

// Port of public/Find-DbaStoredProcedure.ps1: the query, the database selection, the regex matching, the line search,
// the output and the context restore run here in C#. Quirks kept: SqlInstance in the output is $server.ServiceName
// (Azure: correction azure-sqldb); the database filter keeps only databases whose Status -eq "normal"; the procedure is
// looked up again in $db.StoredProcedures with -eq. Corrections: database-wildcards, encrypted-procedure-text.
/// <summary>Searches stored procedure definitions for specific text patterns or regex expressions across SQL Server databases.</summary>
[Cmdlet(VerbsCommon.Find, "DbaStoredProcedure")]
public sealed class FindDbaStoredProcedureCommand : DbaInstanceCmdlet
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

    /// <summary>The regular-expression pattern to match against procedure definitions.</summary>
    [Parameter(Mandatory = true, Position = 4)]
    [PsStringCast]
    public string Pattern { get; set; } = null!;

    /// <summary>Include system stored procedures in the search.</summary>
    [Parameter]
    public SwitchParameter IncludeSystemObjects { get; set; }

    /// <summary>Include system databases in the search.</summary>
    [Parameter]
    public SwitchParameter IncludeSystemDatabases { get; set; }

    private static readonly string[] SplitOn = { "\r\n", "\r", "\n" };

    private static readonly string[] HiddenProperties = { "StoredProcedure", "StoredProcedureFullText" };

    private string _sql = "";
    private int _everyServerSpCount;
    private Regex? _regex;

    // PS: the begin block builds the one fixed query; -IncludeSystemObjects only drops the is_ms_shipped filter.
    protected override void BeginProcessing()
    {
        _sql =
        @"SELECT OBJECT_SCHEMA_NAME(p.object_id) AS ProcSchema, p.name, m.definition AS TextBody
          FROM sys.sql_modules AS m
           INNER JOIN sys.procedures AS p
            ON m.object_id = p.object_id";

        if (!IncludeSystemObjects.ToBool())
            _sql = _sql + " WHERE p.is_ms_shipped = 0;";

        _everyServerSpCount = 0;
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

            int totalCount = 0;
            int dbCount = dbs.Count;

            // Working through a Database object moves the connection into that database and never moves it back, so
            // the caller's database is put back when the work is done (#10555).
            string callerDatabase = server.ConnectionContext.CurrentDatabase;
            try
            {
                foreach (SmoDatabase db in dbs)
                    totalCount += SearchDatabase(server, db);
            }
            finally
            {
                PutDatabaseBack(server.ConnectionContext, callerDatabase, false);
            }

            WriteMessage(MessageLevel.Verbose, String.Format(CultureInfo.InvariantCulture,
                "Evaluated {0} total stored procedures in {1} databases", totalCount, dbCount));
        }
    }

    protected override void EndProcessing()
    {
        WriteMessage(MessageLevel.Verbose, String.Format(CultureInfo.InvariantCulture,
            "Evaluated {0} total stored procedures", _everyServerSpCount));
    }

    // PS: $dbs = $server.Databases | Where-Object { $_.Status -eq "normal" [-and $_.IsSystemObject -eq $false] };
    //     then Where-Object Name -In $Database and Where-Object Name -NotIn $ExcludeDatabase.
    // Correction database-wildcards: the pinned help documents wildcards for -Database and -ExcludeDatabase, which the
    // literal -In and -NotIn never honoured. A value still matches exactly as before; a value with * or ? also matches as
    // a case-insensitive wildcard pattern unless it is the real name of a database of the instance (WildcardNameFilter).
    private List<SmoDatabase> SelectDatabases(Server server)
    {
        List<SmoDatabase> dbs = new();
        List<string> allNames = new();
        IEnumerator? enumerator = null;
        try
        {
            enumerator = LanguagePrimitives.GetEnumerator(server.Databases);
            while (enumerator is not null && enumerator.MoveNext())
            {
                if (enumerator.Current is not SmoDatabase candidate)
                    continue;
                string? candidateName = Read(() => candidate.Name) as string;
                if (candidateName is not null)
                    allNames.Add(candidateName);
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
        {
            WildcardNameMatcher include = WildcardNameFilter.CreateMatcher(Database, true, InOperandEquals, allNames);
            dbs = dbs.FindAll(db => include.Matches(Read(() => db.Name) as string ?? ""));
        }

        if (PsOps.IsTrue(ExcludeDatabase))
        {
            WildcardNameMatcher exclude = WildcardNameFilter.CreateMatcher(ExcludeDatabase, true, InOperandEquals, allNames);
            dbs = dbs.FindAll(db => !exclude.Matches(Read(() => db.Name) as string ?? ""));
        }

        return dbs;
    }

    // PS: $name -in $values for one value: the value is the left operand of -eq, so the name converts to its type.
    private static bool InOperandEquals(object value, string name)
    {
        return PsOps.Eq(value, name);
    }

    private int SearchDatabase(Server server, SmoDatabase db)
    {
        WriteMessage(MessageLevel.Verbose, String.Format(CultureInfo.InvariantCulture, "Searching on database {0}", db));
        WriteMessage(MessageLevel.Debug, _sql);
        DataTable? rows = DatabaseQuery(db, _sql);

        int spCount = 0;
        foreach (DataRow row in Rows(rows))
        {
            spCount++;
            _everyServerSpCount++;

            string procSchema = Text(row["ProcSchema"]);
            string proc = Text(row["Name"]);
            WriteMessage(MessageLevel.Verbose, String.Format(CultureInfo.InvariantCulture,
                "Looking in stored procedure: {0}.{1} textBody for {2}", procSchema, proc, Pattern));

            object textBody = row["TextBody"];
            if (PatternRegex().IsMatch(Text(textBody)))
                WriteObject(Output(server, db, procSchema, proc, textBody));
        }

        WriteMessage(MessageLevel.Verbose, String.Format(CultureInfo.InvariantCulture,
            "Evaluated {0} stored procedures in {1}", spCount, db));
        return spCount;
    }

    private static IEnumerable<DataRow> Rows(DataTable? table)
    {
        if (table is null)
            yield break;
        foreach (DataRow row in table.Rows)
            yield return row;
    }

    // PS: [PSCustomObject]@{ ... } | Select-DefaultView -ExcludeProperty StoredProcedure, StoredProcedureFullText
    private PSObject Output(Server server, SmoDatabase db, string procSchema, string proc, object textBody)
    {
        // PS: $sp = $db.StoredProcedures | Where-Object { $_.Schema -eq $procSchema -and $_.Name -eq $proc }
        List<StoredProcedure> found = new();
        foreach (StoredProcedure candidate in db.StoredProcedures)
        {
            if (PsOps.Eq(Read(() => candidate.Schema), procSchema) && PsOps.Eq(Read(() => candidate.Name), proc))
                found.Add(candidate);
        }

        PSObject output = new();
        output.Properties.Add(new PSNoteProperty("ComputerName", Dataplat.Dbatools.Connection.SmoServerExtensions.GetComputerName(server))); // style-ok: cs-output-props the pinned [PSCustomObject] has ComputerName and SqlInstance only, no InstanceName, and its display set comes from -ExcludeProperty
        output.Properties.Add(new PSNoteProperty("SqlInstance", SqlInstanceValue(server))); // style-ok: cs-output-props the pinned SqlInstance is $server.ServiceName
        output.Properties.Add(new PSNoteProperty("Database", db.Name));
        output.Properties.Add(new PSNoteProperty("DatabaseId", db.ID));
        output.Properties.Add(new PSNoteProperty("Schema", Member(found, sp => sp.Schema)));
        output.Properties.Add(new PSNoteProperty("Name", Member(found, sp => sp.Name)));
        output.Properties.Add(new PSNoteProperty("Owner", Member(found, sp => sp.Owner)));
        output.Properties.Add(new PSNoteProperty("IsSystemObject", Member(found, sp => sp.IsSystemObject)));
        output.Properties.Add(new PSNoteProperty("CreateDate", Member(found, sp => sp.CreateDate)));
        output.Properties.Add(new PSNoteProperty("LastModified", Member(found, sp => sp.DateLastModified)));
        output.Properties.Add(new PSNoteProperty("StoredProcedureTextFound", TextFound(textBody)));
        output.Properties.Add(new PSNoteProperty("StoredProcedure", found.Count == 0 ? null : found.Count == 1 ? (object)found[0] : found.ToArray()));
        output.Properties.Add(new PSNoteProperty("StoredProcedureFullText", textBody));
        OutputHelper.SetDefaultDisplayPropertySetExcluding(output, HiddenProperties);
        return output;
    }

    // PS: $sp.<Property> on what Where-Object returned: $null for none, the value for one, an array for several.
    private static object? Member(List<StoredProcedure> found, Func<StoredProcedure, object?> getter)
    {
        if (found.Count == 0)
            return null;
        if (found.Count == 1)
            return Read(() => getter(found[0]));
        List<object?> values = new();
        foreach (StoredProcedure sp in found)
            values.Add(Read(() => getter(sp)));
        return values.ToArray();
    }

    // PS: $StoredProcedureText.Split($splitOn, None) | Select-String -Pattern $Pattern |
    //     ForEach-Object { "(LineNumber: $($_.LineNumber)) $($_.ToString().Trim())" }, joined with NewLine.
    // Correction encrypted-procedure-text: sys.sql_modules.definition is NULL for an encrypted procedure. The pinned
    // .Split on that DBNull failed with a method error and left $spTextFound as the previous match's lines, so the
    // encrypted procedure was reported with another procedure's text. An encrypted procedure has no lines to show.
    private string TextFound(object textBody)
    {
        if (textBody is not string text)
            return "";
        List<string> found = new();
        string[] lines = text.Split(SplitOn, StringSplitOptions.None);
        for (int index = 0; index < lines.Length; index++)
        {
            if (PatternRegex().IsMatch(lines[index]))
                found.Add(String.Format(CultureInfo.InvariantCulture, "(LineNumber: {0}) {1}", index + 1, lines[index].Trim()));
        }
        return String.Join(Environment.NewLine, found);
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

    // PS: string conversion for -match and for "$value" in the messages; DBNull and $null are empty.
    private static string Text(object? value)
    {
        if (value is null || value is DBNull)
            return "";
        return (string)LanguagePrimitives.ConvertTo(value, typeof(string), CultureInfo.InvariantCulture);
    }

    // PS: -match and Select-String -Pattern, both case-insensitive regular expressions over $Pattern.
    private Regex PatternRegex()
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
        return _regex!;
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
            PutDatabaseBack(connection, previous, true);
        }
    }

    // One routine for both places that move the connection back: the Database.Query script method's finally
    // (scriptMethod true) and Restore-DatabaseContext -Server $server -Database $callerDatabase (scriptMethod false).
    // Both compare case-sensitively (-cne / -ceq), as database names follow the instance collation, then run
    // $null = $connection.ExecuteNonQuery("USE [...]"), and only warn when that fails: the script method through plain
    // Write-Warning with a Stop or Inquire preference raised to Continue, Restore-DatabaseContext through Write-Message.
    private void PutDatabaseBack(ServerConnection connection, string database, bool scriptMethod)
    {
        if (String.IsNullOrEmpty(database) || String.Equals(connection.CurrentDatabase, database, StringComparison.Ordinal))
            return;
        string warning;
        try
        {
            connection.ExecuteNonQuery("USE [" + database.Replace("]", "]]") + "]");
            return;
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            warning = String.Format(CultureInfo.InvariantCulture, RestoreWarning, database,
                "Exception calling \"ExecuteNonQuery\" with \"1\" argument(s): \"" + failure.Message + "\"");
        }

        if (!scriptMethod)
        {
            WriteAttributedMessage("Restore-DatabaseContext", MessageLevel.Warning, warning);
            return;
        }
        try
        {
            WriteWarning(warning); // style-ok: cs-raw-streams the Database.Query script method calls plain Write-Warning, not Write-Message
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
