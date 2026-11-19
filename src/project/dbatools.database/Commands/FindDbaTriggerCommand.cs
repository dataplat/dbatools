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

// Port of public/Find-DbaTrigger.ps1: the server, database and object level searches, the SQL and SMO paths, the regex
// matching, the line search, the output and the context restore run here in C#. Quirks kept: SqlInstance in the output
// is $server.ServiceName (Azure: correction azure-sqldb); -Database and -ExcludeDatabase compare exact names (-in /
// -notin), as the help documents no wildcards; the matched lines come from the SMO TextBody, joined with "`n".
// Corrections: trigger-line-numbers, trigger-counts, azure-sqldb.
/// <summary>Searches trigger code across server, database, and object levels for specific text patterns or regex matches.</summary>
/// <para>
/// Searches through SQL Server trigger definitions to find specific text patterns, supporting both literal strings and regular expressions. Examines triggers at three levels: server-level triggers, database-level DDL triggers, and object-level DML triggers on tables and views.
/// </para>
/// <para>
/// This is particularly useful when you need to find triggers that reference specific objects before making schema changes, locate hardcoded values that need updating, or audit trigger code for compliance requirements. The function returns matching lines with line numbers, making it easy to pinpoint exactly where patterns occur in trigger code.
/// </para>
/// <para>
/// When you specify specific databases, server-level trigger searches are skipped to focus the search scope. The function uses efficient SQL queries against system catalog views to examine trigger definitions without loading all trigger objects into memory.
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Find-DbaTrigger -SqlInstance DEV01 -Pattern whatever
/// </code>
/// <para>
/// Searches all user databases triggers for "whatever" in the text body
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Find-DbaTrigger -SqlInstance sql2016 -Pattern '\w+@\w+\.\w+'
/// </code>
/// <para>
/// Searches all databases for all triggers that contain a valid email pattern in the text body
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Find-DbaTrigger -SqlInstance DEV01 -Database MyDB -Pattern 'some string' -Verbose
/// </code>
/// <para>
/// Searches in "mydb" database triggers for "some string" in the text body
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Find-DbaTrigger -SqlInstance sql2016 -Database MyDB -Pattern RUNTIME -IncludeSystemObjects
/// </code>
/// <para>
/// Searches in "mydb" database triggers for "runtime" in the text body
/// </para>
/// </example>
/// <list type="alertSet">
/// <item>
/// <term />
/// <description>
/// <para>
/// Tags: Trigger, Lookup
/// Author: Claudio Silva (@ClaudioESSilva)
/// </para>
/// <para>
/// Website: https://dbatools.io
/// Copyright: (c) 2018 by dbatools, licensed under MIT
/// License: MIT https://opensource.org/licenses/MIT
/// </para>
/// </description>
/// </item>
/// </list>
/// <seealso href="https://dbatools.io/Find-DbaTrigger" />
[Cmdlet(VerbsCommon.Find, "DbaTrigger")]
public sealed class FindDbaTriggerCommand : DbaInstanceCmdlet
{
    private const string RestoreWarning = "The database context could not be restored to [{0}]: {1}";

    /// <para>
    /// The target SQL Server instance or instances. This can be a collection and receive pipeline input
    /// </para>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public override DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <para>
    /// Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).
    /// </para>
    /// <para>
    /// Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.
    /// </para>
    /// <para>
    /// For MFA support, please use Connect-DbaInstance.
    /// </para>
    [Parameter(Position = 1)]
    public override PSCredential? SqlCredential { get; set; }

    /// <para>
    /// Specifies which databases to search for triggers. Accepts an array of database names for targeting specific databases.
    /// When specified, server-level triggers are automatically excluded from the search to focus on database and object-level triggers.
    /// If omitted, searches all user databases plus any server-level triggers.
    /// </para>
    [Parameter(Position = 2)]
    public object[]? Database { get; set; }

    /// <para>
    /// Excludes specific databases from the trigger search. Accepts an array of database names to skip during processing.
    /// Use this when you want to search most databases but avoid specific ones like staging or temporary databases.
    /// </para>
    [Parameter(Position = 3)]
    public object[]? ExcludeDatabase { get; set; }

    /// <para>
    /// The text pattern or regular expression to search for within trigger definitions. Supports full regex syntax for complex pattern matching.
    /// Use this to find triggers containing specific table names, column references, or code patterns before making schema changes.
    /// Results show matching lines with line numbers to pinpoint exactly where the pattern occurs.
    /// </para>
    [Parameter(Mandatory = true, Position = 4)]
    [PsStringCast]
    public string Pattern { get; set; } = null!;

    /// <para>
    /// Controls which types of triggers to search: Server (instance-level logon triggers), Database (DDL triggers), Object (DML triggers on tables and views), or All.
    /// Use specific levels to narrow your search when you know what type of trigger contains the pattern you're looking for.
    /// Defaults to All, which searches server-level triggers, database DDL triggers, and object-level DML triggers.
    /// </para>
    [Parameter(Position = 5)]
    [ValidateSet("All", "Server", "Database", "Object")]
    [PsStringCast]
    public string TriggerLevel { get; set; } = "All";

    /// <para>
    /// Includes system-created triggers in the search results. By default, only user-created triggers are searched.
    /// Use this when you need to examine built-in triggers for troubleshooting or audit purposes.
    /// Warning: This significantly impacts performance when searching across multiple databases.
    /// </para>
    [Parameter]
    public SwitchParameter IncludeSystemObjects { get; set; }

    /// <para>
    /// Includes system databases (master, model, msdb, tempdb) in the trigger search. By default, only user databases are searched.
    /// Use this when troubleshooting system-level issues or when you need to examine triggers in system databases for audit purposes.
    /// </para>
    [Parameter]
    public SwitchParameter IncludeSystemDatabases { get; set; }

    // Overridden only to carry the pinned .PARAMETER EnableException help; same bare [Parameter] as the base.
    /// <para>
    /// By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
    /// This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
    /// Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.
    /// </para>
    [Parameter]
    public override SwitchParameter EnableException { get; set; }

    private static readonly string[] LineBreaks = { "\r\n", "\r", "\n" };

    private static readonly string[] HiddenProperties = { "Trigger", "TriggerFullText" };

    private string _sqlDatabaseTriggers = "";
    private string _sqlTableTriggers = "";
    private int _everyServerStCount;
    private int _triggerCount;
    private Regex? _regex;

    // PS: the begin block builds the two fixed queries; -IncludeSystemObjects only drops the is_ms_shipped filter.
    protected override void BeginProcessing()
    {
        _sqlDatabaseTriggers = "SELECT tr.name, m.definition AS TextBody FROM sys.sql_modules m, sys.triggers tr WHERE m.object_id = tr.object_id AND tr.parent_class = 0";
        _sqlTableTriggers = "SELECT OBJECT_SCHEMA_NAME(tr.parent_id) TableSchema, OBJECT_NAME(tr.parent_id) AS TableName, tr.name, m.definition AS TextBody FROM sys.sql_modules m, sys.triggers tr WHERE m.object_id = tr.object_id AND tr.parent_class = 1";
        if (!IncludeSystemObjects.ToBool())
            _sqlTableTriggers = _sqlTableTriggers + " AND tr.is_ms_shipped = 0";
        _everyServerStCount = 0;
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

            // PS: search at instance level, only if no database was specified.
            if (!PsOps.IsTrue(Database) && LevelIn("All", "Server"))
                SearchServer(server);

            List<SmoDatabase> dbs = SelectDatabases(server);
            int totalCount = 0;
            int dbCount = dbs.Count;

            if (LevelIn("All", "Database", "Object"))
            {
                // Working through a Database object moves the connection into that database and never moves it back,
                // so the caller's database is put back when the work is done (#10555).
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
            }

            WriteMessage(MessageLevel.Verbose, String.Format(CultureInfo.InvariantCulture,
                "Evaluated {0} total triggers in {1} databases", totalCount, dbCount));
        }
    }

    protected override void EndProcessing()
    {
        WriteMessage(MessageLevel.Verbose, String.Format(CultureInfo.InvariantCulture,
            "Evaluated {0} total triggers", _everyServerStCount));
    }

    // PS: $TriggerLevel -in @(...), case-insensitive.
    private bool LevelIn(params string[] levels)
    {
        return PsOps.In(TriggerLevel, levels);
    }

    // PS: foreach ($trigger in $server.Triggers) { ... }; Write-Message "Evaluated $triggercount triggers in $server".
    // Correction trigger-counts: the pinned $triggercount was never reset here, so the count carried the previous
    // instance's (or pipeline record's) last database count; it now starts at 0 for each instance.
    private void SearchServer(Server server)
    {
        _triggerCount = 0;
        List<ServerDdlTrigger> triggers = new();
        IEnumerator? enumerator = null;
        try
        {
            enumerator = LanguagePrimitives.GetEnumerator(server.Triggers);
            while (enumerator is not null && enumerator.MoveNext())
            {
                if (enumerator.Current is ServerDdlTrigger listed)
                    triggers.Add(listed);
            }
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            // PS: a foreach over a collection that fails to enumerate writes the error and goes on with the function.
            WriteError(EnumerationFault(failure, enumerator)); // style-ok: cs-raw-streams statement fault outside Stop-Function, as in the source
        }

        foreach (ServerDdlTrigger trigger in triggers)
        {
            _everyServerStCount++;
            _triggerCount++;
            WriteMessage(MessageLevel.Debug, String.Format(CultureInfo.InvariantCulture,
                "Looking in Trigger: {0} TextBody for {1}", trigger, Pattern));
            object? textBody = Read(() => trigger.TextBody);
            if (!ServerMatches(textBody))
                continue;
            WriteObject(Output(server, "Server", null, null, null, Read(() => trigger.Name), Read(() => trigger.IsSystemObject),
                Read(() => trigger.CreateDate), Read(() => trigger.DateLastModified), textBody, trigger));
        }

        WriteMessage(MessageLevel.Verbose, String.Format(CultureInfo.InvariantCulture,
            "Evaluated {0} triggers in {1}", _triggerCount, server));
    }

    // The server level runs outside the pinned try/finally: an invalid pattern fails the -match statement, which reaches a
    // caller's try or trap and otherwise writes the error and goes on.
    private bool ServerMatches(object? textBody)
    {
        Regex? regex = TryRegex(out ErrorRecord? invalid);
        if (regex is null)
        {
            // caller-try: terminate -- a caller's try or trap catches the pinned -match fault; every later -match fails alike, so continuing emits nothing more
            ThrowTerminatingError(invalid!); // style-ok: cs-raw-streams operator fault outside Stop-Function, as in the source
        }
        return regex!.IsMatch(Text(textBody));
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

    // One database: the SQL path without -IncludeSystemObjects (no SMO enumeration), the SMO path with it.
    // Correction trigger-counts: the pinned per-database count was reset again before the object level, so under -TriggerLevel
    // All the "Evaluated N triggers in <db>" message counted only the object level; it now counts both levels.
    private int SearchDatabase(Server server, SmoDatabase db)
    {
        WriteMessage(MessageLevel.Verbose, String.Format(CultureInfo.InvariantCulture, "Searching on database {0}", db));
        _triggerCount = 0;
        int evaluated = 0;

        if (!IncludeSystemObjects.ToBool())
        {
            if (LevelIn("All", "Database"))
            {
                WriteMessage(MessageLevel.Debug, _sqlDatabaseTriggers);
                foreach (DataRow row in Rows(DatabaseQuery(db, _sqlDatabaseTriggers)))
                {
                    evaluated++;
                    Count();
                    string trigger = Text(row["name"]);
                    WriteMessage(MessageLevel.Verbose, String.Format(CultureInfo.InvariantCulture,
                        "Looking in trigger {0} for textBody with pattern {1} on database {2}", trigger, Pattern, db));
                    if (!Matches(row["TextBody"]))
                        continue;
                    // PS: $tr = $db.Triggers | Where-Object name -eq $row.name
                    List<object> found = new();
                    foreach (DatabaseDdlTrigger candidate in db.Triggers)
                    {
                        if (PsOps.Eq(Read(() => candidate.Name), row["name"]))
                            found.Add(candidate);
                    }
                    WriteObject(Output(server, "Database", db, found));
                }
            }

            if (LevelIn("All", "Object"))
            {
                WriteMessage(MessageLevel.Debug, _sqlTableTriggers);
                foreach (DataRow row in Rows(DatabaseQuery(db, _sqlTableTriggers)))
                {
                    evaluated++;
                    Count();
                    string trigger = Text(row["name"]);
                    object parentSchema = row["TableSchema"];
                    object parent = row["TableName"];
                    WriteMessage(MessageLevel.Verbose, String.Format(CultureInfo.InvariantCulture,
                        "Looking in trigger {0} for textBody with pattern {1} in object {2}.{3} at database {4}", trigger, Pattern, Text(parentSchema), Text(parent), db));
                    if (!Matches(row["TextBody"]))
                        continue;
                    // PS: ($db.Tables | Where-Object { Name -eq $triggerParent -and Schema -eq $triggerParentSchema }).Triggers
                    //     | Where-Object name -eq $row.name, then the same over $db.Views when nothing was found.
                    List<object> found = ParentTriggers(db.Tables, parent, parentSchema, row["name"]);
                    if (found.Count == 0)
                    {
                        WriteMessage(MessageLevel.Verbose, String.Format(CultureInfo.InvariantCulture,
                            "Could not find table named {0}. Will try to find on Views.", trigger));
                        found = ParentTriggers(db.Views, parent, parentSchema, row["name"]);
                    }
                    WriteObject(Output(server, "Object", db, found));
                }
            }
        }
        else
        {
            if (LevelIn("All", "Database"))
            {
                foreach (DatabaseDdlTrigger tr in db.Triggers)
                {
                    evaluated++;
                    Count();
                    WriteMessage(MessageLevel.Verbose, String.Format(CultureInfo.InvariantCulture,
                        "Looking in trigger {0} for textBody with pattern {1} on database {2}", Text(Read(() => tr.Name)), Pattern, db));
                    if (Matches(Read(() => tr.TextBody)))
                        WriteObject(Output(server, "Database", db, new List<object> { tr }));
                }
            }

            if (LevelIn("All", "Object"))
            {
                // PS: $triggers = $db.Tables | ForEach-Object { $_.Triggers }; $triggers += $db.Views | ForEach-Object { $_.Triggers }
                List<Trigger> triggers = new();
                foreach (Table table in db.Tables)
                {
                    foreach (Trigger tr in table.Triggers)
                        triggers.Add(tr);
                }
                foreach (View view in db.Views)
                {
                    foreach (Trigger tr in view.Triggers)
                        triggers.Add(tr);
                }
                foreach (Trigger tr in triggers)
                {
                    evaluated++;
                    Count();
                    WriteMessage(MessageLevel.Verbose, String.Format(CultureInfo.InvariantCulture,
                        "Looking in trigger {0} for textBody with pattern {1} in object {2} at database {3}", Text(Read(() => tr.Name)), Pattern, Read(() => tr.Parent), db));
                    if (Matches(Read(() => tr.TextBody)))
                        WriteObject(Output(server, "Object", db, new List<object> { tr }));
                }
            }
        }

        WriteMessage(MessageLevel.Verbose, String.Format(CultureInfo.InvariantCulture,
            "Evaluated {0} triggers in {1}", _triggerCount, db));
        return evaluated;
    }

    private void Count()
    {
        _triggerCount++;
        _everyServerStCount++;
    }

    private static List<object> ParentTriggers(IEnumerable parents, object parentName, object parentSchema, object triggerName)
    {
        List<object> found = new();
        foreach (object candidate in parents)
        {
            if (!PsOps.Eq(Read(() => PsProperty.Get(candidate, "Name")), parentName) || !PsOps.Eq(Read(() => PsProperty.Get(candidate, "Schema")), parentSchema))
                continue;
            if (Read(() => PsProperty.Get(candidate, "Triggers")) is not IEnumerable triggers)
                continue;
            foreach (object tr in triggers)
            {
                if (PsOps.Eq(Read(() => PsProperty.Get(tr, "Name")), triggerName))
                    found.Add(tr);
            }
        }
        return found;
    }

    private static IEnumerable<DataRow> Rows(DataTable? table)
    {
        if (table is null)
            yield break;
        foreach (DataRow row in table.Rows)
            yield return row;
    }

    // A database or object level row from the trigger(s) Where-Object found: $tr.<Property> is $null for none, the
    // value for one, an array for several.
    private PSObject Output(Server server, string level, SmoDatabase db, List<object> found)
    {
        object? textBody = Member(found, "TextBody");
        return Output(server, level, db.Name, db.ID, Member(found, "Parent"), Member(found, "Name"), Member(found, "IsSystemObject"),
            Member(found, "CreateDate"), Member(found, "DateLastModified"), textBody,
            found.Count == 0 ? null : found.Count == 1 ? found[0] : found.ToArray());
    }

    // PS: [PSCustomObject]@{ ... } | Select-DefaultView -ExcludeProperty Trigger, TriggerFullText
    private PSObject Output(Server server, string level, object? database, object? databaseId, object? parent, object? name,
        object? isSystemObject, object? createDate, object? lastModified, object? textBody, object? trigger)
    {
        PSObject output = new();
        output.Properties.Add(new PSNoteProperty("ComputerName", Dataplat.Dbatools.Connection.SmoServerExtensions.GetComputerName(server))); // style-ok: cs-output-props the pinned [PSCustomObject] has ComputerName and SqlInstance only, no InstanceName, and its display set comes from -ExcludeProperty
        output.Properties.Add(new PSNoteProperty("SqlInstance", SqlInstanceValue(server))); // style-ok: cs-output-props the pinned SqlInstance is $server.ServiceName
        output.Properties.Add(new PSNoteProperty("TriggerLevel", level));
        output.Properties.Add(new PSNoteProperty("Database", database));
        output.Properties.Add(new PSNoteProperty("DatabaseId", databaseId));
        output.Properties.Add(new PSNoteProperty("Object", parent));
        output.Properties.Add(new PSNoteProperty("Name", name));
        output.Properties.Add(new PSNoteProperty("IsSystemObject", isSystemObject));
        output.Properties.Add(new PSNoteProperty("CreateDate", createDate));
        output.Properties.Add(new PSNoteProperty("LastModified", lastModified));
        output.Properties.Add(new PSNoteProperty("TriggerTextFound", TextFound(textBody)));
        output.Properties.Add(new PSNoteProperty("Trigger", trigger));
        output.Properties.Add(new PSNoteProperty("TriggerFullText", textBody));
        OutputHelper.SetDefaultDisplayPropertySetExcluding(output, HiddenProperties);
        return output;
    }

    private static object? Member(List<object> found, string property)
    {
        if (found.Count == 0)
            return null;
        if (found.Count == 1)
            return Read(() => PsProperty.Get(found[0], property));
        List<object?> values = new();
        foreach (object item in found)
            values.Add(Read(() => PsProperty.Get(item, property)));
        return values.ToArray();
    }

    // PS: $tr.TextBody.split($eol) | Select-String -Pattern $Pattern |
    //     ForEach-Object { "(LineNumber: $($_.LineNumber)) $($_.ToString().Trim())" }, joined with "`n".
    // Correction trigger-line-numbers: .split($eol) bound to Split(char[]) on Windows PowerShell, which cut CR and LF
    // apart and counted an empty line after every CR LF, and to Split(string) on PowerShell 7, which never cut a text
    // with LF line ends; the line numbers were wrong on both. The text is now cut at CR LF, CR and LF on both.
    private string TextFound(object? textBody)
    {
        if (textBody is not string text)
            return "";
        List<string> found = new();
        string[] lines = text.Split(LineBreaks, StringSplitOptions.None);
        for (int index = 0; index < lines.Length; index++)
        {
            if (Matches(lines[index]))
                found.Add(String.Format(CultureInfo.InvariantCulture, "(LineNumber: {0}) {1}", index + 1, lines[index].Trim()));
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

    // PS: -match and Select-String -Pattern inside the pinned try/finally: an invalid pattern ends the command.
    private bool Matches(object? value)
    {
        Regex? regex = TryRegex(out ErrorRecord? invalid);
        if (regex is null)
        {
            // caller-try: terminate -- the -match statement fault fails every row alike, so continuing emits nothing more
            ThrowTerminatingError(invalid!); // style-ok: cs-raw-streams operator fault outside Stop-Function, as in the source
        }
        return regex!.IsMatch(Text(value));
    }

    // PS: -match builds a case-insensitive Regex from $Pattern; an invalid pattern is the operator's own fault.
    private Regex? TryRegex(out ErrorRecord? invalid)
    {
        invalid = null;
        if (_regex is not null)
            return _regex;
        try
        {
            _regex = new Regex(Pattern, RegexOptions.IgnoreCase);
            return _regex;
        }
        catch (ArgumentException failure)
        {
            // PS: the -match statement fault carries the runtime's own exception (ArgumentException on .NET Framework,
            // RegexParseException on .NET), its type name as the error id, OperationStopped and no target.
            invalid = new ErrorRecord(failure, failure.GetType().ToString(), ErrorCategory.OperationStopped, null);
            return null;
        }
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
