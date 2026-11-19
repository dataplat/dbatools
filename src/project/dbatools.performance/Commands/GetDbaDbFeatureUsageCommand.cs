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
using Microsoft.SqlServer.Management.Common;
using Microsoft.SqlServer.Management.Smo;
using SmoDatabase = Microsoft.SqlServer.Management.Smo.Database;

namespace Dataplat.Dbatools.Commands;

// Port of public/Get-DbaDbFeatureUsage.ps1 at refs/pins/dbatools-2026-10-22: the nested Get-DbaDatabase selection, then the
// raw rows of sys.dm_db_persisted_sku_features from each accessible database.
/// <summary>Identifies Enterprise-edition features currently used in databases that prevent downgrading to Standard edition</summary>
/// <para>
/// Queries the sys.dm_db_persisted_sku_features dynamic management view to identify SQL Server Enterprise features that are actively used in your databases. This is essential when planning to downgrade from Enterprise to Standard edition or migrating databases to environments with lower SQL Server editions.
/// </para>
/// <para>
/// Enterprise features like columnstore indexes, table partitioning, or transparent data encryption must be removed or disabled before a database can be successfully migrated to Standard edition. This function helps you inventory these blocking features across one or more databases so you can plan the necessary remediation steps.
/// </para>
/// <para>
/// Returns feature ID, feature name, and database information for each Enterprise feature found, making it easy to identify which databases need attention before edition changes.
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaDatabase -SqlInstance sql2008 -Database testdb, db2 | Get-DbaDbFeatureUsage
/// </code>
/// <para>
/// Shows features that are enabled in the testdb and db2 databases but
/// not supported on the all the editions of SQL Server.
/// </para>
/// </example>
/// <list type="alertSet">
/// <item>
/// <term />
/// <description>
/// <para>
/// Tags: Deprecated
/// Author: Brandon Abshire, netnerds.net
/// </para>
/// <para>
/// Website: https://dbatools.io
/// Copyright: (c) 2018 by dbatools, licensed under MIT
/// License: MIT https://opensource.org/licenses/MIT
/// </para>
/// </description>
/// </item>
/// </list>
/// <seealso href="https://dbatools.io/Get-DbaDbFeatureUsage" />
[Cmdlet(VerbsCommon.Get, "DbaDbFeatureUsage")]
public sealed class GetDbaDbFeatureUsageCommand : DbaInstanceCmdlet
{
    // PS: the begin block's query, verbatim.
    private const string FeatureUsageQuery = @"SELECT  SERVERPROPERTY('MachineName') AS ComputerName,
            ISNULL(SERVERPROPERTY('InstanceName'), 'MSSQLSERVER') AS InstanceName,
            SERVERPROPERTY('ServerName') AS SqlInstance, feature_id AS Id,
            feature_name AS Feature,  DB_NAME() AS [Database] FROM sys.dm_db_persisted_sku_features";

    // PS: Get-DbaDatabase's two queries for SQL Server 2008 and later and for Azure. Their rows set the database order.
    private const string DatabasesQuery = "SELECT name, state, SUSER_SNAME(owner_sid) AS [Owner], is_cdc_enabled FROM sys.databases";
    private const string AzureDatabasesQuery = "SELECT db.name, db.state, dp.name AS [Owner] FROM sys.databases AS db LEFT JOIN sys.database_principals AS dp ON dp.sid = db.owner_sid";

    // Get-DbaDatabase's default -Status, any overlap sufficient. Its Azure filter does not read the status.
    private const DatabaseStatus DefaultStatus = DatabaseStatus.Normal | DatabaseStatus.Restoring |
        DatabaseStatus.RecoveryPending | DatabaseStatus.Recovering | DatabaseStatus.Suspect |
        DatabaseStatus.Offline | DatabaseStatus.Standby | DatabaseStatus.EmergencyMode;

    private bool _instancesRead;

    /// <para>
    /// The target SQL Server instance
    /// </para>
    [Parameter(Position = 0)]
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
    /// Specifies which databases to scan for Enterprise edition features. Accepts wildcards for pattern matching.
    /// Use this when you need to check specific databases instead of scanning all databases on the instance.
    /// Helpful when planning edition downgrades for particular databases or troubleshooting feature usage in development environments.
    /// </para>
    [Parameter(Position = 2)]
    public string[]? Database { get; set; }

    /// <para>
    /// Excludes specific databases from the Enterprise feature scan. Accepts wildcards for pattern matching.
    /// Use this to skip system databases, read-only databases, or databases you know don't need to be downgraded.
    /// Commonly used to exclude tempdb, model, or archived databases from bulk scanning operations.
    /// </para>
    [Parameter(Position = 3)]
    public string[]? ExcludeDatabase { get; set; }

    /// <para>
    /// Accepts database objects directly from the pipeline, typically from Get-DbaDatabase output.
    /// Use this for advanced filtering scenarios or when you've already retrieved specific database objects.
    /// Allows you to chain database selection commands with feature usage checking in a single pipeline operation.
    /// </para>
    [Parameter(ValueFromPipeline = true, Position = 4)]
    public SmoDatabase[]? InputObject { get; set; }

    // Overridden only to carry the pinned .PARAMETER EnableException help; same bare [Parameter] as the base.
    /// <para>
    /// By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
    /// This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
    /// Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.
    /// </para>
    [Parameter]
    public override SwitchParameter EnableException { get; set; }

    protected override void ProcessRecord()
    {
        // PS: foreach ($instance in $SqlInstance) { $InputObject += Get-DbaDatabase ... }, built before the first database is read.
        // Correction sqlinstance-read-once: the source appended the instance databases to the rebound InputObject on every
        // piped record, repeating their rows once per record. SqlInstance is not pipeline-bound, so it is read once, after
        // the first record's piped objects.
        List<SmoDatabase?> databases = new(InputObject ?? Array.Empty<SmoDatabase>());
        if (!_instancesRead && SqlInstance is not null)
            databases.AddRange(GatherDatabases());
        _instancesRead = true;

        foreach (SmoDatabase? database in databases)
        {
            WriteMessage(MessageLevel.Verbose, String.Format(CultureInfo.InvariantCulture, "Processing {0} on {1}", database, database?.Parent?.Name));

            if (database is not null && IsInaccessible(database))
            {
                StopFunction(String.Format(CultureInfo.InvariantCulture, "The database {0} is not accessible. Skipping database.", database), continueLoop: true);
                continue;
            }

            ErrorRecord? fault = QueryDatabase(database, out DataTable? rows);
            if (fault is not null)
            {
                StopFunction("Failure", errorRecord: fault, continueLoop: true);
                continue;
            }

            foreach (DataRow row in rows!.Rows)
                WriteObject(row);
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

    // PS: Get-DbaDatabase -SqlInstance $instance -SqlCredential $SqlCredential -Database $Database -ExcludeDatabase $ExcludeDatabase.
    // -EnableException never reaches that call, so its Stop-Function warns under its own name and the next instance is read.
    private List<SmoDatabase> GatherDatabases()
    {
        List<SmoDatabase> gathered = new();
        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            Server? server = OpenServer(instance);
            if (server is not null)
                gathered.AddRange(SelectDatabases(server));
        }
        return gathered;
    }

    // PS: Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential, inside Get-DbaDatabase's own try.
    private Server? OpenServer(DbaInstanceParameter instance)
    {
        void Relay(MessageLevel level, string message) => WriteAttributedMessage("Connect-DbaInstance", level, message);

        try
        {
            Relay(MessageLevel.Debug, "Starting process block");
            Server server = ConnectionService.GetServer(new SmoConnectionRequest
            {
                Instance = instance,
                SqlCredential = SqlCredential,
                BoundParameters = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "SqlInstance", "SqlCredential" },
                MessageCallback = Relay
            });
            Relay(MessageLevel.Debug, "We are finished with this instance");
            SetActiveConnection(server.ConnectionContext);
            return server;
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            ErrorRecord record = new(failure, "dbatools_Get-DbaDatabase", ErrorCategory.ConnectionError, instance);
            WarnNestedStopFunction("Get-DbaDatabase", "Failure", instance, record, ErrorCategory.ConnectionError);
            return null;
        }
    }

    // PS: the Where-Object filters of Get-DbaDatabase, by name in the order sys.databases gave. Correction database-wildcards:
    // the pinned help documents wildcards for both filters, which the literal -in and -notin never honoured. Each instance's
    // own names decide which pattern values are real names and stay literal.
    private List<SmoDatabase> SelectDatabases(Server server)
    {
        List<SmoDatabase> selected = new();
        List<string>? names = ReadDatabaseNames(server);
        if (names is null)
            return selected;

        bool isAzure = server.DatabaseEngineType == DatabaseEngineType.SqlAzureDatabase;
        WildcardNameMatcher included = NameMatcher(Database, names);
        WildcardNameMatcher excluded = NameMatcher(ExcludeDatabase, names);
        foreach (string name in names)
        {
            if (LanguagePrimitives.IsTrue(Database) && !included.Matches(name))
                continue;
            if (LanguagePrimitives.IsTrue(ExcludeDatabase) && excluded.Matches(name))
                continue;
            SmoDatabase? database = server.Databases[name];
            if (database is not null && (isAzure || (database.Status & DefaultStatus) != 0))
                selected.Add(database);
        }
        return selected;
    }

    // PS: Invoke-QueryRawDatabases. Its Stop-Function has no -Continue, and the empty result then ends the instance.
    private List<string>? ReadDatabaseNames(Server server)
    {
        try
        {
            string query = server.DatabaseEngineType == DatabaseEngineType.SqlAzureDatabase ? AzureDatabasesQuery : DatabasesQuery;
            List<string> names = new();
            foreach (DataRow row in server.ConnectionContext.ExecuteWithResults(query).Tables[0].Rows)
                names.Add((string)row["name"]);
            return names;
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            WarnNestedStopFunction("Get-DbaDatabase", "Failure", errorRecord: new ErrorRecord(failure, "dbatools_Get-DbaDatabase", ErrorCategory.NotSpecified, null));
            return null;
        }
    }

    // PS: -in compares each value with the name, ignoring case; a pattern is tried only on a value the scope does not name.
    private static WildcardNameMatcher NameMatcher(string[]? values, List<string> scope)
    {
        return WildcardNameFilter.CreateMatcher(values, true,
            (value, name) => LanguagePrimitives.Equals(name, value, true, CultureInfo.InvariantCulture), scope);
    }

    // PS: $db.Query($sql), the dbatools Database.Query script method: ExecuteWithResults on the server's own connection, the
    // first table, and the previous database put back in its finally. Returns the record the source's catch block saw, or null.
    private ErrorRecord? QueryDatabase(SmoDatabase? database, out DataTable? rows)
    {
        rows = null;
        if (database is null)
            return new ErrorRecord(new RuntimeException("You cannot call a method on a null-valued expression."), "InvokeMethodOnNull", ErrorCategory.InvalidOperation, null);

        ServerConnection connection = database.Parent.ConnectionContext;
        string? previous = CurrentDatabase(connection);
        SetActiveConnection(connection);
        try
        {
            rows = database.ExecuteWithResults(FeatureUsageQuery).Tables[0];
            return null;
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            MethodInvocationException call = new(String.Format(CultureInfo.InvariantCulture,
                "Exception calling \"ExecuteWithResults\" with \"1\" argument(s): \"{0}\"", failure.Message), failure);
            MethodInvocationException query = new(String.Format(CultureInfo.InvariantCulture,
                "Exception calling \"Query\" with \"1\" argument(s): \"{0}\"", call.Message), call);
            return new ErrorRecord(query, "ScriptMethodRuntimeException", ErrorCategory.NotSpecified, null);
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
}
