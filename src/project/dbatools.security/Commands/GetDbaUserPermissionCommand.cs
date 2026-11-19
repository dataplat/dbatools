#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Data;
using System.Globalization;
using System.IO;
using System.Management.Automation;
using System.Text.RegularExpressions;
using Dataplat.Dbatools.dbaSystem;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.Data.SqlClient;
using Microsoft.SqlServer.Management.Common;
using Microsoft.SqlServer.Management.Smo;
// the sibling namespace Dataplat.Dbatools.Database shadows Smo.Database inside Dataplat.Dbatools.Commands
using SmoDatabase = Microsoft.SqlServer.Management.Smo.Database;

namespace Dataplat.Dbatools.Commands;

// Port of public/Get-DbaUserPermission.ps1 at refs/pins/dbatools-2026-10-22. The begin block's T-SQL is kept verbatim; the
// process block's connect is the shared ConnectInstance, and each nested Invoke-DbaQuery -SqlInstance $server -Database <db>
// -Query <batches> -EnableException is absorbed as Query: the GO-separated batches on a connection of its own in that
// database (non-pooled, closed after), the DataRows of each batch, and the record its Stop-Function throws reaching the
// pinned catch as $_.

/// <summary>
/// Audits comprehensive security permissions across SQL Server instances using DISA STIG methodology
/// </summary>
/// <para>
/// Performs a comprehensive security audit by analyzing all server logins, server-level permissions, database users, database roles, and object-level permissions across SQL Server instances. Creates temporary STIG (Security Technical Implementation Guide) objects in tempdb to gather detailed permission information for both direct and inherited access rights.
/// </para>
/// <para>
/// This command is essential for security compliance audits, particularly for organizations implementing DISA STIG requirements. It reveals the complete permission landscape including role memberships, explicit grants/denials, and securable object permissions, giving DBAs the detailed visibility needed for access reviews and compliance reporting.
/// </para>
/// <para>
/// The function uses DISA-provided Permissions.sql scripts to ensure thorough analysis of security configurations. By default, it excludes public/guest permissions and system objects to focus on meaningful security grants, but these can be included for complete visibility.
/// </para>
/// <para>
/// Note that if you interrupt this command prematurely (Ctrl-C), it will leave behind a STIG schema in tempdb that should be manually cleaned up.
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaUserPermission -SqlInstance sql2008, sqlserver2012
/// </code>
/// <para>
/// Check server and database permissions for servers sql2008 and sqlserver2012.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaUserPermission -SqlInstance sql2008 -Database TestDB
/// </code>
/// <para>
/// Check server and database permissions on server sql2008 for only the TestDB database
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaUserPermission -SqlInstance sql2008 -Database TestDB -IncludePublicGuest -IncludeSystemObjects
/// </code>
/// <para>
/// Check server and database permissions on server sql2008 for only the TestDB database,
/// including public and guest grants, and sys schema objects.
/// </para>
/// </example>
/// <list type="alertSet">
/// <item>
/// <term />
/// <description>
/// <para>
/// Tags: Security, User
/// Author: Brandon Abshire, netnerds.net | Josh Smith
/// </para>
/// <para>
/// Website: https://dbatools.io
/// Copyright: (c) 2018 by dbatools, licensed under MIT
/// License: MIT https://opensource.org/licenses/MIT
/// </para>
/// </description>
/// </item>
/// <item>
/// <term>OUTPUTS</term>
/// <description>
/// <para>
/// PSCustomObject
/// </para>
/// <para>
/// Returns one object per permission grant/denial or role membership discovered during the security audit. Separate objects are returned for server-level and database-level permissions, with each object containing contextual information about the grantor, grantee, and permission state.
/// </para>
/// <para>
/// Properties:
/// - ComputerName: The computer name of the SQL Server instance
/// - InstanceName: The SQL Server instance name
/// - SqlInstance: The full SQL Server instance name (computer\instance format)
/// - Object: The scope of the permission - 'SERVER' for server-level permissions, or the database name for database-level permissions
/// - Type: The type of audit row - 'SERVER LOGINS', 'SERVER SECURABLES', 'DB ROLE MEMBERS', or 'DB SECURABLES'
/// - Member: The login or principal name (populated for role membership rows only)
/// - RoleSecurableClass: The role name for membership records, securable class for permission records, or 'None'
/// - SchemaOwner: The schema/owner name for object permissions (empty for role memberships)
/// - Securable: The name of the securable object being granted permissions (table, procedure, etc.) - empty for role memberships
/// - GranteeType: The type of grantee (USER, ROLE, APPLICATION ROLE) - empty for role memberships
/// - Grantee: The principal name that was granted the permission - empty for role memberships
/// - Permission: The permission name (SELECT, INSERT, EXECUTE, etc.) - empty for role memberships
/// - State: The permission state (GRANT or DENY) - empty for role memberships
/// - Grantor: The principal that granted the permission - empty for role memberships
/// - GrantorType: The type of grantor (USER, ROLE) - empty for role memberships
/// - SourceView: The STIG schema view the data came from - empty for role memberships
/// </para>
/// <para>
/// Note: Records with empty property values indicate that property does not apply to that audit row type. Role membership records populate only Member, RoleSecurableClass, and connection properties. Object permission records populate all securable-related properties.
/// </para>
/// </description>
/// </item>
/// </list>
/// <seealso href="https://dbatools.io/Get-DbaUserPermission" />
[Cmdlet(VerbsCommon.Get, "DbaUserPermission")]
[OutputType(typeof(PSCustomObject))]
public sealed class GetDbaUserPermissionCommand : DbaInstanceCmdlet
{
    /// <para>
    /// The target SQL Server instance or instances.
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
    /// Specifies which databases to audit for user permissions and role memberships. Accepts multiple database names and supports wildcards.
    /// Use this when you need to focus the security audit on specific databases rather than scanning the entire instance.
    /// </para>
    [Parameter(Position = 2)]
    public object[]? Database { get; set; }

    /// <para>
    /// Specifies databases to skip during the security audit. Useful for excluding databases that don't require security review.
    /// Common scenarios include excluding development databases or databases with known compliant configurations.
    /// </para>
    [Parameter(Position = 3)]
    public object[]? ExcludeDatabase { get; set; }

    /// <para>
    /// Excludes system databases (master, model, msdb, tempdb) from the security audit. Focuses the output on user databases only.
    /// Use this when compliance requirements only apply to application databases and not SQL Server system databases.
    /// </para>
    [Parameter]
    public SwitchParameter ExcludeSystemDatabase { get; set; }

    /// <para>
    /// Includes permissions granted to the public database role and guest user account in the audit results.
    /// Use this for complete security visibility, as public and guest permissions affect all users and can create unintended access paths.
    /// </para>
    [Parameter]
    public SwitchParameter IncludePublicGuest { get; set; }

    /// <para>
    /// Includes permissions on system schema objects (sys, INFORMATION_SCHEMA) in the audit results.
    /// Enable this when security policies require auditing access to metadata views and system functions that could expose sensitive information.
    /// </para>
    [Parameter]
    public SwitchParameter IncludeSystemObjects { get; set; }

    /// <para>
    /// Excludes object-level permissions (tables, views, procedures, functions) from the audit and returns only role memberships.
    /// Use this for high-level security reviews focused on role-based access rather than granular object permissions.
    /// </para>
    [Parameter]
    public SwitchParameter ExcludeSecurables { get; set; }

    private const string QueryRunner = "Invoke-DbaQuery";

    // The name the pinned T-SQL gives the schema it builds in tempdb.
    private const string PinnedSchema = "STIG";

    // Invoke-DbaQuery's GO separator (the native Invoke-DbaQuery's GoSplitterRegex, "(?smi)^[\s]*GO[\s]*" and the end anchor).
    private static readonly Regex GoSeparator = new("(?smi)^[\\s]*GO[\\s]*" + "$");

    // PS: the begin block's $removeStigSQL, verbatim.
    private const string RemoveStigSql = @"       BEGIN TRY DROP FUNCTION STIG.server_effective_permissions END TRY BEGIN CATCH END CATCH;
                       GO
                       BEGIN TRY DROP VIEW STIG.server_permissions END TRY BEGIN CATCH END CATCH;
                       GO
                       BEGIN TRY DROP FUNCTION STIG.members_of_server_role END TRY BEGIN CATCH END CATCH;
                       GO
                       BEGIN TRY DROP FUNCTION STIG.server_roles_of END TRY BEGIN CATCH END CATCH;
                       GO
                       BEGIN TRY DROP VIEW STIG.server_role_members END TRY BEGIN CATCH END CATCH;
                       GO
                       BEGIN TRY DROP FUNCTION STIG.database_effective_permissions END TRY BEGIN CATCH END CATCH;
                       GO
                       BEGIN TRY DROP VIEW STIG.database_permissions END TRY BEGIN CATCH END CATCH;
                       GO
                       BEGIN TRY DROP FUNCTION STIG.members_of_db_role END TRY BEGIN CATCH END CATCH;
                       GO
                       BEGIN TRY DROP FUNCTION STIG.database_roles_of END TRY BEGIN CATCH END CATCH;
                       GO
                       BEGIN TRY DROP VIEW STIG.database_role_members END TRY BEGIN CATCH END CATCH;
                       GO
                       BEGIN TRY DROP SCHEMA STIG END TRY BEGIN CATCH END CATCH;
                       GO";

    // PS: the begin block's $serverSQL, verbatim; the T-SQL comment only carries the style note for the pinned view.
    private const string ServerSql = @"SELECT  'SERVER LOGINS' AS Type ,
                                    sl.name AS Member ,
                                    ISNULL(srm.Role, 'None') AS [Role/Securable/Class] ,
                                    ' ' AS [Schema/Owner] ,
                                    ' ' AS [Securable] ,
                                    ' ' AS [Grantee Type] ,
                                    ' ' AS [Grantee] ,
                                    ' ' AS [Permission] ,
                                    ' ' AS [State] ,
                                    ' ' AS [Grantor] ,
                                    ' ' AS [Grantor Type] ,
                                    ' ' AS [Source View]
                            FROM    master.sys.syslogins sl -- style-ok: sql-deprecated-views the pinned query: its rows are the rows of sys.syslogins
                                    LEFT JOIN tempdb.[STIG].[server_role_members] srm ON sl.name = srm.Member
                            WHERE   sl.name NOT LIKE 'NT %'
                                    AND sl.name NOT LIKE '##%'";

    // PS: the begin block's $dbSQL, verbatim.
    private const string DbSql = @"SELECT  'DB ROLE MEMBERS' AS Type ,
                                Member ,
                                ISNULL(Role, 'None') AS [Role/Securable/Class],
                                ' ' AS [Schema/Owner] ,
                                ' ' AS [Securable] ,
                                ' ' AS [Grantee Type] ,
                                ' ' AS [Grantee] ,
                                ' ' AS [Permission] ,
                                ' ' AS [State] ,
                                ' ' AS [Grantor] ,
                                ' ' AS [Grantor Type] ,
                                ' ' AS [Source View]
                        FROM    tempdb.[STIG].[database_role_members]";

    // PS: the union the begin block appends to $serverSQL unless -ExcludeSecurables, verbatim.
    private const string ServerSecurablesSql = @"
                            UNION
                            SELECT  'SERVER SECURABLES' AS Type ,
                                    sl.name ,
                                    sp.[Securable Class] COLLATE SQL_Latin1_General_CP1_CI_AS ,
                                    ' ' ,
                                    sp.[Securable] ,
                                    sp.[Grantee Type] COLLATE SQL_Latin1_General_CP1_CI_AS ,
                                    sp.Grantee ,
                                    sp.Permission COLLATE SQL_Latin1_General_CP1_CI_AS ,
                                    sp.State COLLATE SQL_Latin1_General_CP1_CI_AS ,
                                    sp.Grantor ,
                                    sp.[Grantor Type] COLLATE SQL_Latin1_General_CP1_CI_AS ,
                                    sp.[Source View]
                            FROM    master.sys.syslogins sl -- style-ok: sql-deprecated-views the pinned query: its rows are the rows of sys.syslogins
                                    LEFT JOIN tempdb.[STIG].[server_permissions] sp ON sl.name = sp.Grantee
                            WHERE   sl.name NOT LIKE 'NT %'
                                    AND sl.name NOT LIKE '##%';";

    // PS: the union the begin block appends to $dbSQL unless -ExcludeSecurables, verbatim.
    private const string DbSecurablesSql = @"
                        UNION
                        SELECT DISTINCT
                                'DB SECURABLES' AS Type ,
                                ISNULL(drm.Member, 'None') AS [Role/Securable/Class] ,
                                dp.[Securable Type or Class] COLLATE SQL_Latin1_General_CP1_CI_AS ,
                                dp.[Schema/Owner] ,
                                dp.Securable ,
                                dp.[Grantee Type] COLLATE SQL_Latin1_General_CP1_CI_AS ,
                                dp.Grantee ,
                                dp.Permission COLLATE SQL_Latin1_General_CP1_CI_AS ,
                                dp.State COLLATE SQL_Latin1_General_CP1_CI_AS ,
                                dp.Grantor ,
                                dp.[Grantor Type] COLLATE SQL_Latin1_General_CP1_CI_AS ,
                                dp.[Source View]
                        FROM    tempdb.[STIG].[database_role_members] drm
                                FULL JOIN tempdb.[STIG].[database_permissions] dp ON ( drm.Member = dp.Grantee
                                                                                      OR drm.Role = dp.Grantee
                                                                                     )
                        WHERE    dp.Grantor IS NOT NULL
                                AND dp.Grantee NOT IN ('public', 'guest')
                                AND [Schema/Owner] <> 'sys'";

    private string _serverSql = ServerSql;
    private string _dbSql = DbSql;

    /// <summary>
    /// The begin block: the server and database queries, with the -ExcludeSecurables, -IncludePublicGuest and
    /// -IncludeSystemObjects edits the pinned begin block makes.
    /// </summary>
    protected override void BeginProcessing()
    {
        base.BeginProcessing();
        if (!ExcludeSecurables.ToBool())
        {
            _serverSql = ServerSql + ServerSecurablesSql;
            _dbSql = DbSql + DbSecurablesSql;
        }
        if (IncludePublicGuest.ToBool())
            _dbSql = _dbSql.Replace("AND dp.Grantee NOT IN ('public', 'guest')", "");
        if (IncludeSystemObjects.ToBool())
            _dbSql = _dbSql.Replace("AND [Schema/Owner] <> 'sys'", "");
    }

    /// <summary>
    /// Audits each instance bound to this record.
    /// </summary>
    protected override void ProcessRecord()
    {
        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            // PS: try { Connect-DbaInstance -MinimumVersion 10 -AzureUnsupported } catch { Stop-Function -Message "Failure" -Category ConnectionError -Continue }
            Server? server = ConnectInstance(instance, "Failure", minimumVersion: 10, azureUnsupported: true);
            if (server is null)
                continue;
            AuditInstance(server, instance);
        }
    }

    private void AuditInstance(Server server, DbaInstanceParameter instance)
    {
        List<SmoDatabase> dbs = SelectDatabases(server);
        string schema = SchemaName();
        string removeSql = InSchema(RemoveStigSql, schema);

        WriteMessage(MessageLevel.Verbose, "Reading stig.sql");
        string sql = "";
        bool removed = false;
        try
        {
            try
            {
                sql = InSchema(File.ReadAllText(Path.Combine(SystemHost.ModuleBase ?? String.Empty, "bin", "stig.sql")), schema);
                WriteMessage(MessageLevel.Verbose, "Removing STIG schema if it still exists from previous run");
                Query(server, "tempdb", removeSql);
                WriteMessage(MessageLevel.Verbose, "Creating STIG schema customized for master database");
                Query(server, "tempdb", ForDatabase(sql, "master"));
                WriteMessage(MessageLevel.Verbose, "Building data table for server objects");
                foreach (DataRow row in Query(server, "tempdb", InSchema(_serverSql, schema)))
                    WriteObject(Row(server, "SERVER", row));
            }
            catch (Exception failure) when (failure is not PipelineStoppedException)
            {
                // PS: Stop-Function -Message "Failed to create or use STIG schema on $instance" -ErrorRecord $_ -Target $instance -Continue,
                // which goes on to the next instance: the database loop and the last cleanup do not run.
                StopFunction("Failed to create or use STIG schema on " + Text(instance), target: instance, errorRecord: CaughtRecord(failure), continueLoop: true);
                return;
            }

            foreach (SmoDatabase db in dbs)
                AuditDatabase(server, instance, db, sql, removeSql, schema);

            try
            {
                WriteMessage(MessageLevel.Verbose, "Removing STIG schema from tempdb");
                Query(server, "tempdb", removeSql);
                removed = true;
            }
            catch (Exception failure) when (failure is not PipelineStoppedException)
            {
                StopFunction("Failed to remove STIG schema from tempdb on " + Text(instance), target: instance, errorRecord: CaughtRecord(failure), continueLoop: true);
            }
        }
        finally
        {
            // Correction fixed-schema-name: no later call drops this call's own schema, so it is dropped on every way out,
            // the pinned paths that skip the last cleanup (a stop, -EnableException, Ctrl-C) included.
            if (!removed)
                DropSchema(server, removeSql);
        }
    }

    // The last cleanup on a way out that skipped it: the same batches, with nothing written to the caller's streams.
    private void DropSchema(Server server, string removeSql)
    {
        ServerConnection? connection = null;
        try
        {
            ServerConnection copy = server.ConnectionContext.Copy();
            copy.NonPooledConnection = true;
            connection = copy.GetDatabaseConnection("tempdb", false);
            foreach (string batch in GoSeparator.Split(removeSql))
            {
                if (batch.Trim().Length != 0)
                    connection.ExecuteNonQuery(batch);
            }
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            // Not the caller's failure: the pin never ran this cleanup. Debug only, so the streams stay as the pin's.
            WriteMessage(MessageLevel.Debug, "Could not drop the tempdb schema of this call: " + failure.Message);
        }
        finally
        {
            if (connection is not null && connection.IsOpen)
                connection.Disconnect();
        }
    }

    private void AuditDatabase(Server server, DbaInstanceParameter instance, SmoDatabase db, string sql, string removeSql, string schema)
    {
        WriteMessage(MessageLevel.Verbose, "Processing " + Text(db) + " on " + Text(instance));

        // PS: if ($db.IsAccessible -eq $false): a getter that fails reads as $null, which is not $false.
        if (Read(() => db.IsAccessible) is bool accessible && !accessible)
        {
            WriteMessage(MessageLevel.Warning, "The database " + Text(db) + " on " + Text(instance) + " is not accessible. Skipping.");
            return;
        }

        try
        {
            WriteMessage(MessageLevel.Verbose, "Removing STIG schema if it still exists from previous run");
            Query(server, "tempdb", removeSql);
            WriteMessage(MessageLevel.Verbose, "Creating STIG schema customized for current database");
            string name = db.Name;
            string createStigSql = ForDatabase(sql, name);
            WriteMessage(MessageLevel.Verbose, "Length of createStigSQL: " + createStigSql.Length.ToString(CultureInfo.InvariantCulture));
            Query(server, "tempdb", createStigSql);
            WriteMessage(MessageLevel.Verbose, "Building data table for database objects");
            foreach (DataRow row in Query(server, name, InSchema(_dbSql, schema)))
                WriteObject(Row(server, name, row));
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            StopFunction("Failed to create or use STIG schema for database " + Text(db) + " on " + Text(instance), target: instance,
                errorRecord: CaughtRecord(failure), continueLoop: true);
        }
    }

    // The schema the T-SQL builds in tempdb for this instance.
    // Correction fixed-schema-name: the pin builds and drops tempdb.STIG, which every caller on the instance shares, so a
    // concurrent call drops or rebuilds the views this call reads (for another database) and the pin drops STIG objects it
    // did not create. Each call builds its own schema, STIG_ and a new GUID, and drops it when it is done.
    private static string SchemaName()
    {
        return PinnedSchema + "_" + Guid.NewGuid().ToString("N");
    }

    // The T-SQL with the pinned schema name STIG replaced by this instance's schema. It runs on the T-SQL text before any
    // database name is put in, so a database name is never rewritten.
    private static string InSchema(string sql, string schema)
    {
        return Regex.Replace(sql, "\\bSTIG\\b", match => schema, RegexOptions.CultureInvariant);
    }

    // PS: $sql.Replace("<TARGETDB>", <database name>)
    // Correction database-name-injection: the pin puts the name into [<TARGETDB>] as it is, so a name with ] ends the
    // identifier and the rest of the name runs as T-SQL; the name goes in with ] doubled.
    // Correction source-view-placeholder: stig.sql (since upstream 95b578a5be) writes the name as '<QUOTETARGETDB>' in a
    // string literal, a token the pin never replaces, so SourceView reads "<QUOTETARGETDB>.sys.database_permissions"; the
    // token takes the name with ' doubled, so SourceView names the database as it did before that change.
    // One pass over the text, so a name that holds either token is never read as one.
    private static string ForDatabase(string sql, string database)
    {
        return Regex.Replace(sql, "<QUOTETARGETDB>|<TARGETDB>",
            match => match.Value == "<TARGETDB>" ? database.Replace("]", "]]") : database.Replace("'", "''"), RegexOptions.CultureInvariant);
    }

    // PS: $dbs = $server.Databases, then Where-Object { $Database -contains $_.Name } when -Database is set,
    // Where-Object Name -NotIn $ExcludeDatabase when -ExcludeDatabase is set and Where-Object IsSystemObject -eq $false
    // with -ExcludeSystemDatabase.
    private List<SmoDatabase> SelectDatabases(Server server)
    {
        List<SmoDatabase> dbs = new();
        try
        {
            foreach (SmoDatabase candidate in server.Databases)
                dbs.Add(candidate);
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            // The pipeline that reads the collection writes the read's fault and goes on with what it read.
            WriteError(CaughtRecord(failure));
        }

        bool named = LanguagePrimitives.IsTrue(Database);
        bool excluded = LanguagePrimitives.IsTrue(ExcludeDatabase);

        // Correction database-wildcards: the help documents wildcards for -Database, which -contains never honoured. The
        // shared WildcardNameFilter matcher keeps each value's -contains comparison and adds the documented pattern, unless
        // the value is the name of a database on the instance (rule E+).
        WildcardNameMatcher? matcher = null;
        if (named)
        {
            List<string> scope = new();
            foreach (SmoDatabase db in dbs)
            {
                if (Read(() => db.Name) is string scopeName)
                    scope.Add(scopeName);
            }
            matcher = WildcardNameFilter.CreateMatcher(Database, true, (value, name) => Contains(new[] { value }, name), scope);
        }

        List<SmoDatabase> selected = new();
        foreach (SmoDatabase db in dbs)
        {
            string? name = Read(() => db.Name) as string;
            if (matcher is not null && !(name is not null && matcher.Matches(name)))
                continue;
            if (excluded && Contains(ExcludeDatabase, name))
                continue;
            if (ExcludeSystemDatabase.ToBool() && !(Read(() => db.IsSystemObject) is bool system && !system))
                continue;
            selected.Add(db);
        }
        return selected;
    }

    // PS: $values -contains $name and $name -in $values: each value -eq the name, the value as the left operand, ignoring case.
    private static bool Contains(object[]? values, string? name)
    {
        if (values is null)
            return false;
        foreach (object? value in values)
        {
            object? left = value is PSObject wrapped ? wrapped.BaseObject : value;
            if (LanguagePrimitives.Equals(left, name, true, CultureInfo.InvariantCulture))
                return true;
        }
        return false;
    }

    // PS: Invoke-DbaQuery -SqlInstance $server -Database <database> -Query <query> -EnableException. It keeps the server's own
    // connection when that connection is in the database and otherwise opens its own there, non-pooled, and closes it after; it
    // runs the GO-separated batches in turn and emits the first table of each as DataRows. Its Stop-Function under
    // -EnableException throws the record the pinned catch receives as $_.
    private List<DataRow> Query(Server server, string database, string query)
    {
        List<DataRow> rows = new();
        DbaInstanceParameter source = new((object)server);
        ServerConnection serverConnection = server.ConnectionContext;
        ServerConnection connection = serverConnection;
        bool reuse = false;
        bool opened = false;
        try
        {
            reuse = String.Equals(serverConnection.DatabaseName, database, StringComparison.OrdinalIgnoreCase)
                && String.IsNullOrEmpty(serverConnection.ConnectAsUserName);
            if (!reuse)
            {
                ServerConnection copy = serverConnection.Copy();
                copy.NonPooledConnection = true;
                connection = copy.GetDatabaseConnection(database, false);
                connection.StatementTimeout = serverConnection.StatementTimeout;
            }
            if (!connection.IsOpen)
            {
                connection.Connect();
                opened = true;
            }
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            throw new QueryFault(CaughtNestedStopFunction(QueryRunner, "Failure", target: source,
                errorRecord: new ErrorRecord(failure, QueryRunner, ErrorCategory.NotSpecified, null)));
        }

        try
        {
            foreach (string batch in GoSeparator.Split(query))
            {
                if (batch.Trim().Length == 0)
                    continue;
                using SqlCommand command = connection.SqlConnectionObject.CreateCommand();
                command.CommandText = batch;
                command.CommandTimeout = connection.StatementTimeout;
                using SqlDataAdapter adapter = new(command);
                DataSet results = new();
                SetActiveCommand(command);
                try
                {
                    adapter.Fill(results);
                }
                catch (Exception failure) when (failure is not PipelineStoppedException)
                {
                    MethodInvocationException fill = new(String.Format(CultureInfo.InvariantCulture,
                        "Exception calling \"Fill\" with \"1\" argument(s): \"{0}\"", failure.Message), failure);
                    throw new QueryFault(CaughtNestedStopFunction(QueryRunner,
                        String.Format(CultureInfo.InvariantCulture, "[{0}] Failed during execution", source), target: source,
                        errorRecord: new ErrorRecord(fill, QueryRunner, ErrorCategory.NotSpecified, null)));
                }
                finally
                {
                    SetActiveCommand(null);
                }
                if (results.Tables.Count != 0)
                {
                    foreach (DataRow row in results.Tables[0].Rows)
                        rows.Add(row);
                }
            }
        }
        finally
        {
            if (!reuse || opened)
                connection.Disconnect();
        }
        return rows;
    }

    // PS: [PSCustomObject]@{ ComputerName; InstanceName; SqlInstance; Object; Type; Member; RoleSecurableClass; SchemaOwner;
    // Securable; GranteeType; Grantee; Permission; State; Grantor; GrantorType; SourceView }, each value read from the row as
    // the DataRow adapter reads it (a NULL is DBNull).
    private static PSObject Row(Server server, string objectName, DataRow row)
    {
        PSObject output = new();
        OutputHelper.AddInstanceProperties(output, server);
        output.Properties.Add(new PSNoteProperty("Object", objectName));
        output.Properties.Add(new PSNoteProperty("Type", Column(row, "Type")));
        output.Properties.Add(new PSNoteProperty("Member", Column(row, "Member")));
        output.Properties.Add(new PSNoteProperty("RoleSecurableClass", Column(row, "Role/Securable/Class")));
        output.Properties.Add(new PSNoteProperty("SchemaOwner", Column(row, "Schema/Owner")));
        output.Properties.Add(new PSNoteProperty("Securable", Column(row, "Securable")));
        output.Properties.Add(new PSNoteProperty("GranteeType", Column(row, "Grantee Type")));
        output.Properties.Add(new PSNoteProperty("Grantee", Column(row, "Grantee")));
        output.Properties.Add(new PSNoteProperty("Permission", Column(row, "Permission")));
        output.Properties.Add(new PSNoteProperty("State", Column(row, "State")));
        output.Properties.Add(new PSNoteProperty("Grantor", Column(row, "Grantor")));
        output.Properties.Add(new PSNoteProperty("GrantorType", Column(row, "Grantor Type")));
        output.Properties.Add(new PSNoteProperty("SourceView", Column(row, "Source View")));
        return output;
    }

    // $row.'<column>': the DataRow adapter reads a column the row lacks as $null.
    private static object? Column(DataRow row, string name)
    {
        return row.Table.Columns.Contains(name) ? row[name] : null;
    }

    // The record the pinned catch receives as $_.
    private static ErrorRecord CaughtRecord(Exception failure)
    {
        if (failure is QueryFault fault)
            return fault.Record;
        if (failure is IContainsErrorRecord container && container.ErrorRecord is not null)
            return new ErrorRecord(container.ErrorRecord, failure);
        return new ErrorRecord(failure, failure.GetType().Name, ErrorCategory.NotSpecified, null);
    }

    // "$value" in a PowerShell string.
    private static string Text(object? value)
    {
        return value is null ? String.Empty : PSObject.AsPSObject(value).ToString();
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

    // Carries the nested Invoke-DbaQuery's thrown record to the catch that Stop-Function reports it from.
    private sealed class QueryFault : Exception
    {
        public QueryFault(ErrorRecord record)
            : base(record.Exception.Message, record.Exception)
        {
            Record = record;
        }

        public ErrorRecord Record { get; }
    }
}
