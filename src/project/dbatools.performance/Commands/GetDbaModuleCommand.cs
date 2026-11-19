#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Data;
using System.Globalization;
using System.Management.Automation;
using System.Text;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;
using SmoDatabase = Microsoft.SqlServer.Management.Smo.Database;

namespace Dataplat.Dbatools.Commands;

/// <summary>Retrieves database modules (stored procedures, functions, views, triggers) modified after a specified date</summary>
/// <para>Queries sys.sql_modules and sys.objects to find database modules that have been modified within a specified timeframe, helping DBAs track recent code changes for troubleshooting, auditing, or deployment verification. Essential for identifying which stored procedures, functions, views, or triggers were altered during maintenance windows or after application deployments. Returns metadata including modification dates, schema names, and object types, with the actual module definition hidden by default but available when needed. Supports filtering by specific module types and can exclude system objects to focus on user-created code changes.</para>
/// <example><code>PS C:\&gt; Get-DbaModule -SqlInstance sql2008, sqlserver2012</code>
/// <para>Return all modules for servers sql2008 and sqlserver2012 sorted by Database, Modify_Date ASC.</para></example>
/// <example><code>PS C:\&gt; Get-DbaModule -SqlInstance sql2008, sqlserver2012 | Select-Object *</code>
/// <para>Shows hidden definition column (informative wall of text).</para></example>
/// <example><code>PS C:\&gt; Get-DbaModule -SqlInstance sql2008 -Database TestDB -ModifiedSince "2017-01-01 10:00:00"</code>
/// <para>Return all modules on server sql2008 for only the TestDB database with a modified date after 1 January 2017 10:00:00 AM.</para></example>
/// <example><code>PS C:\&gt; Get-DbaModule -SqlInstance sql2008 -Type View, Trigger, ScalarFunction</code>
/// <para>Return all modules on server sql2008 for all databases that are triggers, views or scalar functions.</para></example>
/// <example><code>PS C:\&gt; 'sql2008' | Get-DbaModule -Database TestDB -Type View, StoredProcedure, ScalarFunction</code>
/// <para>Return all modules on server sql2008 for only the TestDB database that are stored procedures, views or scalar functions. Input via Pipeline</para></example>
/// <example><code>PS C:\&gt; Get-DbaDatabase -SqlInstance sql2008 -ExcludeSystem | Get-DbaModule -Type View, Trigger, ScalarFunction</code>
/// <para>Return all modules on server sql2008 for all user databases that are triggers, views or scalar functions.</para></example>
/// <example><code>PS C:\&gt; Get-DbaDatabase -SqlInstance sql2008, sqlserver2012 -ExcludeUser | Get-DbaModule -Type StoredProcedure -ExcludeSystemObjects</code>
/// <para>Return all user created stored procedures in the system databases for servers sql2008 and sqlserver2012.</para></example>
/// <list type="alertSet"><item><term></term><description>
/// <para>Tags: General, Object, StoredProcedure, View, Table, Trigger Author: Brandon Abshire, netnerds.net</para>
/// <para>Website: https://dbatools.io Copyright: (c) 2018 by dbatools, licensed under MIT License: MIT https://opensource.org/licenses/MIT</para>
/// </description></item><item><term>OUTPUTS</term><description>
/// <para>PSCustomObject</para>
/// <para>Returns one object per database module (stored procedure, function, view, trigger, etc.) found in the specified databases that matches the filter criteria.</para>
/// <para>Properties: - ComputerName: The computer name of the SQL Server instance - InstanceName: The SQL Server instance name - SqlInstance: The full SQL Server instance name (computer\instance) - Database: The name of the database containing the module - Name: The name of the module object - ObjectID: The SQL Server object ID (int) - SchemaName: The name of the schema containing the module - Type: The type of module (VIEW, SQL_STORED_PROCEDURE, SQL_SCALAR_FUNCTION, SQL_TABLE_VALUED_FUNCTION, SQL_INLINE_TABLE_VALUED_FUNCTION, SQL_TRIGGER, DEFAULT_CONSTRAINT, RULE) - CreateDate: DateTime when the module was first created - ModifyDate: DateTime when the module was last modified - IsMsShipped: Boolean indicating if the module is a Microsoft-shipped system object - ExecIsStartUp: Boolean indicating if the stored procedure is configured to run at SQL Server startup (for stored procedures only) - Definition: The source code definition of the module (hidden by default, use Select-Object * to view)</para>
/// </description></item></list>
/// <seealso href="https://dbatools.io/Get-DbaModule" />
[Cmdlet(VerbsCommon.Get, "DbaModule")]
public sealed class GetDbaModuleCommand : DbaBaseCmdlet
{
/// <para>The target SQL Server instance or instances.</para>
    [Parameter(ValueFromPipeline = true, Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

/// <para>Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).</para>
/// <para>Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.</para>
/// <para>For MFA support, please use Connect-DbaInstance.</para>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

/// <para>Specifies which databases to search for modified modules. Accepts database names or wildcards for pattern matching. Use this when you need to focus on specific databases rather than scanning all databases on the instance.</para>
    [Parameter(Position = 2)]
    public object[]? Database { get; set; }

/// <para>Excludes specific databases from the module search. Useful when you want to search most databases but skip certain ones like test or archive databases. Commonly used to exclude databases under maintenance or those known to have frequent module changes.</para>
    [Parameter(Position = 3)]
    public object[]? ExcludeDatabase { get; set; }

/// <para>Returns only modules modified after this date and time. Defaults to 1900-01-01 to include all modules. Essential for tracking recent code changes after deployments, maintenance windows, or troubleshooting sessions.</para>
    [Parameter(Position = 4)]
    [PsDateTimeCast]
    public DateTime ModifiedSince { get; set; } = new DateTime(1900, 1, 1);

/// <para>Filters results to specific module types only. Valid choices include: View, TableValuedFunction, DefaultConstraint, StoredProcedure, Rule, InlineTableValuedFunction, Trigger, ScalarFunction. Use this when investigating specific types of database objects, such as finding all modified stored procedures after an application release.</para>
    [Parameter(Position = 5)]
    [ValidateSet("View", "TableValuedFunction", "DefaultConstraint", "StoredProcedure", "Rule", "InlineTableValuedFunction", "Trigger", "ScalarFunction")]
    public string[]? Type { get; set; }

/// <para>Excludes system databases (master, model, msdb, tempdb) from the search. Focus on user databases only. Recommended for routine auditing since system database changes are typically handled by SQL Server updates rather than application deployments.</para>
    [Parameter]
    public SwitchParameter ExcludeSystemDatabases { get; set; }

/// <para>Excludes Microsoft-shipped system objects from results. Shows only user-created modules. Use this to filter out built-in SQL Server objects and focus on custom business logic that your team maintains.</para>
    [Parameter]
    public SwitchParameter ExcludeSystemObjects { get; set; }

/// <para>Accepts database objects from Get-DbaDatabase for pipeline operations. Allows chaining commands together. Useful for complex filtering scenarios where you first select databases with specific criteria, then search for modules within those databases.</para>
    [Parameter(ValueFromPipeline = true, Position = 6)]
    public SmoDatabase[]? InputObject { get; set; }

/// <para>By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message. This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting. Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.</para>
    [Parameter]
    public override SwitchParameter EnableException { get; set; }

    private string _sql = "";

    protected override void BeginProcessing()
    {
        List<string> types = new();
        foreach (string type in Type ?? Array.Empty<string>())
        {
            switch (type.ToLowerInvariant())
            {
                case "view": types.Add("VIEW"); break;
                case "tablevaluedfunction": types.Add("SQL_TABLE_VALUED_FUNCTION"); break;
                case "defaultconstraint": types.Add("DEFAULT_CONSTRAINT"); break;
                case "storedprocedure": types.Add("SQL_STORED_PROCEDURE"); break;
                case "rule": types.Add("RULE"); break;
                case "inlinetablevaluedfunction": types.Add("SQL_INLINE_TABLE_VALUED_FUNCTION"); break;
                case "trigger": types.Add("SQL_TRIGGER"); break;
                case "scalarfunction": types.Add("SQL_SCALAR_FUNCTION"); break;
            }
        }
        // Correction: invariant ISO text and datetime2 preserve the caller's subsecond boundary,
        // independently of the session's date format and the catalog's datetime rounding.
        string date = ModifiedSince.ToString("yyyy-MM-ddTHH:mm:ss.fffffff", CultureInfo.InvariantCulture);
        _sql = @"SELECT DB_NAME() AS DatabaseName, so.name AS ModuleName, so.object_id,
            SCHEMA_NAME(so.schema_id) AS SchemaName, so.parent_object_id, so.type, so.type_desc,
            so.create_date, so.modify_date, so.is_ms_shipped, sm.definition,
            OBJECTPROPERTY(so.object_id, 'ExecIsStartUp') AS startup
            FROM (SELECT object_id, definition FROM sys.sql_modules
                  UNION ALL SELECT object_id, definition FROM sys.default_constraints) sm
            LEFT JOIN sys.objects so ON sm.object_id = so.object_id
            WHERE CONVERT(datetime2(3), so.modify_date) >= CONVERT(datetime2(7), '" + date.Replace("'", "''") + "', 126)";
        if (ExcludeSystemObjects) _sql += "\n AND so.is_ms_shipped = 0";
        if (LanguagePrimitives.IsTrue(Type))
        {
            List<string> literals = new();
            foreach (string type in types) literals.Add("'" + type.Replace("'", "''") + "'");
            _sql += " AND type_desc IN (" + String.Join(",", literals) + ")";
        }
        _sql += "\n ORDER BY so.modify_date";
    }

    protected override void ProcessRecord()
    {
        if (!LanguagePrimitives.IsTrue(InputObject) && !LanguagePrimitives.IsTrue(SqlInstance))
        {
            StopFunction("You must pipe in a database or specify a SqlInstance");
            return;
        }
        // Correction: each pipeline record reads only its explicit input and selected databases.
        List<SmoDatabase> databases = new();
        if (InputObject is not null) databases.AddRange(InputObject);
        if (LanguagePrimitives.IsTrue(SqlInstance))
        {
            List<string> instanceNames = new();
            foreach (DbaInstanceParameter instance in SqlInstance!) instanceNames.Add(instance.ToString());
            WriteMessage(MessageLevel.Verbose, "Creating InputObject from " + String.Join(" ", instanceNames));
            foreach (DbaInstanceParameter instance in SqlInstance!)
            {
                Server? server = Open(instance);
                if (server is null) continue;
                SetActiveConnection(server.ConnectionContext);
                foreach (SmoDatabase database in SelectDatabases(server)) databases.Add(database);
            }
        }
        foreach (SmoDatabase database in databases)
        {
            CancellationToken.ThrowIfCancellationRequested();
            if (!database.IsAccessible)
            {
                WriteMessage(MessageLevel.Warning, "Database " + database + " is not accessible. Skipping.");
                continue;
            }
            Server server = database.Parent;
            SetActiveConnection(server.ConnectionContext);
            WriteMessage(MessageLevel.Verbose, "Processing " + database + " on " + SmoServerExtensions.GetDomainInstanceName(server));
            DataTable? rows;
            try
            {
                DataSet result = database.ExecuteWithResults(_sql);
                rows = result.Tables.Count == 0 ? null : result.Tables[0];
            }
            catch (Exception failure) when (failure is not PipelineStoppedException)
            {
                StringBuilder message = new();
                for (Exception? cause = failure; cause is not null; cause = cause.InnerException) message.Append(cause.Message);
                RuntimeException thrown = new(message.ToString());
                MethodInvocationException query = new("Exception calling \"Query\" with \"2\" argument(s): \"" + message + "\"", new RuntimeException(message.ToString(), thrown));
                ErrorRecord record = new(query, "ScriptMethodRuntimeException", ErrorCategory.NotSpecified, null);
                if (EnableException)
                    // caller-try: terminate -- EnableException requests a stop at the query statement fault.
                    ThrowTerminatingError(record); // style-ok: cs-raw-streams pinned statement fault outside Stop-Function
                StatementFault.Surface(this, record);
                continue;
            }
            if (rows is null) continue;
            foreach (DataRow row in rows.Rows)
            {
                PSObject output = new();
                OutputHelper.AddInstanceProperties(output, server);
                string[] names = { "Database", "Name", "ObjectID", "SchemaName", "Type", "CreateDate", "ModifyDate", "IsMsShipped", "ExecIsStartUp", "Definition" };
                string[] columns = { "DatabaseName", "ModuleName", "object_id", "SchemaName", "type_desc", "create_date", "modify_date", "is_ms_shipped", "startup", "definition" };
                for (int index = 0; index < names.Length; index++)
                    output.Properties.Add(new PSNoteProperty(names[index], row[columns[index]]));
                OutputHelper.SetDefaultDisplayPropertySetExcluding(output, new[] { "Definition" });
                WriteObject(output);
            }
        }
    }

    private IEnumerable<SmoDatabase> SelectDatabases(Server server)
    {
        string[]? include = Database is null ? null : (string[])LanguagePrimitives.ConvertTo(Database, typeof(string[]), CultureInfo.InvariantCulture);
        string[]? exclude = ExcludeDatabase is null ? null : (string[])LanguagePrimitives.ConvertTo(ExcludeDatabase, typeof(string[]), CultureInfo.InvariantCulture);
        List<string> scope = new();
        foreach (SmoDatabase database in server.Databases) scope.Add(database.Name);
        // Correction: Database documents patterns; ExcludeDatabase retains its literal semantics.
        WildcardNameMatcher matcher = WildcardNameFilter.CreateMatcher(include, true,
            (value, name) => LanguagePrimitives.Equals(name, value, true, CultureInfo.InvariantCulture), scope);
        foreach (SmoDatabase database in server.Databases)
        {
            if (LanguagePrimitives.IsTrue(include) && !matcher.Matches(database.Name)) continue;
            if (LanguagePrimitives.IsTrue(exclude) && PsOps.In(database.Name, exclude)) continue;
            if (ExcludeSystemDatabases && database.IsSystemObject) continue;
            DatabaseStatus accepted = DatabaseStatus.Normal | DatabaseStatus.Restoring | DatabaseStatus.RecoveryPending |
                DatabaseStatus.Recovering | DatabaseStatus.Suspect | DatabaseStatus.Offline | DatabaseStatus.Standby | DatabaseStatus.EmergencyMode;
            if ((database.Status & accepted) != 0) yield return database;
        }
    }

    private Server? Open(DbaInstanceParameter instance)
    {
        try
        {
            WriteAttributedMessage("Connect-DbaInstance", MessageLevel.Debug, "Starting process block");
            Server server = ConnectionService.GetServer(new SmoConnectionRequest
            {
                Instance = instance, SqlCredential = SqlCredential,
                BoundParameters = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "SqlInstance", "SqlCredential" },
                MessageCallback = (level, message) => WriteAttributedMessage("Connect-DbaInstance", level, message)
            });
            WriteAttributedMessage("Connect-DbaInstance", MessageLevel.Debug, "We are finished with this instance");
            return server;
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            // The pin does not forward EnableException into Get-DbaDatabase.
            MessageService.MessageRequest request = new()
            {
                FunctionName = "Get-DbaDatabase", ModuleName = "dbatools", Level = MessageLevel.Warning,
                Message = "Failure", EnableException = false, FromStopFunction = true,
                File = MyInvocation.ScriptName, Line = MyInvocation.ScriptLineNumber
            };
            object target = MessageService.CollapseTarget(MessageService.ResolveTarget(this, request, instance));
            Exception transformed = MessageService.ResolveException(this, request, failure);
            ErrorRecord input = new(transformed, "dbatools_Get-DbaDatabase", ErrorCategory.ConnectionError, target);
            ErrorRecord record = new(new Exception(MessageService.GetErrorMessage(input), transformed),
                "dbatools_Get-DbaDatabase", ErrorCategory.ConnectionError, target);
            request.Target = target;
            request.ErrorRecord = new[] { record };
            MessageService.Write(this, request);
            if (SessionState.PSVariable.GetValue("global:Error") is ArrayList errors) errors.Insert(0, record);
            return null;
        }
    }
}
