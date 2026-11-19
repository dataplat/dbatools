#nullable enable

using System;
using System.Collections.Generic;
using System.Data;
using System.Globalization;
using System.Management.Automation;
using System.Text;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Common;
using Microsoft.SqlServer.Management.Smo;
using SmoDatabase = Microsoft.SqlServer.Management.Smo.Database;

namespace Dataplat.Dbatools.Commands;

/// <summary>Retrieves explicit and implicit permissions across SQL Server instances and databases for security auditing</summary>
/// <para>Retrieves comprehensive permission information from SQL Server instances and databases, including both explicit permissions and implicit permissions from fixed roles.</para>
/// <para>This function queries sys.server_permissions and sys.database_permissions to capture all granted, denied, and revoked permissions across server and database levels. Perfect for security audits, compliance reporting, troubleshooting access issues, and planning permission migrations between environments.</para>
/// <para>The output includes permission state (GRANT/DENY/REVOKE), permission type (SELECT, CONNECT, EXECUTE, etc.), grantee information, and the specific securable being protected. Also captures implicit CONTROL permissions for dbo users, db_owner role members, and schema owners that aren't explicitly stored in system tables. Each result includes ready-to-use GRANT and REVOKE statements for easy permission replication or cleanup.</para>
/// <para>Permissions link principals (logins, users, roles) to securables (servers, databases, schemas, objects). Principals exist at Windows, instance, and database levels, while securables exist at instance and database levels.</para>
/// <para>See https://msdn.microsoft.com/en-us/library/ms191291.aspx for more information about SQL Server permissions</para>
[Cmdlet(VerbsCommon.Get, "DbaPermission")]
[OutputType(typeof(DataRow))]
public sealed partial class GetDbaPermissionCommand : DbaInstanceCmdlet
{
    /// <para>The target SQL Server instance or instances. Defaults to localhost.</para>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public override DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <para>Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).</para>
    /// <para>Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.</para>
    /// <para>For MFA support, please use Connect-DbaInstance.</para>
    [Parameter(Position = 1)]
    public override PSCredential? SqlCredential { get; set; }

    /// <para>Specifies which databases to analyze for permissions. Accepts wildcards and multiple database names. When omitted, all accessible databases on the instance are processed, which is useful for comprehensive security audits.</para>
    [Parameter(Position = 2)]
    public object[]? Database { get; set; }

    /// <para>Excludes specific databases from permission analysis. Accepts wildcards and multiple database names. Commonly used to skip system databases like TempDB or exclude sensitive databases from security reports.</para>
    [Parameter(Position = 3)]
    public object[]? ExcludeDatabase { get; set; }

    /// <para>Includes server-level permissions in the output, such as CONTROL SERVER, VIEW SERVER STATE, and fixed server roles like sysadmin. Essential for complete security audits as it captures instance-wide permissions that affect all databases.</para>
    [Parameter]
    public SwitchParameter IncludeServerLevel { get; set; }

    /// <para>Excludes permissions on system objects like system tables, views, and stored procedures from the output. Use this when focusing on user-created objects to reduce noise in permission reports and compliance audits.</para>
    [Parameter]
    public SwitchParameter ExcludeSystemObjects { get; set; }

    /// <para>By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message. This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting. Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.</para>
    [Parameter]
    public override SwitchParameter EnableException { get; set; }

    protected override void ProcessRecord()
    {
        string filter = ExcludeSystemObjects ? "WHERE major_id > 0 " : String.Empty;
        string serverSql = ServerPermissionSql.Replace("{SystemFilter}", filter);
        string databaseSql = DatabasePermissionSql.Replace("{SystemFilter}", filter);
        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            Server? server = ConnectInstance(instance, minimumVersion: 9);
            if (server is null) continue;

            bool azure = server.DatabaseEngineType == DatabaseEngineType.SqlAzureDatabase;
            if (IncludeServerLevel)
            {
                if (azure)
                {
                    WriteMessage(MessageLevel.Warning, "Server-level permissions are not supported on Azure SQL Database. Skipping -IncludeServerLevel.");
                }
                else
                {
                    WriteMessage(MessageLevel.Debug, "T-SQL: " + serverSql);
                    ErrorRecord? serverFault = Query(server, null, serverSql, out DataTable? serverRows);
                    if (serverFault is not null)
                        SurfaceFault(serverFault);
                    else
                        EmitRows(serverRows);
                }
            }

            string currentSql = azure
                ? databaseSql.Replace("SUSER_SNAME(owner_sid)", "(SELECT TOP 1 name FROM sys.database_principals WHERE sid = owner_sid)")
                : databaseSql;
            List<SmoDatabase>? databases = null;
            List<string>? databaseNames = null;
            if (LanguagePrimitives.IsTrue(Database))
                databases = FilterDatabases(server, databases, Database, false, ref databaseNames);
            if (LanguagePrimitives.IsTrue(ExcludeDatabase))
                databases = FilterDatabases(server, databases, ExcludeDatabase, true, ref databaseNames);

            string? callerDatabase = ReadCurrentDatabase(server.ConnectionContext);
            try
            {
                foreach (SmoDatabase database in databases ?? ReadDatabases(server) ?? new List<SmoDatabase>())
                {
                    WriteMessage(MessageLevel.Verbose, String.Format(CultureInfo.InvariantCulture, "Processing {0} on {1}.", database, instance));
                    if (!database.IsAccessible)
                    {
                        WriteMessage(MessageLevel.Warning, String.Format(CultureInfo.InvariantCulture, "The database {0} is not accessible. Skipping database.", database));
                        continue;
                    }

                    WriteMessage(MessageLevel.Debug, "T-SQL: " + currentSql);
                    ErrorRecord? databaseFault = Query(server, database, currentSql, out DataTable? databaseRows);
                    if (databaseFault is not null)
                    {
                        StopFunction(String.Format(CultureInfo.InvariantCulture, "Failure executing against {0} on {1}", database.Name, instance), errorRecord: databaseFault, continueLoop: true);
                        continue;
                    }
                    EmitRows(databaseRows);
                }
            }
            finally
            {
                RestoreContext(server.ConnectionContext, callerDatabase, false);
            }
        }
    }

    private static WildcardNameMatcher NameMatcher(object[]? values, List<string> scope)
    {
        return WildcardNameFilter.CreateMatcher(values, true,
            (value, name) => LanguagePrimitives.Equals(name, value, true, CultureInfo.InvariantCulture), scope);
    }

    // A failed pinned filter assignment leaves the SMO collection in $dbs. The next filter or
    // foreach genuinely enumerates it again, producing the measured second record for -Database.
    private List<SmoDatabase>? FilterDatabases(Server server, List<SmoDatabase>? databases,
        object[]? values, bool exclude, ref List<string>? scope)
    {
        List<SmoDatabase>? read = databases ?? ReadDatabases(server);
        if (read is null) return null;
        if (scope is null)
        {
            scope = new List<string>();
            foreach (SmoDatabase database in read) scope.Add(database.Name);
        }
        WildcardNameMatcher matcher = NameMatcher(values, scope);
        List<SmoDatabase> selected = new();
        foreach (SmoDatabase database in read)
            if (matcher.Matches(database.Name) != exclude) selected.Add(database);
        return selected;
    }

    private List<SmoDatabase>? ReadDatabases(Server server)
    {
        List<SmoDatabase> databases = new();
        ErrorRecord fault;
        try
        {
            foreach (SmoDatabase database in server.Databases) databases.Add(database);
            return databases;
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            fault = new ErrorRecord(new ExtendedTypeSystemException(String.Format(CultureInfo.InvariantCulture,
                "The following exception occurred while trying to enumerate the collection: \"{0}\".", failure.Message), failure),
                "ExceptionInGetEnumerator", ErrorCategory.NotSpecified, null);
        }
        SurfaceFault(fault);
        return null;
    }

    private void SurfaceFault(ErrorRecord fault)
    {
        if (EnableException)
        {
            // caller-try: terminate -- the installed caller-try contract requires the explicit EnableException stop.
            ThrowTerminatingError(fault); // style-ok: cs-raw-streams preserve the causal statement fault outside Stop-Function
        }
        StatementFault.Surface(this, fault);
    }

    private void EmitRows(DataTable? table)
    {
        if (table is null) return;
        foreach (DataRow row in table.Rows) WriteObject(row);
    }

    // The two pinned Query adapters have different exception chains. Database.Query also restores
    // its caller's database before its result is emitted; the outer finally covers SMO enumeration.
    private ErrorRecord? Query(Server server, SmoDatabase? database, string sql, out DataTable? table)
    {
        table = null;
        ServerConnection connection = server.ConnectionContext;
        string? previous = database is null ? null : ReadCurrentDatabase(connection);
        SetActiveConnection(connection);
        try
        {
            DataSet data = database is null ? connection.ExecuteWithResults(sql) : database.ExecuteWithResults(sql);
            if (data.Tables.Count > 0) table = data.Tables[0];
            return null;
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            Exception inner;
            if (database is null)
            {
                StringBuilder chain = new();
                for (Exception? current = failure; current is not null; current = current.InnerException)
                    chain.Append(current.Message);
                // The pinned Server.Query throws its concatenated message, so the measured script-method
                // record has two RuntimeException layers, both with that message, without the SQL exception.
                inner = new RuntimeException(chain.ToString(), new RuntimeException(chain.ToString()));
            }
            else
            {
                inner = new MethodInvocationException(
                    String.Format(CultureInfo.InvariantCulture, "Exception calling \"ExecuteWithResults\" with \"1\" argument(s): \"{0}\"", failure.Message), failure);
            }
            MethodInvocationException query = new(
                String.Format(CultureInfo.InvariantCulture, "Exception calling \"Query\" with \"1\" argument(s): \"{0}\"", inner.Message), inner);
            return new ErrorRecord(query, "ScriptMethodRuntimeException", ErrorCategory.NotSpecified, null);
        }
        finally
        {
            if (database is not null) RestoreContext(connection, previous, true);
        }
    }

    private static string? ReadCurrentDatabase(ServerConnection connection)
    {
        try { return connection.CurrentDatabase; }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            // PowerShell's property read yields null if the connection has already failed.
            return null;
        }
    }

    private void RestoreContext(ServerConnection connection, string? database, bool queryMethod)
    {
        if (String.IsNullOrEmpty(database) || String.Equals(database, ReadCurrentDatabase(connection), StringComparison.Ordinal))
            return;

        string? warning = null;
        try
        {
            connection.ExecuteNonQuery("USE [" + database!.Replace("]", "]]") + "]");
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            warning = String.Format(CultureInfo.InvariantCulture, "The database context could not be restored to [{0}]: Exception calling \"ExecuteNonQuery\" with \"1\" argument(s): \"{1}\"", database, failure.Message);
        }
        if (warning is null) return;

        object? preference = SessionState.PSVariable.GetValue("WarningPreference");
        bool suppressStop = preference is not ActionPreference action ||
            (action != ActionPreference.SilentlyContinue && action != ActionPreference.Ignore && action != ActionPreference.Continue);
        try
        {
            if (suppressStop) SessionState.PSVariable.Set("WarningPreference", ActionPreference.Continue);
            if (queryMethod)
                WriteWarning(warning); // style-ok: cs-raw-streams pinned Database.Query emits an unattributed housekeeping warning
            else
                WriteAttributedMessage("Restore-DatabaseContext", MessageLevel.Warning, warning);
        }
        catch (ActionPreferenceStopException)
        {
            // A bound -WarningAction Stop must not replace the original query outcome.
        }
        finally
        {
            if (suppressStop) SessionState.PSVariable.Set("WarningPreference", preference);
        }
    }
}

