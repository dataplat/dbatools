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
using SmoDatabase = Microsoft.SqlServer.Management.Smo.Database;
using SmoView = Microsoft.SqlServer.Management.Smo.View;

namespace Dataplat.Dbatools.Commands;

// Port of public/Get-DbaDbView.ps1 at refs/pins/dbatools-2026-10-22: the views of each database Get-DbaDatabase selects, or of each database given to -InputObject.
// Expected values as the pin measured on both editions: evidence/pin-view-20261104.txt, whose case names the comments below use.
/// <summary>Retrieves SQL Server database views with metadata for documentation and analysis.</summary>
/// <para>
/// Retrieves all database views from SQL Server instances along with their schema, creation dates, and modification timestamps. This helps DBAs document database architecture, analyze view dependencies, and audit database objects across multiple servers and databases. The function excludes system views by default when requested, making it useful for focusing on custom business logic views.
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaDbView -SqlInstance sql2016
/// </code>
/// <para>
/// Gets all database views
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaDbView -SqlInstance Server1 -Database db1
/// </code>
/// <para>
/// Gets the views for the db1 database
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaDbView -SqlInstance Server1 -ExcludeDatabase db1
/// </code>
/// <para>
/// Gets the views for all databases except db1
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaDbView -SqlInstance Server1 -ExcludeSystemView
/// </code>
/// <para>
/// Gets the views for all databases that are not system objects (there can be 400+ system views in each DB)
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; 'Sql1','Sql2/sqlexpress' | Get-DbaDbView
/// </code>
/// <para>
/// Gets the views for the databases on Sql1 and Sql2/sqlexpress
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaDatabase -SqlInstance Server1 -ExcludeSystem | Get-DbaDbView
/// </code>
/// <para>
/// Pipe the databases from Get-DbaDatabase into Get-DbaDbView
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaDbView -SqlInstance Server1 -Database db1 -View vw1
/// </code>
/// <para>
/// Gets the view vw1 for the db1 database
/// </para>
/// </example>
/// <list type="alertSet">
/// <item>
/// <term />
/// <description>
/// <para>
/// Tags: View, Database
/// Author: Klaas Vandenberghe (@PowerDbaKlaas)
/// </para>
/// <para>
/// Website: https://dbatools.io
/// Copyright: (c) 2018 by dbatools, licensed under MIT
/// License: MIT https://opensource.org/licenses/MIT
/// </para>
/// </description>
/// </item>
/// </list>
/// <seealso href="https://dbatools.io/Get-DbaDbView" />
[Cmdlet(VerbsCommon.Get, "DbaDbView")]
public sealed class GetDbaDbViewCommand : DbaBaseCmdlet
{
    private const string DatabaseCommand = "Get-DbaDatabase";
    private const string RawDatabasesCommand = "Invoke-QueryRawDatabases";

    // PS: Invoke-QueryRawDatabases, whose text keeps the rows in the order the pin reads them.
    private const string InstanceDatabasesQuery = "SELECT name, state, SUSER_SNAME(owner_sid) AS [Owner], is_cdc_enabled FROM sys.databases";
    private const string AzureDatabasesQuery = "SELECT db.name, db.state, dp.name AS [Owner] FROM sys.databases AS db LEFT JOIN sys.database_principals AS dp ON dp.sid = db.owner_sid";

    /// <para>
    /// The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.
    /// </para>
    [Parameter(ValueFromPipeline = true, Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

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
    public PSCredential? SqlCredential { get; set; }

    /// <para>
    /// Specifies which databases to search for views. Use this when you need to focus on specific databases instead of scanning all databases on the instance.
    /// </para>
    [Parameter(Position = 2)]
    public object[]? Database { get; set; }

    /// <para>
    /// Specifies databases to skip when retrieving views. Useful when you want results from most databases but need to exclude specific ones like test or staging databases.
    /// </para>
    [Parameter(Position = 3)]
    public object[]? ExcludeDatabase { get; set; }

    /// <para>
    /// Excludes SQL Server system views from results to focus only on user-created views. Essential when documenting custom application views since each database can contain 400+ system views that clutter output.
    /// </para>
    [Parameter]
    public SwitchParameter ExcludeSystemView { get; set; }

    /// <para>
    /// Specifies specific view names to retrieve instead of returning all views. Supports three-part naming (database.schema.view) to target views across different databases and schemas in a single query.
    /// </para>
    [Parameter(Position = 4)]
    [PsStringArrayCast]
    public string[]? View { get; set; }

    /// <para>
    /// Filters results to views within specific schemas only. Useful for organizing output when databases have views spread across multiple schemas like dbo, reporting, or application-specific schemas.
    /// </para>
    [Parameter(Position = 5)]
    [PsStringArrayCast]
    public string[]? Schema { get; set; }

    /// <para>
    /// Accepts database objects from Get-DbaDatabase through the pipeline. Allows you to filter databases first with Get-DbaDatabase then retrieve views from only those selected databases.
    /// </para>
    [Parameter(ValueFromPipeline = true, Position = 6)]
    public SmoDatabase[]? InputObject { get; set; }

    // Overridden only to carry the pinned .PARAMETER EnableException help; same bare [Parameter] as the base.
    /// <para>
    /// By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
    /// This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
    /// Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.
    /// </para>
    [Parameter]
    public override SwitchParameter EnableException { get; set; }

    // PS: $fqtns; null when -View reads as false, so that every view of a database is read.
    private List<ViewName>? _names;

    private sealed class ViewName
    {
        internal ViewName(string? database, string? schema, string? name)
        {
            Database = database;
            Schema = schema;
            Name = name;
        }

        internal string? Database { get; }

        internal string? Schema { get; }

        internal string? Name { get; }
    }

    protected override void BeginProcessing()
    {
        if (!LanguagePrimitives.IsTrue(View))
            return;

        List<ViewName> names = new();
        foreach (string value in View!)
        {
            // PS: Get-ObjectNameParts' Parsed: a one, two or three part name. The shared parser leaves the object part null for any
            // other name, and only then.
            ObjectNameParser.Split(value, out string? database, out string? schema, out string? name);
            if (name is null)
            {
                // PS: the message names $t, which holds nothing in this function, so the value reads as empty (view-bad-four-parts); message text stays. Disclosed in the corrections record.
                WriteMessage(MessageLevel.Warning, "Please check you are using proper three-part names. If your search value contains special characters you must use [ ] to wrap the name. The value  could not be parsed as a valid name.");
                continue;
            }
            names.Add(new ViewName(database, schema, name));
        }

        if (names.Count == 0)
        {
            StopFunction("No Valid View specified");
            return;
        }
        _names = names;
    }

    protected override void ProcessRecord()
    {
        if (Interrupted)
            return;

        if (TestBound(nameof(SqlInstance)))
            ReadInputObject();

        foreach (SmoDatabase? database in InputObject ?? Array.Empty<SmoDatabase>())
            WriteViews(database);
    }

    // PS: $InputObject = Get-DbaDatabase -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database -ExcludeDatabase $ExcludeDatabase, which gets no -EnableException.
    // A binder fault leaves $InputObject as it was (instance-then-input-piped). Test-Bound stays true on a later pipeline record, whose -SqlInstance is then null, as the binder restores it.
    private void ReadInputObject()
    {
        if (SqlInstance is null || Array.Exists(SqlInstance, instance => instance is null))
        {
            ReportBindingFault("ParameterArgumentValidationErrorNullNotAllowed", "null");
            return;
        }
        if (SqlInstance.Length == 0)
        {
            ReportBindingFault("ParameterArgumentValidationErrorEmptyArrayNotAllowed", "an empty array");
            return;
        }

        string[]? included = ToNames(Database);
        string[]? excluded = ToNames(ExcludeDatabase);
        List<SmoDatabase> read = new();
        foreach (DbaInstanceParameter instance in SqlInstance)
            read.AddRange(ReadInstance(instance, included, excluded));
        InputObject = read.ToArray();
    }

    // PS: the [string[]] parameters of Get-DbaDatabase take these [object[]] values, so a null element reads as "" and an object as its text (database-null-element).
    private static string[]? ToNames(object[]? values)
    {
        return values is null ? null : (string[])LanguagePrimitives.ConvertTo(values, typeof(string[]), CultureInfo.InvariantCulture);
    }

    // The help documents no wildcard for either filter (wildcard-database, wildcard-exclude-database). The helper keeps SMO's sorted order; the pin's is that of the rows of sys.databases
    // (instance-wide, azure-by-name), so they order what it gathered.
    private List<SmoDatabase> ReadInstance(DbaInstanceParameter instance, string[]? included, string[]? excluded)
    {
        List<SmoDatabase> ordered = new();
        Server? connected = null;
        List<SmoDatabase> gathered;
        try
        {
            gathered = NativeDatabaseSelection.GatherMatching(this, new[] { instance }, SqlCredential, included, false, excluded, false, server =>
            {
                connected = server;
                SetActiveConnection(server.ConnectionContext);
            }, () => false);
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            // PS: its catch around $server.Databases writes this line and falls back to the indexer; no fixture reaches it. Disclosed in the corrections record, raw-databases-untested.
            WriteAttributedMessage(DatabaseCommand, MessageLevel.Verbose, "Failure: " + EnumerationFault(failure).Exception.Message);
            return ordered;
        }

        if (connected is null)
            return ordered;

        DataTable? rows = ReadDatabaseRows(connected);
        if (rows is null)
            return ordered;

        foreach (DataRow row in rows.Rows)
        {
            string name = Convert.ToString(row["name"], CultureInfo.InvariantCulture) ?? String.Empty;
            foreach (SmoDatabase database in gathered)
            {
                if (String.Equals(database.Name, name, StringComparison.Ordinal))
                    ordered.Add(database);
            }
        }
        return ordered;
    }

    // PS: Invoke-QueryRawDatabases. Its Stop-Function has no -Continue and runs without -EnableException here, so it only warns, whatever this command's switch says, and the instance
    // then has no database. Every login may read sys.databases, so no native test reaches it; disclosed in the corrections record, raw-databases-untested.
    private DataTable? ReadDatabaseRows(Server server)
    {
        try
        {
            return server.ConnectionContext.ExecuteWithResults(SmoServerExtensions.GetIsAzure(server) ? AzureDatabasesQuery : InstanceDatabasesQuery).Tables[0];
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            ErrorRecord record = new(failure, "dbatools_" + RawDatabasesCommand, ErrorCategory.NotSpecified, null);
            MessageService.Write(this, new MessageService.MessageRequest
            {
                FunctionName = RawDatabasesCommand, ModuleName = "dbatools", Level = MessageLevel.Warning,
                Message = "Failure | " + MessageService.GetErrorMessage(record), EnableException = false,
                File = MyInvocation.ScriptName, Line = MyInvocation.ScriptLineNumber
            });
            return null;
        }
    }

    private void WriteViews(SmoDatabase? database)
    {
        string shown = Convert.ToString(database, CultureInfo.InvariantCulture) ?? String.Empty;
        string instanceName = database is null ? String.Empty : SmoServerExtensions.GetDomainInstanceName(database.Parent);
        WriteMessage(MessageLevel.Verbose, "processing " + shown);
        ClearAndInitialize(database);

        // PS: $views; null while it is still the database's collection, which each statement over it enumerates again.
        List<SmoView>? views = null;
        if (_names is not null)
        {
            views = new List<SmoView>();
            foreach (ViewName name in _names)
            {
                // PS: if ($fqtn.Database) { if ($fqtn.Database -ne $db.Name) { continue } }
                if (!String.IsNullOrEmpty(name.Database) && !IsSame(name.Database, database?.Name))
                    continue;

                // Correction stale-view-row: a fault leaves the pin's $vw as the last database's view, which it then writes under this database's name (held-view).
                List<SmoView> found = ReadNamed(database, name) ?? new List<SmoView>();
                if (found.Count == 0)
                    WriteMessage(MessageLevel.Verbose, String.Format(CultureInfo.InvariantCulture, "Could not find view {0} in {1} on {2}", name.Name, shown, instanceName));
                views.AddRange(found);
            }
        }

        if (database is null || !ReadsAccessible(database))
        {
            WriteMessage(MessageLevel.Warning, String.Format(CultureInfo.InvariantCulture, "Database {0} is not accessible. Skipping", shown));
            return;
        }

        // PS: if (-not $views). The collection is not a list, so it reads as true however many views it holds; only the list -View builds can read as false (view-absent).
        if (views is not null && views.Count == 0)
        {
            WriteMessage(MessageLevel.Verbose, String.Format(CultureInfo.InvariantCulture, "No views exist in the {0} database on {1}", shown, instanceName), database);
            return;
        }

        if (LanguagePrimitives.IsTrue(Schema))
            views = Filter(database, views, view => IsNamed(Schema, view.Schema));

        // Correction exclude-system-false: the pin's Test-Bound reads -ExcludeSystemView:$false as the switch (exclude-system-false), so asking to keep the system views drops them.
        if (ExcludeSystemView.ToBool())
            views = Filter(database, views, view => !view.IsSystemObject);

        foreach (SmoView view in views ?? ReadViews(database) ?? new List<SmoView>())
            WriteObject(Decorate(database, view));
    }

    // PS: $db.Views.ClearAndInitialize('', [string[]]('Name', 'Schema', 'IsSystemObject', 'CreateDate', 'DateLastModified')) in its try, with a verbose line on failure.
    private void ClearAndInitialize(SmoDatabase? database)
    {
        if (database is null)
        {
            WriteMessage(MessageLevel.Verbose, "ClearAndInitialize failed: You cannot call a method on a null-valued expression.");
            return;
        }
        try
        {
            database.Views.ClearAndInitialize(String.Empty, new[] { "Name", "Schema", "IsSystemObject", "CreateDate", "DateLastModified" });
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            WriteMessage(MessageLevel.Verbose, String.Format(CultureInfo.InvariantCulture, "ClearAndInitialize failed: Exception calling \"ClearAndInitialize\" with \"2\" argument(s): \"{0}\"", failure.Message));
        }
    }

    // PS: $db.Views | Where-Object { $_.Name -in $fqtn.View -and $fqtn.Schema -in ($_.Schema, $null) -and $fqtn.Database -in ($_.Parent.Name, $null) }. On a null database it pipes a null and keeps nothing.
    private List<SmoView>? ReadNamed(SmoDatabase? database, ViewName name)
    {
        if (database is null)
            return new List<SmoView>();

        return Filter(database, null, view => IsSame(name.Name, view.Name)
            && (name.Schema is null || IsSame(name.Schema, view.Schema))
            && (name.Database is null || IsSame(name.Database, database.Name)));
    }

    // PS: $views = $views | Where-Object ... A fault leaves $views the collection, so the next statement enumerates it again, and each writes a record (held-schema-and-exclude).
    private List<SmoView>? Filter(SmoDatabase database, List<SmoView>? views, Func<SmoView, bool> keep)
    {
        List<SmoView>? read = views ?? ReadViews(database);
        if (read is null)
            return null;

        List<SmoView> kept = new();
        foreach (SmoView view in read)
        {
            if (Keeps(keep, view))
                kept.Add(view);
        }
        return kept;
    }

    // A getter that fails reads as $null, which none of these comparisons keeps.
    private static bool Keeps(Func<SmoView, bool> keep, SmoView view)
    {
        try
        {
            return keep(view);
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            return false;
        }
    }

    // PS: -in over a [string[]], exact and in any case: no wildcards (schema-wildcard).
    private static bool IsNamed(string[]? names, string value)
    {
        foreach (string name in names ?? Array.Empty<string>())
        {
            if (IsSame(name, value))
                return true;
        }
        return false;
    }

    private static bool IsSame(string? left, string? right)
    {
        return LanguagePrimitives.Equals(left, right, true, CultureInfo.InvariantCulture);
    }

    private static bool ReadsAccessible(SmoDatabase database)
    {
        try
        {
            return database.IsAccessible;
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            return false;
        }
    }

    // A pipeline or foreach over $db.Views; SMO keeps what it read, so the fault comes only from a read that has not yet worked (held-plain, held-view, offline-view, low-no-user-view).
    private List<SmoView>? ReadViews(SmoDatabase database)
    {
        try
        {
            List<SmoView> views = new();
            foreach (SmoView view in database.Views)
                views.Add(view);
            return views;
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            SurfaceFault(EnumerationFault(failure));
            return null;
        }
    }

    // Add-Member -Force and Select-DefaultView.
    private static PSObject Decorate(SmoDatabase database, SmoView view)
    {
        PSObject output = PSObject.AsPSObject(view);
        foreach (string name in new[] { "ComputerName", "InstanceName", "SqlInstance", "Database" })
            output.Properties.Remove(name);
        OutputHelper.AddInstanceProperties(output, database.Parent);
        output.Properties.Add(new PSNoteProperty("Database", database.Name));
        OutputHelper.SetDefaultDisplayPropertySet(output, "ComputerName", "InstanceName", "SqlInstance", "Database", "Schema", "CreateDate", "DateLastModified", "Name");
        return output;
    }

    // PS: the binder of the nested Get-DbaDatabase refuses -SqlInstance (instance-null-plain, instance-empty-plain, instance-null-element-plain, pipe-null), as this command's own does not.
    // Binder section points 1 to 3 of harness-edits.md: the record the pin gives, on the public ParameterBindingException.
    private void ReportBindingFault(string errorId, string problem)
    {
        ErrorRecord fault = new(new ParameterBindingException(String.Format(CultureInfo.InvariantCulture, "Cannot bind argument to parameter 'SqlInstance' because it is {0}.", problem)),
            errorId, ErrorCategory.InvalidData, null);
        // The binder's own type is internal, so the record carries its public base and keeps the reason callers classify by.
        fault.CategoryInfo.Reason = "ParameterBindingValidationException";
        // The pin's activity follows its id suffix: the nested command when the caller has no try (instance-null-plain). Under -ErrorAction Stop or a caller's try the fault leaves
        // through this command, and the engine's default activity, this cmdlet's name, is already the pin's (instance-null-stop, instance-null-try).
        bool stopAsked = MyInvocation.BoundParameters.TryGetValue("ErrorAction", out object? errorAction)
            && String.Equals(LanguagePrimitives.ConvertTo<string>(errorAction), "Stop", StringComparison.OrdinalIgnoreCase);
        if (!stopAsked && !StatementFault.CallerHasEnclosingTry(this))
            fault.CategoryInfo.Activity = DatabaseCommand;
        SurfaceFault(fault);
    }

    // Accepted differences from the pin at these statements (harness-edits.md, keep-going, binder and StatementFault sections; "Script-scope preferences and the one-line connect warning",
    // point 1). -EnableException stops here with the record; the pin ignores the switch at them and goes on (held-ee, instance-null-ee). $ErrorActionPreference = "Stop" set in the
    // caller's scope or at a script's top stops at this WriteError, and "SilentlyContinue" there silences the record, as for any compiled command; the pin ignores both there.
    private void SurfaceFault(ErrorRecord fault)
    {
        if (EnableException.ToBool())
        {
            // caller-try: terminate -- -EnableException asks for the stop
            ThrowTerminatingError(fault); // style-ok: cs-raw-streams a statement fault of the pin, outside Stop-Function
        }

        // A plain call writes the record and goes on, as the pin does; under a caller's try the record stops the command, as the fault stops the pin's statement.
        StatementFault.Surface(this, fault);
    }

    // PS: the engine's record for a collection that faults when a pipeline or foreach enumerates it (held-plain).
    private static ErrorRecord EnumerationFault(Exception failure)
    {
        return new ErrorRecord(new ExtendedTypeSystemException(String.Format(CultureInfo.InvariantCulture,
            "The following exception occurred while trying to enumerate the collection: \"{0}\".", failure.Message), failure),
            "ExceptionInGetEnumerator", ErrorCategory.NotSpecified, null);
    }
}
