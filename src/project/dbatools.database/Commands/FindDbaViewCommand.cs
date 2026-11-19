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

// Port of public/Find-DbaView.ps1: the query and SMO paths, the database selection, the regex matching, the line search,
// the output and the context restore run here in C#. Quirks kept: SqlInstance in the output is $server.ServiceName; the
// database filter keeps only databases whose Status -eq "normal"; the query path matches the sys.sql_modules definition,
// then looks the view up again in $db.Views with -eq and reports the SMO TextBody (the text after the view's header);
// -ExcludeDatabase compares exact names (-notin), as its help documents no wildcards; the matched lines are joined with "`n".
// Corrections: view-line-numbers, database-wildcards, view-messages, encrypted-view-text, azure-sqldb.
/// <summary>Searches database views for specific text patterns or regular expressions in their definitions.</summary>
[Cmdlet(VerbsCommon.Find, "DbaView")]
public sealed class FindDbaViewCommand : DbaInstanceCmdlet
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

    /// <summary>The regular-expression pattern to match against view definitions.</summary>
    [Parameter(Mandatory = true, Position = 4)]
    [PsStringCast]
    public string Pattern { get; set; } = null!;

    /// <summary>Include system views in the search.</summary>
    [Parameter]
    public SwitchParameter IncludeSystemObjects { get; set; }

    /// <summary>Include system databases in the search.</summary>
    [Parameter]
    public SwitchParameter IncludeSystemDatabases { get; set; }

    private static readonly string[] ViewLineEnds = { "\r\n", "\r", "\n" };

    private static readonly string[] HiddenProperties = { "View", "ViewFullText" };

    private string _sql = "";
    private int _everyServerVwCount;
    private Regex? _regex;

    // PS: the begin block builds the one query of the query path; -IncludeSystemObjects drops the is_ms_shipped filter
    // (and takes the SMO path, which never runs it).
    protected override void BeginProcessing()
    {
        _sql = "SELECT OBJECT_SCHEMA_NAME(vw.object_id) AS ViewSchema, vw.name, m.definition AS TextBody FROM sys.sql_modules m, sys.views vw WHERE m.object_id = vw.object_id";
        if (!IncludeSystemObjects.ToBool())
            _sql = _sql + " AND vw.is_ms_shipped = 0";
        _everyServerVwCount = 0;
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
                "Evaluated {0} total views in {1} databases", totalCount, dbCount));
        }
    }

    protected override void EndProcessing()
    {
        WriteMessage(MessageLevel.Verbose, String.Format(CultureInfo.InvariantCulture,
            "Evaluated {0} total views", _everyServerVwCount));
    }

    // PS: $dbs = $server.Databases | Where-Object { $_.Status -eq "normal" [-and $_.IsSystemObject -eq $false] };
    //     then Where-Object Name -In $Database and Where-Object Name -NotIn $ExcludeDatabase.
    // Correction database-wildcards: the pinned help documents wildcards for -Database, which the literal -In never
    // honoured. A value still matches exactly as before; a value with * or ? also matches as a case-insensitive wildcard
    // pattern unless it is the real name of a database of the instance (rule E+). -ExcludeDatabase documents none.
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
                if (Read(() => candidate.Name) is string candidateName)
                    allNames.Add(candidateName);
                bool normal = PsOps.Eq(Read(() => candidate.Status), "normal");
                if (normal && (IncludeSystemDatabases.ToBool() || PsOps.Eq(Read(() => candidate.IsSystemObject), false)))
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
            WildcardNameMatcher include = NativeDatabaseSelection.CreateInOperandMatcher(Database, true, allNames);
            dbs = dbs.FindAll(db => include.Matches(Read(() => db.Name) as string ?? ""));
        }

        if (PsOps.IsTrue(ExcludeDatabase))
            dbs = dbs.FindAll(db => !NativeDatabaseSelection.ContainsInOperand(ExcludeDatabase, Read(() => db.Name) as string ?? ""));

        return dbs;
    }

    // One database: the query path without -IncludeSystemObjects, the SMO path with it. Returns the views evaluated.
    // Correction view-messages: the pinned SMO path never reset $vwcount, so "Evaluated N views in <db>" added every
    // database searched before it, and read the schema from $row, which that path never sets. The count now starts at 0
    // for every database on both paths, and the SMO path names the view's own schema.
    private int SearchDatabase(Server server, SmoDatabase db)
    {
        WriteMessage(MessageLevel.Verbose, String.Format(CultureInfo.InvariantCulture, "Searching on database {0}", db));
        int evaluated = 0;

        if (!IncludeSystemObjects.ToBool())
        {
            WriteMessage(MessageLevel.Debug, _sql);
            DataTable? rows = DatabaseQuery(db, _sql);
            foreach (DataRow row in Rows(rows))
            {
                evaluated++;
                _everyServerVwCount++;

                string viewSchema = Text(row["ViewSchema"]);
                string view = Text(row["name"]);
                LookingIn(viewSchema, view);
                if (!Matches(Text(row["TextBody"])))
                    continue;

                // PS: $vw = $db.Views | Where-Object { $_.Schema -eq $viewSchema -and $_.Name -eq $view }
                List<View> found = new();
                foreach (View candidate in db.Views)
                {
                    if (PsOps.Eq(Read(() => candidate.Schema), viewSchema) && PsOps.Eq(Read(() => candidate.Name), view))
                        found.Add(candidate);
                }
                WriteObject(Output(server, db, found));
            }
        }
        else
        {
            foreach (View vw in db.Views)
            {
                evaluated++;
                _everyServerVwCount++;

                LookingIn(Text(Read(() => vw.Schema)), Text(Read(() => vw.Name)));
                if (Matches(Text(Read(() => vw.TextBody))))
                    WriteObject(Output(server, db, new List<View> { vw }));
            }
        }

        WriteMessage(MessageLevel.Verbose, String.Format(CultureInfo.InvariantCulture,
            "Evaluated {0} views in {1}", evaluated, db));
        return evaluated;
    }

    private void LookingIn(string viewSchema, string view)
    {
        WriteMessage(MessageLevel.Verbose, String.Format(CultureInfo.InvariantCulture,
            "Looking in View: {0}.{1} TextBody for {2}", viewSchema, view, Pattern));
    }

    private static IEnumerable<DataRow> Rows(DataTable? table)
    {
        if (table is null)
            yield break;
        foreach (DataRow row in table.Rows)
            yield return row;
    }

    // PS: [PSCustomObject]@{ ... } | Select-DefaultView -ExcludeProperty View, ViewFullText, every value read from $vw:
    // $null for no view, the value for one, an array for several.
    private PSObject Output(Server server, SmoDatabase db, List<View> found)
    {
        object? textBody = Member(found, vw => vw.TextBody);
        PSObject output = new();
        output.Properties.Add(new PSNoteProperty("ComputerName", Dataplat.Dbatools.Connection.SmoServerExtensions.GetComputerName(server))); // style-ok: cs-output-props the pinned [PSCustomObject] has ComputerName and SqlInstance only, no InstanceName, and its display set comes from -ExcludeProperty
        output.Properties.Add(new PSNoteProperty("SqlInstance", SqlInstanceValue(server))); // style-ok: cs-output-props the pinned SqlInstance is $server.ServiceName
        output.Properties.Add(new PSNoteProperty("Database", db.Name));
        output.Properties.Add(new PSNoteProperty("DatabaseId", db.ID));
        output.Properties.Add(new PSNoteProperty("Schema", Member(found, vw => vw.Schema)));
        output.Properties.Add(new PSNoteProperty("Name", Member(found, vw => vw.Name)));
        output.Properties.Add(new PSNoteProperty("Owner", Member(found, vw => vw.Owner)));
        output.Properties.Add(new PSNoteProperty("IsSystemObject", Member(found, vw => vw.IsSystemObject)));
        output.Properties.Add(new PSNoteProperty("CreateDate", Member(found, vw => vw.CreateDate)));
        output.Properties.Add(new PSNoteProperty("LastModified", Member(found, vw => vw.DateLastModified)));
        output.Properties.Add(new PSNoteProperty("ViewTextFound", TextFound(textBody)));
        output.Properties.Add(new PSNoteProperty("View", found.Count == 0 ? null : found.Count == 1 ? (object)found[0] : found.ToArray()));
        output.Properties.Add(new PSNoteProperty("ViewFullText", textBody));
        OutputHelper.SetDefaultDisplayPropertySetExcluding(output, HiddenProperties);
        return output;
    }

    private static object? Member(List<View> found, Func<View, object?> getter)
    {
        if (found.Count == 0)
            return null;
        if (found.Count == 1)
            return Read(() => getter(found[0]));
        List<object?> values = new();
        foreach (View vw in found)
            values.Add(Read(() => getter(vw)));
        return values.ToArray();
    }

    // PS: $viewText = $vw.TextBody.split($eol); $vwTextFound = $viewText | Select-String -Pattern $Pattern |
    //     ForEach-Object { "(LineNumber: $($_.LineNumber)) $($_.ToString().Trim())" }; ViewTextFound = $vwTextFound -join "`n".
    // Several views (member enumeration) give one list of lines, numbered on.
    // Correction view-line-numbers: .split($eol) bound to Split(char[]) on Windows PowerShell, which cut CR and LF apart
    // and counted an empty line after every CR LF, and to Split(string) on PowerShell 7, which never cut a text with LF
    // line ends; the line numbers were wrong on both. The text is now cut at CR LF, CR and LF on both.
    // Correction encrypted-view-text: an encrypted view's TextBody reads as $null. The pinned .split on it failed with a
    // method error and left $viewText as the previous match's lines; a view without text now has no lines to show.
    private string TextFound(object? textBody)
    {
        List<string> texts = new();
        if (textBody is string single)
            texts.Add(single);
        else if (textBody is object?[] several)
        {
            foreach (object? item in several)
            {
                if (item is string text)
                    texts.Add(text);
            }
        }

        List<string> found = new();
        int lineNumber = 0;
        foreach (string text in texts)
        {
            foreach (string line in text.Split(ViewLineEnds, StringSplitOptions.None))
            {
                lineNumber++;
                if (Matches(line))
                    found.Add(String.Format(CultureInfo.InvariantCulture, "(LineNumber: {0}) {1}", lineNumber, line.Trim()));
            }
        }
        return String.Join("\n", found);
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
    private bool Matches(string text)
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
                // caller-try: terminate -- the -match statement fault fails every view alike, so continuing emits nothing more
                ThrowTerminatingError(new ErrorRecord(fault, "InvalidRegularExpression", ErrorCategory.InvalidOperation, Pattern)); // style-ok: cs-raw-streams operator fault outside Stop-Function, as in the source
            }
        }
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
            PutDatabaseBack(connection, previous, true);
        }
    }

    // The two places that move the connection back: the Database.Query script method's finally (scriptMethod true) and
    // Restore-DatabaseContext -Server $server -Database $callerDatabase (scriptMethod false). Both compare
    // case-sensitively, run USE [...], and only warn when that fails: the script method through plain Write-Warning
    // with a Stop or Inquire preference raised to Continue, Restore-DatabaseContext through Write-Message.
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
