#nullable enable

using System;
using System.Collections.Generic;
using System.Data;
using System.Globalization;
using System.Management.Automation;
using System.Text.RegularExpressions;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Common;
using Microsoft.SqlServer.Management.Smo;
using SmoDatabase = Microsoft.SqlServer.Management.Smo.Database;

namespace Dataplat.Dbatools.Commands;

// Port of public/Get-DbaLastGoodCheckDb.ps1 at refs/pins/dbatools-2026-10-22: the input dispatch, the nested Get-DbaDatabase
// selection, then per database the sysadmin check, DBCC DBINFO as sysadmin or SMO's LastGoodCheckDbTime otherwise, and the
// caller's database put back. The SQL Server 2005 branch (VersionMajor -lt 10) is not carried: the connection layer refuses
// instances older than SQL Server 2008.
/// <summary>Retrieves the last successful DBCC CHECKDB timestamp and integrity status for databases</summary>
/// <para>
/// Retrieves and compares the timestamp for the last successful DBCC CHECKDB operation along with database creation dates. This helps DBAs monitor database integrity checking compliance and identify databases that need attention.
/// </para>
/// <para>
/// The function returns comprehensive information including days since the last good CHECKDB, database creation date, current status assessment (Ok, New database not checked yet, or CheckDB should be performed), and data purity settings. Use this to quickly identify which databases are overdue for integrity checks in your maintenance routines.
/// </para>
/// <para>
/// This function supports SQL Server 2005 and higher. For SQL Server 2008 and earlier, it uses DBCC DBINFO() WITH TABLERESULTS to extract the dbi_dbccLastKnownGood field. For newer versions, it uses the LastGoodCheckDbTime property from SMO.
/// </para>
/// <para>
/// Please note that this script uses the DBCC DBINFO() WITH TABLERESULTS. DBCC DBINFO has several known weak points, such as:
/// - DBCC DBINFO is an undocumented feature/command.
/// - The LastKnowGood timestamp is updated when a DBCC CHECKFILEGROUP is performed.
/// - The LastKnowGood timestamp is updated when a DBCC CHECKDB WITH PHYSICAL_ONLY is performed.
/// - The LastKnowGood timestamp does not get updated when a database in READ_ONLY.
/// </para>
/// <para>
/// An empty ($null) LastGoodCheckDb result indicates that a good DBCC CHECKDB has never been performed.
/// </para>
/// <para>
/// SQL Server 2008R2 has a "bug" that causes each databases to possess two dbi_dbccLastKnownGood fields, instead of the normal one.
/// </para>
/// <para>
/// This script will only display the newest timestamp. If -Verbose is specified, the function will announce every time more than one dbi_dbccLastKnownGood fields is encountered.
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaLastGoodCheckDb -SqlInstance ServerA\sql987
/// </code>
/// <para>
/// Returns a custom object displaying Server, Database, DatabaseCreated, LastGoodCheckDb, DaysSinceDbCreated, DaysSinceLastGoodCheckDb, Status and DataPurityEnabled
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaLastGoodCheckDb -SqlInstance ServerA\sql987 -SqlCredential sqladmin | Format-Table -AutoSize
/// </code>
/// <para>
/// Returns a formatted table displaying Server, Database, DatabaseCreated, LastGoodCheckDb, DaysSinceDbCreated, DaysSinceLastGoodCheckDb, Status and DataPurityEnabled. Authenticates using SQL Server authentication.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaLastGoodCheckDb -SqlInstance sql2016 -ExcludeDatabase "TempDB" | Format-Table -AutoSize
/// </code>
/// <para>
/// Returns a formatted table displaying Server, Database, DatabaseCreated, LastGoodCheckDb, DaysSinceDbCreated, DaysSinceLastGoodCheckDb, Status and DataPurityEnabled. All databases except for "TempDB" will be displayed in the output.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaDatabase -SqlInstance sql2016 -Database DB1, DB2 | Get-DbaLastGoodCheckDb | Format-Table -AutoSize
/// </code>
/// <para>
/// Returns a formatted table displaying Server, Database, DatabaseCreated, LastGoodCheckDb, DaysSinceDbCreated, DaysSinceLastGoodCheckDb, Status and DataPurityEnabled. Only databases DB1 abd DB2 will be displayed in the output.
/// </para>
/// </example>
/// <list type="alertSet">
/// <item>
/// <term />
/// <description>
/// <para>
/// Tags: CHECKDB, Database, Utility
/// Author: Jakob Bindslet (jakob@bindslet.dk)
/// </para>
/// <para>
/// Website: https://dbatools.io
/// Copyright: (c) 2018 by dbatools, licensed under MIT
/// License: MIT https://opensource.org/licenses/MIT
/// </para>
/// <para>
/// Ref:
/// DBCC CHECKDB:
/// https://msdn.microsoft.com/en-us/library/ms176064.aspx
/// http://www.sqlcopilot.com/dbcc-checkdb.html
/// Data Purity:
/// http://www.sqlskills.com/blogs/paul/checkdb-from-every-angle-how-to-tell-if-data-purity-checks-will-be-run/
/// https://www.mssqltips.com/sqlservertip/1988/ensure-sql-server-data-purity-checks-are-performed/
/// </para>
/// </description>
/// </item>
/// </list>
/// <seealso href="https://dbatools.io/Get-DbaLastGoodCheckDb" />
[Cmdlet(VerbsCommon.Get, "DbaLastGoodCheckDb")]
public sealed class GetDbaLastGoodCheckDbCommand : DbaBaseCmdlet
{
    // PS: Get-DbaDatabase's two queries for SQL Server 2008 and later and for Azure. Their rows set the database order.
    private const string DatabasesQuery = "SELECT name, state, SUSER_SNAME(owner_sid) AS [Owner], is_cdc_enabled FROM sys.databases";
    private const string AzureDatabasesQuery = "SELECT db.name, db.state, dp.name AS [Owner] FROM sys.databases AS db LEFT JOIN sys.database_principals AS dp ON dp.sid = db.owner_sid";

    // Get-DbaDatabase's default -Status, any overlap sufficient. Its Azure filter does not read the status.
    private const DatabaseStatus DefaultStatus = DatabaseStatus.Normal | DatabaseStatus.Restoring |
        DatabaseStatus.RecoveryPending | DatabaseStatus.Recovering | DatabaseStatus.Suspect |
        DatabaseStatus.Offline | DatabaseStatus.Standby | DatabaseStatus.EmergencyMode;

    // PS: Get-Date '1/1/1900 12:00:00 AM', the value that stands for "never" before the two Remove-Variable calls.
    private static readonly DateTime Never = new(1900, 1, 1, 0, 0, 0);

    /// <para>
    /// The target SQL Server instance or instances. Defaults to localhost.
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
    /// Specifies which databases to check for their last good CHECKDB status. Accepts wildcards for pattern matching.
    /// When omitted, all user and system databases on the instance will be processed. Use this to focus on specific databases or groups of databases when monitoring CHECKDB compliance.
    /// </para>
    [Parameter(Position = 2)]
    public object[]? Database { get; set; }

    /// <para>
    /// Excludes specific databases from the CHECKDB status check. Commonly used to skip system databases like TempDB or databases with known maintenance schedules.
    /// Accepts wildcards and multiple database names to filter out databases that don't need regular CHECKDB monitoring.
    /// </para>
    [Parameter(Position = 3)]
    public object[]? ExcludeDatabase { get; set; }

    /// <para>
    /// Accepts database objects piped from Get-DbaDatabase, allowing for complex filtering scenarios before checking CHECKDB status.
    /// Use this when you need to apply advanced database filtering logic or when chaining multiple dbatools commands together.
    /// </para>
    [Parameter(ValueFromPipeline = true, Position = 4)]
    public object[]? InputObject { get; set; }

    // Overridden only to carry the pinned .PARAMETER EnableException help; same bare [Parameter] as the base.
    /// <para>
    /// By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
    /// This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
    /// Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.
    /// </para>
    [Parameter]
    public override SwitchParameter EnableException { get; set; }

    // PS: $inputType lives in the function scope, so a null element, whose GetType() call fails, is dispatched by the type of
    // the element read before it, in this record or an earlier one.
    private string? _inputType;

    protected override void ProcessRecord()
    {
        // PS: Test-Bound -not 'SqlInstance', 'InputObject'. Test-Bound returns $false when nothing at all is bound, so a call
        // with no parameter gives no warning and, with nothing to read, no output.
        if (MyInvocation.BoundParameters.Count > 0 && !TestBound(nameof(SqlInstance), nameof(InputObject)))
        {
            WriteMessage(MessageLevel.Warning, "You must specify either a SQL instance or supply an InputObject");
            return;
        }

        // PS: if ($SqlInstance) { $InputObject = $SqlInstance }
        object?[] inputs = Array.Empty<object?>();
        if (LanguagePrimitives.IsTrue(SqlInstance))
            inputs = SqlInstance!;
        else if (InputObject is not null)
            inputs = InputObject;

        foreach (object? element in inputs)
        {
            object? item = element is PSObject wrapped ? wrapped.BaseObject : element;
            if (item is null)
            {
                // PS: $input.GetType() on $null ends that statement; $inputType keeps the value it had.
                ReportNullElement();
            }
            else
            {
                _inputType = item.GetType().FullName;
            }

            List<SmoDatabase>? databases;
            switch (_inputType)
            {
                case "Dataplat.Dbatools.Parameter.DbaInstanceParameter":
                    WriteMessage(MessageLevel.Verbose, "Processing DbaInstanceParameter through InputObject");
                    databases = item is DbaInstanceParameter instance ? GatherDatabases(instance) : ReportBinderFault();
                    break;
                case "Microsoft.SqlServer.Management.Smo.Server":
                    WriteMessage(MessageLevel.Verbose, "Processing Server through InputObject");
                    // Correction server-input: the source passed the unbound $SqlInstance here instead of the server it was given.
                    databases = item is Server server ? GatherDatabases(new DbaInstanceParameter(server)) : ReportBinderFault();
                    break;
                case "Microsoft.SqlServer.Management.Smo.Database":
                    WriteMessage(MessageLevel.Verbose, "Processing Database through InputObject");
                    databases = item is SmoDatabase single ? new List<SmoDatabase> { single } : null;
                    break;
                default:
                    StopFunction("InputObject is not a server or database.");
                    return;
            }

            if (databases is null)
                continue;
            foreach (SmoDatabase db in databases)
                ReadDatabase(db);
        }
    }

    // PS: the InvokeMethodOnNull record of $input.GetType(), a statement fault: a plain call writes it and goes on, a caller's
    // try catches it and the command ends.
    private void ReportNullElement()
    {
        ReportFault(new ErrorRecord(new RuntimeException("You cannot call a method on a null-valued expression."), "InvokeMethodOnNull", ErrorCategory.InvalidOperation, null));
    }

    // PS: a null element dispatched as an instance or a server reaches Get-DbaDatabase -SqlInstance $null, whose binder refuses it: a statement fault
    // that ends the assignment, so $databases keeps what the element before it read (harness-edits.md, "binder fault records in every port"; probes
    // pin-lastgood-20261106, instance-null-last and server-then-null, and pin-lastgood-binder-20261106). The binder's exception type is internal, so the
    // record carries its public base and the Reason callers read. A caller try, -ErrorAction Stop and -EnableException never get here: the null
    // element's InvokeMethodOnNull record has already ended the command, so the Activity is always the nested command's.
    // Correction null-element-repeat: the element reads no database, where the pin read the previous element's databases again.
    private List<SmoDatabase>? ReportBinderFault()
    {
        ErrorRecord fault = new ErrorRecord(
            new ParameterBindingException("Cannot bind argument to parameter 'SqlInstance' because it is null."),
            "ParameterArgumentValidationErrorNullNotAllowed", ErrorCategory.InvalidData, null);
        fault.CategoryInfo.Reason = "ParameterBindingValidationException";
        fault.CategoryInfo.Activity = "Get-DbaDatabase";
        ReportFault(fault);
        return null;
    }

    // PS: the per-database try with Restore-DatabaseContext in its finally.
    private void ReadDatabase(SmoDatabase db)
    {
        Server server = db.Parent;
        ServerConnection connection = server.ConnectionContext;
        string? callerDatabase = CurrentDatabase(connection);
        try
        {
            WriteMessage(MessageLevel.Verbose, String.Format(CultureInfo.InvariantCulture, "Processing {0} on {1}.", db.Name, server.Name));

            if (IsInaccessible(db))
            {
                StopFunction(String.Format(CultureInfo.InvariantCulture, "The database {0} is not accessible. Skipping database.", db.Name), target: db, continueLoop: true);
                return;
            }

            PSObject? row;
            try
            {
                row = BuildRow(server, connection, db);
            }
            catch (StatementFaultException fault)
            {
                ReportFault(fault.Record);
                return;
            }
            WriteObject(row);
        }
        finally
        {
            RestoreDatabaseContext(connection, callerDatabase);
        }
    }

    private PSObject BuildRow(Server server, ServerConnection connection, SmoDatabase db)
    {
        bool isAzure = Regex.IsMatch(server.DatabaseEngineType.ToString(), "Azure", RegexOptions.IgnoreCase);
        bool isAdmin = false;
        if (!isAzure)
        {
            object? scalar = Call("ExecuteScalar", () => connection.ExecuteScalar("SELECT IS_SRVROLEMEMBER('sysadmin')"));
            isAdmin = LanguagePrimitives.IsTrue(scalar);
        }

        DateTime lastKnownGood;
        object? dataPurityEnabled;
        // Correction stale-dbinfo-columns: the source assigned these only as sysadmin and kept them in the function scope, so a
        // database read without sysadmin reported the CreateVersion and DbccFlags of the last one read with it.
        object? createVersion = null;
        object? dbccFlags = null;
        if (isAdmin)
        {
            string sql = "DBCC DBINFO ([" + db.Name.Replace("]", "]]") + "]) WITH TABLERESULTS";
            WriteMessage(MessageLevel.Debug, "T-SQL: " + sql);
            DataTable resultTable = QueryDatabase(db, sql);

            List<DateTime> lastKnownGoodArray = new();
            foreach (DataRow field in FieldRows(resultTable, "dbi_dbccLastKnownGood"))
                lastKnownGoodArray.Add(Cast<DateTime>(field["Value"]));
            if (lastKnownGoodArray.Count >= 2)
            {
                WriteMessage(MessageLevel.Verbose, String.Format(CultureInfo.InvariantCulture,
                    "The database {0} has {1} dbi_dbccLastKnownGood fields. This script will only use the newest.", db, lastKnownGoodArray.Count));
            }
            // PS: [datetime]$lastKnownGood = ... | Sort-Object -Descending | Select-Object -First 1; no field converts $null to DateTime's default.
            lastKnownGood = default;
            foreach (DateTime value in lastKnownGoodArray)
            {
                if (value > lastKnownGood)
                    lastKnownGood = value;
            }

            int createVersionValue = Cast<int>(FieldValue(resultTable, "dbi_createVersion"));
            int dbccFlagsValue = Cast<int>(FieldValue(resultTable, "dbi_dbccFlags"));
            createVersion = createVersionValue;
            dbccFlags = dbccFlagsValue;
            dataPurityEnabled = !(createVersionValue < 611 && dbccFlagsValue == 0);
        }
        else
        {
            lastKnownGood = Get("LastGoodCheckDbTime", () => db.LastGoodCheckDbTime);
            dataPurityEnabled = null;
        }

        DateTime createDate = Get("CreateDate", () => db.CreateDate);
        DateTime now = DateTime.Now;
        int daysSinceCheckDb = (now - lastKnownGood).Days;
        double daysSinceDbCreated = (now - createDate).TotalDays;

        string status;
        if (daysSinceCheckDb < 7)
            status = "Ok";
        else if (daysSinceDbCreated < 7)
            status = "New database, not checked yet";
        else
            status = "CheckDB should be performed";

        // PS: Remove-Variable -Name lastKnownGood, daysSinceCheckDb when it is the 1900 value: both report $null.
        bool never = lastKnownGood == Never;

        PSObject output = new();
        OutputHelper.AddInstanceProperties(output, server);
        output.Properties.Add(new PSNoteProperty("Database", db.Name));
        output.Properties.Add(new PSNoteProperty("DatabaseCreated", createDate));
        output.Properties.Add(new PSNoteProperty("LastGoodCheckDb", never ? (object?)null : lastKnownGood));
        output.Properties.Add(new PSNoteProperty("DaysSinceDbCreated", daysSinceDbCreated));
        output.Properties.Add(new PSNoteProperty("DaysSinceLastGoodCheckDb", never ? (object?)null : daysSinceCheckDb));
        output.Properties.Add(new PSNoteProperty("Status", status));
        output.Properties.Add(new PSNoteProperty("DataPurityEnabled", dataPurityEnabled));
        output.Properties.Add(new PSNoteProperty("CreateVersion", createVersion));
        output.Properties.Add(new PSNoteProperty("DbccFlags", dbccFlags));
        return output;
    }

    // PS: $resultTable | Where-Object Field -eq <name>: -eq ignores case.
    private static IEnumerable<DataRow> FieldRows(DataTable table, string name)
    {
        foreach (DataRow row in table.Rows)
        {
            if (LanguagePrimitives.Equals(row["Field"], name, true, CultureInfo.InvariantCulture))
                yield return row;
        }
    }

    // PS: ($resultTable | Where-Object Field -eq <name>).Value: one row gives its value, none gives $null.
    private static object? FieldValue(DataTable table, string name)
    {
        List<object> values = new();
        foreach (DataRow row in FieldRows(table, name))
            values.Add(row["Value"]);
        if (values.Count == 0)
            return null;
        return values.Count == 1 ? values[0] : values.ToArray();
    }

    // Accepted differences kept by the keep-going section's point 3: -EnableException stops here with this record, where the
    // pin writes it and goes on to the next database; -ErrorAction Stop has the effect PowerShell gives WriteError.
    private void ReportFault(ErrorRecord fault)
    {
        if (EnableException.ToBool())
        {
            // caller-try: terminate -- -EnableException asks for the stop
            ThrowTerminatingError(fault); // style-ok: cs-raw-streams a statement fault of the pin, outside Stop-Function
        }

        // A plain call writes the record and goes on to the next database; under a caller try the record ends the command.
        StatementFault.Surface(this, fault);
    }

    // PS: the [datetime] and [int] casts of the source; a value that does not convert ends the statement with the cast's error.
    private static T Cast<T>(object? value)
    {
        try
        {
            return LanguagePrimitives.ConvertTo<T>(value);
        }
        catch (PSInvalidCastException failure)
        {
            throw new StatementFaultException(new ErrorRecord(failure, failure.ErrorRecord.FullyQualifiedErrorId, ErrorCategory.InvalidArgument, value));
        }
    }

    // PS: a .NET method called from the source; its exception is the statement's MethodInvocationException.
    private static T Call<T>(string method, Func<T> body)
    {
        try
        {
            return body();
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            MethodInvocationException call = new(String.Format(CultureInfo.InvariantCulture,
                "Exception calling \"{0}\" with \"1\" argument(s): \"{1}\"", method, failure.Message), failure);
            throw new StatementFaultException(new ErrorRecord(call, failure.GetType().Name, ErrorCategory.NotSpecified, null));
        }
    }

    // PS: a property read from the source; a getter's exception is the statement's GetValueInvocationException.
    private static T Get<T>(string property, Func<T> body)
    {
        try
        {
            return body();
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            GetValueInvocationException read = new(String.Format(CultureInfo.InvariantCulture,
                "Exception getting \"{0}\": \"{1}\"", property, failure.Message), failure);
            throw new StatementFaultException(new ErrorRecord(read, "ExceptionWhenGetting", ErrorCategory.NotSpecified, null));
        }
    }

    // PS: $db.Query($sql), the dbatools Database.Query script method: ExecuteWithResults on the server's own connection, the
    // first table, and the previous database put back in its finally.
    private DataTable QueryDatabase(SmoDatabase db, string sql)
    {
        ServerConnection connection = db.Parent.ConnectionContext;
        string? previous = CurrentDatabase(connection);
        SetActiveConnection(connection);
        try
        {
            return db.ExecuteWithResults(sql).Tables[0];
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            MethodInvocationException call = new(String.Format(CultureInfo.InvariantCulture,
                "Exception calling \"ExecuteWithResults\" with \"1\" argument(s): \"{0}\"", failure.Message), failure);
            MethodInvocationException query = new(String.Format(CultureInfo.InvariantCulture,
                "Exception calling \"Query\" with \"1\" argument(s): \"{0}\"", call.Message), call);
            throw new StatementFaultException(new ErrorRecord(query, "ScriptMethodRuntimeException", ErrorCategory.NotSpecified, null));
        }
        finally
        {
            PutDatabaseBack(connection, previous);
        }
    }

    // PS: the script method's finally. -cne on purpose: database names follow the instance collation. A failed USE only warns,
    // through plain Write-Warning, with a Stop or Inquire preference raised to Continue for that one call.
    private void PutDatabaseBack(ServerConnection connection, string? previous)
    {
        if (String.IsNullOrEmpty(previous) || String.Equals(CurrentDatabase(connection), previous, StringComparison.Ordinal))
            return;
        try
        {
            connection.ExecuteNonQuery("USE [" + previous!.Replace("]", "]]") + "]");
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            try
            {
                WriteWarning(String.Format(CultureInfo.InvariantCulture, // style-ok: cs-raw-streams the Database.Query script method calls plain Write-Warning, not Write-Message
                    "The database context could not be restored to [{0}]: Exception calling \"ExecuteNonQuery\" with \"1\" argument(s): \"{1}\"",
                    previous, failure.Message));
            }
            catch (ActionPreferenceStopException stopped)
            {
                WriteMessage(MessageLevel.Debug, stopped.Message);
            }
        }
    }

    // PS: Restore-DatabaseContext -Server $server -Database $callerDatabase, in the per-database finally. A failed USE warns
    // through Write-Message under that function's name, with a Stop or Inquire preference raised to Continue.
    private void RestoreDatabaseContext(ServerConnection connection, string? callerDatabase)
    {
        if (String.IsNullOrEmpty(callerDatabase) || String.Equals(CurrentDatabase(connection), callerDatabase, StringComparison.Ordinal))
            return;
        try
        {
            connection.ExecuteNonQuery("USE [" + callerDatabase!.Replace("]", "]]") + "]");
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            try
            {
                WriteAttributedMessage("Restore-DatabaseContext", MessageLevel.Warning, String.Format(CultureInfo.InvariantCulture,
                    "The database context could not be restored to [{0}]: Exception calling \"ExecuteNonQuery\" with \"1\" argument(s): \"{1}\"",
                    callerDatabase, failure.Message));
            }
            catch (ActionPreferenceStopException stopped)
            {
                WriteMessage(MessageLevel.Debug, stopped.Message);
            }
        }
    }

    // PS: $connectionContext.CurrentDatabase. A getter that throws reads as $null there, so a lost connection stays the query's failure.
    private static string? CurrentDatabase(ServerConnection connection)
    {
        try
        {
            return connection.CurrentDatabase;
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            return null;
        }
    }

    // PS: $db.IsAccessible -eq $false. A getter that throws reads as $null there, and $null is not $false.
    private static bool IsInaccessible(SmoDatabase database)
    {
        try
        {
            return !database.IsAccessible;
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            return false;
        }
    }

    // PS: Get-DbaDatabase -SqlInstance $input -SqlCredential $SqlCredential -Database $Database -ExcludeDatabase $ExcludeDatabase,
    // called without -EnableException. Its connect failure (Stop-Function -Continue) and its failed name query (the Stop-Function
    // of Invoke-QueryRawDatabases) both warn under its own name, and that input then brings no database.
    private List<SmoDatabase>? GatherDatabases(DbaInstanceParameter instance)
    {
        Server server;
        try
        {
            server = ConnectNested(instance);
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            WarnNestedStopFunction("Get-DbaDatabase", "Failure", instance,
                new ErrorRecord(failure, "dbatools_Get-DbaDatabase", ErrorCategory.ConnectionError, instance), ErrorCategory.ConnectionError);
            return null;
        }

        bool isAzure = server.DatabaseEngineType == DatabaseEngineType.SqlAzureDatabase;
        List<string> scope = new();
        try
        {
            DataTable rawDatabases = server.ConnectionContext.ExecuteWithResults(isAzure ? AzureDatabasesQuery : DatabasesQuery).Tables[0];
            foreach (DataRow raw in rawDatabases.Rows)
                scope.Add((string)raw["name"]);
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            WarnNestedStopFunction("Get-DbaDatabase", "Failure", errorRecord: new ErrorRecord(failure, "dbatools_Get-DbaDatabase", ErrorCategory.NotSpecified, null));
            return null;
        }

        // PS: the Where-Object filters, by name in the order sys.databases gave; [string[]] turns each object value into text.
        // Correction database-wildcards: the pinned help documents wildcards for both filters, which the literal -in and -notin
        // never honoured. This instance's own names decide which pattern values are real names and stay literal.
        string[]? include = Database is null ? null : LanguagePrimitives.ConvertTo<string[]>(Database);
        string[]? exclude = ExcludeDatabase is null ? null : LanguagePrimitives.ConvertTo<string[]>(ExcludeDatabase);
        WildcardNameMatcher includes = WildcardNameFilter.CreateMatcher(include, true, SameName, scope);
        WildcardNameMatcher excludes = WildcardNameFilter.CreateMatcher(exclude, true, SameName, scope);
        List<SmoDatabase> found = new();
        foreach (string name in scope)
        {
            bool wanted = (!LanguagePrimitives.IsTrue(include) || includes.Matches(name))
                && (!LanguagePrimitives.IsTrue(exclude) || !excludes.Matches(name));
            SmoDatabase? candidate = wanted ? server.Databases[name] : null;
            if (candidate is not null && (isAzure || (candidate.Status & DefaultStatus) != 0))
                found.Add(candidate);
        }
        return found;
    }

    // PS: -in compares each value with the name, ignoring case.
    private static bool SameName(object value, string name)
    {
        return LanguagePrimitives.Equals(name, value, true, CultureInfo.InvariantCulture);
    }

    // PS: Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential inside Get-DbaDatabase, its messages under its own name.
    private Server ConnectNested(DbaInstanceParameter instance)
    {
        WriteAttributedMessage("Connect-DbaInstance", MessageLevel.Debug, "Starting process block");
        Server server = ConnectionService.GetServer(new SmoConnectionRequest
        {
            Instance = instance,
            SqlCredential = SqlCredential,
            BoundParameters = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "SqlInstance", "SqlCredential" },
            MessageCallback = (level, message) => WriteAttributedMessage("Connect-DbaInstance", level, message)
        });
        WriteAttributedMessage("Connect-DbaInstance", MessageLevel.Debug, "We are finished with this instance");
        SetActiveConnection(server.ConnectionContext);
        return server;
    }

    // Carries a statement fault's record out of the per-database work to the one place that reports it.
    private sealed class StatementFaultException : Exception
    {
        internal StatementFaultException(ErrorRecord record)
            : base(record.Exception.Message, record.Exception)
        {
            Record = record;
        }

        internal ErrorRecord Record { get; }
    }
}
