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
using SmoRecoveryModel = Microsoft.SqlServer.Management.Smo.RecoveryModel;

namespace Dataplat.Dbatools.Commands;

// Port of public/Get-DbaDbRecoveryModel.ps1 at refs/pins/dbatools-2026-10-22: the nested Get-DbaDatabase call, given the caller's
// -Database, -ExcludeDatabase and -EnableException, and for -RecoveryModel only the accessible databases of those models, each
// written with this command's default view.
/// <summary>Retrieves database recovery model settings and backup history information from SQL Server instances.</summary>
/// <para>Retrieves recovery model configuration for databases along with their last backup dates, which is essential for backup strategy planning and compliance auditing. DBAs use this to identify databases with inappropriate recovery models for their business requirements, troubleshoot transaction log growth issues, and ensure backup policies align with recovery model settings. The function shows whether databases are accessible and when their last full, differential, and transaction log backups occurred, making it valuable for both routine maintenance and disaster recovery planning.</para>
/// <list type="alertSet">
///   <item>
///     <term></term>
///     <description>
///       <para>Tags: Recovery, RecoveryModel, Backup</para>
///       <para>Author: Viorel Ciucu (@viorelciucu), cviorel.com</para>
///       <para>Website: https://dbatools.io</para>
///       <para>Copyright: (c) 2018 by dbatools, licensed under MIT</para>
///       <para>License: MIT https://opensource.org/licenses/MIT</para>
///     </description>
///   </item>
/// </list>
/// <example>
///   <prefix>PS C:\&gt;</prefix>
///   <code>Get-DbaDbRecoveryModel -SqlInstance sql2014 -RecoveryModel BulkLogged -Verbose</code>
///   <para>Gets all databases on SQL Server instance sql2014 having RecoveryModel set to BulkLogged.</para>
/// </example>
/// <example>
///   <prefix>PS C:\&gt;</prefix>
///   <code>Get-DbaDbRecoveryModel -SqlInstance sql2014 -Database TestDB</code>
///   <para>Gets recovery model information for TestDB. If TestDB does not exist on the instance nothing is returned.</para>
/// </example>
/// <seealso href="https://dbatools.io/Get-DbaDbRecoveryModel"/>
[Cmdlet(VerbsCommon.Get, "DbaDbRecoveryModel")]
public sealed class GetDbaDbRecoveryModelCommand : DbaInstanceCmdlet
{
    private const string DatabaseCommand = "Get-DbaDatabase";

    // PS: Invoke-QueryRawDatabases, for SQL Server 2008 and later and for Azure SQL Database. Its rows set the order of the databases.
    // Correction azure-recovery-model adds recovery_model to the Azure query.
    private const string InstanceDatabasesQuery = "SELECT name, state, SUSER_SNAME(owner_sid) AS [Owner], is_cdc_enabled FROM sys.databases";
    private const string AzureDatabasesQuery = "SELECT db.name, db.state, dp.name AS [Owner], db.recovery_model FROM sys.databases AS db LEFT JOIN sys.database_principals AS dp ON dp.sid = db.owner_sid";

    // PS: $querySizes, which stands in for a Size that SMO reports as null or 0. Azure SQL Database has no sys.master_files, so each
    // database is read in a connection of its own there.
    private const string InstanceSizesQuery = "SELECT DB_NAME(database_id) AS name, CAST(SUM(CAST(size AS BIGINT)) * 8.0 / 1024 AS DECIMAL(18,2)) AS SizeMB FROM sys.master_files GROUP BY database_id";
    private const string AzureSizeQuery = "SELECT DB_NAME() AS name, CAST(SUM(CAST(size AS BIGINT)) * 8.0 / 1024 AS DECIMAL(18,2)) AS SizeMB FROM sys.database_files";

    // Get-DbaDatabase's default -Status: a database passes when any of its status flags is one of these.
    private const DatabaseStatus ListedStatus = DatabaseStatus.EmergencyMode | DatabaseStatus.Normal | DatabaseStatus.Offline |
        DatabaseStatus.Recovering | DatabaseStatus.RecoveryPending | DatabaseStatus.Restoring | DatabaseStatus.Standby | DatabaseStatus.Suspect;

    // PS: $defaults, with each "X as Y" written as the alias Y.
    private static readonly string[] DisplayProperties =
    {
        "ComputerName", "InstanceName", "SqlInstance", "Name", "Status", "IsAccessible", "RecoveryModel", "LastFullBackup", "LastDiffBackup", "LastLogBackup"
    };

    /// <para>The target SQL Server instance or instances.</para>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public override DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <para>Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).</para>
    /// <para>Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.</para>
    /// <para>For MFA support, please use Connect-DbaInstance.</para>
    [Parameter(Position = 1)]
    public override PSCredential? SqlCredential { get; set; }

    /// <para>Filters results to show only databases using the specified recovery model (Simple, Full, or BulkLogged).</para>
    /// <para>Use this to identify databases with incorrect recovery models for your backup strategy or to audit compliance with recovery model policies.</para>
    /// <para>Details about the recovery models can be found here:</para>
    /// <para>https://docs.microsoft.com/en-us/sql/relational-databases/backup-restore/recovery-models-sql-server</para>
    [Parameter(Position = 2)]
    [ValidateSet("Simple", "Full", "BulkLogged")]
    public string[]? RecoveryModel { get; set; }

    /// <para>Specifies which databases to retrieve recovery model information for. Accepts database names, wildcards, or arrays.</para>
    /// <para>Use this when you need to check recovery models for specific databases rather than all databases on the instance.</para>
    [Parameter(Position = 3)]
    public object[]? Database { get; set; }

    /// <para>Excludes specific databases from the recovery model check. Accepts database names, wildcards, or arrays.</para>
    /// <para>Useful for skipping system databases or databases you don't manage when reviewing recovery model compliance.</para>
    [Parameter(Position = 4)]
    public object[]? ExcludeDatabase { get; set; }

    // Overridden only to carry the pinned .PARAMETER EnableException help; same bare [Parameter] as the base.
    /// <para>By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.</para>
    /// <para>This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.</para>
    /// <para>Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.</para>
    [Parameter]
    public override SwitchParameter EnableException { get; set; }

    protected override void ProcessRecord()
    {
        // PS: Get-DbaDatabase binds -Database and -ExcludeDatabase as [string[]]: a null element becomes "", any other value its text.
        string[]? included = BoundNames(Database);
        string[]? excluded = BoundNames(ExcludeDatabase);
        bool filtered = LanguagePrimitives.IsTrue(RecoveryModel);

        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            Server? server = OpenServer(instance);
            if (server is null)
                continue;

            foreach (PSObject output in SelectDatabases(server, included, excluded))
            {
                // PS: Where-Object RecoveryModel -in $RecoveryModel | Where-Object IsAccessible, only for -RecoveryModel.
                if (filtered && !(HasListedModel(output) && LanguagePrimitives.IsTrue(ReadMember(output, "IsAccessible"))))
                    continue;
                // PS: Select-DefaultView -Property $defaults adds its three aliases again, then this view.
                SetAlias(output, "LastFullBackup", "LastBackupDate");
                SetAlias(output, "LastDiffBackup", "LastDifferentialBackupDate");
                SetAlias(output, "LastLogBackup", "LastLogBackupDate");
                OutputHelper.SetDefaultDisplayPropertySet(output, DisplayProperties);
                WriteObject(output);
            }
        }
    }

    // PS: Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential inside Get-DbaDatabase's try. Its Stop-Function
    // -Continue warns under Get-DbaDatabase's name and reads the next instance, or throws under the -EnableException passed on.
    private Server? OpenServer(DbaInstanceParameter instance)
    {
        SmoConnectionRequest request = new();
        request.Instance = instance;
        request.SqlCredential = SqlCredential;
        request.BoundParameters = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { nameof(SqlInstance), nameof(SqlCredential) };
        request.MessageCallback = (level, message) => WriteAttributedMessage("Connect-DbaInstance", level, message);
        try
        {
            WriteAttributedMessage("Connect-DbaInstance", MessageLevel.Debug, "Starting process block");
            Server server = ConnectionService.GetServer(request);
            SetActiveConnection(server.ConnectionContext);
            WriteAttributedMessage("Connect-DbaInstance", MessageLevel.Debug, "We are finished with this instance");
            return server;
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            // The caught record holds the connection's own failure, as Connect-DbaInstance's port reports it; the resolution exception
            // only names the pinned call site.
            Exception reported = failure is ConnectionResolutionException ? failure.InnerException ?? failure : failure;
            ErrorRecord record = new(reported, "dbatools_" + DatabaseCommand, ErrorCategory.ConnectionError, instance);
            StopAttributedFunction(DatabaseCommand, "Failure", target: instance, errorRecord: record, category: ErrorCategory.ConnectionError, continueLoop: true);
            return null;
        }
    }

    // PS: the Where-Object filters of Get-DbaDatabase over the rows of sys.databases, in their order, then what it adds to each database.
    // Correction database-wildcards: the pinned help documents wildcards for -Database and -ExcludeDatabase, which the exact -in and
    // -notin of Get-DbaDatabase never honoured. The instance's own names decide which pattern values are real names and stay literal.
    private List<PSObject> SelectDatabases(Server server, string[]? included, string[]? excluded)
    {
        List<PSObject> selected = new();
        bool azure = SmoServerExtensions.GetIsAzure(server);
        DataTable? rows = ReadDatabases(server, azure);
        if (rows is null)
        {
            // PS: with no rows the size query still runs, and warns when it fails too; Azure reads sizes per database, so none there.
            if (!azure)
                _ = ReadInstanceSizes(server);
            return selected;
        }

        List<string> names = new();
        foreach (DataRow row in rows.Rows)
            names.Add(Convert.ToString(row["name"], CultureInfo.InvariantCulture) ?? "");
        WildcardNameMatcher includes = NameMatcher(included, names);
        WildcardNameMatcher excludes = NameMatcher(excluded, names);
        bool including = LanguagePrimitives.IsTrue(included);
        bool excluding = LanguagePrimitives.IsTrue(excluded);

        List<SmoDatabase>? known = KnownDatabases(server);
        List<KeyValuePair<SmoDatabase, DataRow>> chosen = new();
        foreach (DataRow row in rows.Rows)
        {
            string name = Convert.ToString(row["name"], CultureInfo.InvariantCulture) ?? "";
            if ((including && !includes.Matches(name)) || (excluding && excludes.Matches(name)))
                continue;
            foreach (SmoDatabase database in Named(server, known, name))
            {
                if (azure || HasListedStatus(database))
                    chosen.Add(new KeyValuePair<SmoDatabase, DataRow>(database, row));
            }
        }

        DataTable? sizes = azure ? null : ReadInstanceSizes(server);
        foreach (KeyValuePair<SmoDatabase, DataRow> pair in chosen)
            selected.Add(AddDatabaseMembers(server, pair.Key, pair.Value, sizes, azure));
        return selected;
    }

    // PS: Invoke-QueryRawDatabases. Its Stop-Function has no -Continue and runs in that helper, so without -EnableException it only
    // warns, and the instance then has no database to write.
    private DataTable? ReadDatabases(Server server, bool azure)
    {
        try
        {
            return server.ConnectionContext.ExecuteWithResults(azure ? AzureDatabasesQuery : InstanceDatabasesQuery).Tables[0];
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            StopAttributedFunction("Invoke-QueryRawDatabases", "Failure", errorRecord: new ErrorRecord(failure, "dbatools_Invoke-QueryRawDatabases", ErrorCategory.NotSpecified, null),
                interruptCallerScope: false);
            return null;
        }
    }

    // PS: $server.Databases, enumerated once here; the pin enumerates the same cached collection for each row.
    private List<SmoDatabase>? KnownDatabases(Server server)
    {
        try
        {
            List<SmoDatabase> known = new();
            foreach (SmoDatabase database in server.Databases)
                known.Add(database);
            return known;
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            WriteAttributedMessage(DatabaseCommand, MessageLevel.Verbose, "Failure: " + failure.Message);
            return null;
        }
    }

    // PS: $server.Databases | Where-Object Name -ceq $dt.name, or, where the collection cannot be enumerated, $server.Databases[$dt.name].
    private static List<SmoDatabase> Named(Server server, List<SmoDatabase>? known, string name)
    {
        List<SmoDatabase> found = new();
        if (known is null)
        {
            SmoDatabase? indexed = Indexed(server, name);
            if (indexed is not null)
                found.Add(indexed);
            return found;
        }
        foreach (SmoDatabase database in known)
        {
            if (String.Equals(ReadName(database), name, StringComparison.Ordinal))
                found.Add(database);
        }
        return found;
    }

    private static SmoDatabase? Indexed(Server server, string name)
    {
        try
        {
            return server.Databases[name];
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            // The pin adds whatever the indexer gives; a failed lookup gives no database, and its later filters drop a null.
            return null;
        }
    }

    // PS: (Compare-Object @($_.Status.tostring().split(',').trim()) $Status -ExcludeDifferent -IncludeEqual).inputobject.count -ge 1.
    // The default ReadOnly, IsAccessible and IsSystemObject filters of Get-DbaDatabase list both values, so they pass every database
    // whose value can be read; a getter that fails reads as $null, which they drop.
    private static bool HasListedStatus(SmoDatabase database)
    {
        try
        {
            _ = database.ReadOnly;
            _ = database.IsAccessible;
            _ = database.IsSystemObject;
            return (database.Status & ListedStatus) != 0;
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            return false;
        }
    }

    // PS: Invoke-QueryDatabaseSizes; a failure warns and leaves every Size as SMO reports it.
    private DataTable? ReadInstanceSizes(Server server)
    {
        try
        {
            return server.ConnectionContext.ExecuteWithResults(InstanceSizesQuery).Tables[0];
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            WriteAttributedMessage(DatabaseCommand, MessageLevel.Warning, "Could not retrieve database sizes via T-SQL: " + QueryFailureText(failure));
            return null;
        }
    }

    // PS: the Add-Member calls of Get-DbaDatabase in its order, then the aliases of its Select-DefaultView.
    private PSObject AddDatabaseMembers(Server server, SmoDatabase database, DataRow row, DataTable? sizes, bool azure)
    {
        PSObject output = PSObject.AsPSObject(database);
        object? isCdcEnabled = row.Table.Columns.Contains("is_cdc_enabled") ? row["is_cdc_enabled"] : null;
        object? size = ReadMember(output, "Size");
        if (size is null || LanguagePrimitives.Equals(size, 0))
            size = azure ? ReadAzureSize(server, database) ?? size : ListedSize(sizes, ReadName(database)) ?? size;

        SetNote(output, "BackupStatus", null);
        output.Properties.Remove("ComputerName");
        output.Properties.Remove("InstanceName");
        output.Properties.Remove("SqlInstance");
        OutputHelper.AddInstanceProperties(output, server);
        SetNote(output, "LastRead", null);
        SetNote(output, "LastWrite", null);
        SetNote(output, "IsCdcEnabled", isCdcEnabled);
        if (size is not null)
            SetNote(output, "Size", size);
        if (azure)
            AddAzureRecoveryModel(output, database, row);

        SetAlias(output, "SizeMB", "Size");
        SetAlias(output, "Compatibility", "CompatibilityLevel");
        SetAlias(output, "Encrypted", "EncryptionEnabled");
        SetAlias(output, "LastFullBackup", "LastBackupDate");
        SetAlias(output, "LastDiffBackup", "LastDifferentialBackupDate");
        SetAlias(output, "LastLogBackup", "LastLogBackupDate");
        return output;
    }

    // Correction azure-recovery-model: SMO's RecoveryModel getter fails on Azure SQL Database, so the pin shows no model and its
    // -RecoveryModel filter loses every database, while sys.databases gives the value. The enum's values are those of
    // sys.databases.recovery_model. A getter that reads keeps its own value.
    private static void AddAzureRecoveryModel(PSObject output, SmoDatabase database, DataRow row)
    {
        try
        {
            _ = database.RecoveryModel;
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            if (row["recovery_model"] is not DBNull)
                SetNote(output, "RecoveryModel", (SmoRecoveryModel)Convert.ToInt32(row["recovery_model"], CultureInfo.InvariantCulture));
        }
    }

    // PS: $dbSizes | Where-Object { $_.name -eq $db.Name }, then its SizeMB.
    private static object? ListedSize(DataTable? sizes, string? name)
    {
        if (sizes is null)
            return null;
        foreach (DataRow row in sizes.Rows)
        {
            if (LanguagePrimitives.Equals(row["name"], name, true, CultureInfo.InvariantCulture))
                return row["SizeMB"] is DBNull ? null : row["SizeMB"];
        }
        return null;
    }

    // PS: Invoke-DbaQuery -SqlInstance $server -Database $db.Name -Query $querySizes -EnableException inside a catch that skips the
    // database. It runs here only for a database whose Size SMO reports as null or 0, the only one whose output it changes.
    private object? ReadAzureSize(Server server, SmoDatabase database)
    {
        string? name = ReadName(database);
        if (name is null)
            return null;
        ServerConnection? connection = null;
        try
        {
            ServerConnection copy = server.ConnectionContext.Copy();
            copy.NonPooledConnection = true;
            connection = copy.GetDatabaseConnection(name, false);
            DataTable table = connection.ExecuteWithResults(AzureSizeQuery).Tables[0];
            return ListedSize(table, name);
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            // The pinned catch skips a database that cannot be read, with no message; its Size stays as SMO reports it.
            return null;
        }
        finally
        {
            if (connection is not null && connection.IsOpen)
                connection.Disconnect();
        }
    }

    // PS: RecoveryModel -in $RecoveryModel, each value compared with the model as -eq does, ignoring case.
    private bool HasListedModel(PSObject output)
    {
        object? model = ReadMember(output, "RecoveryModel");
        if (model is null || RecoveryModel is null)
            return false;
        foreach (string value in RecoveryModel)
        {
            if (LanguagePrimitives.Equals(value, model, true, CultureInfo.InvariantCulture))
                return true;
        }
        return false;
    }

    // PS: the text of an error from the Server.Query script method: the messages of its inner exceptions, joined, in its own wrapper.
    private static string QueryFailureText(Exception failure)
    {
        string joined = "";
        for (Exception? inner = failure; inner is not null; inner = inner.InnerException)
            joined += inner.Message;
        return "Exception calling \"Query\" with \"1\" argument(s): \"" + joined + "\"";
    }

    private static string[]? BoundNames(object[]? values)
    {
        return values is null ? null : (string[])LanguagePrimitives.ConvertTo(values, typeof(string[]), CultureInfo.InvariantCulture);
    }

    // PS: -in and -notin compare each value with the name, ignoring case; a pattern is tried as correction database-wildcards allows.
    private static WildcardNameMatcher NameMatcher(string[]? values, List<string> scope)
    {
        return WildcardNameFilter.CreateMatcher(values, true,
            (value, name) => LanguagePrimitives.Equals(value, name, true, CultureInfo.InvariantCulture), scope);
    }

    private static string? ReadName(SmoDatabase database)
    {
        try
        {
            return database.Name;
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            // The dot operator reads a getter that fails as $null.
            return null;
        }
    }

    // PS: member access, which sees a member added earlier and reads a getter that fails as $null, with no record.
    private static object? ReadMember(PSObject output, string name)
    {
        try
        {
            return output.Properties[name]?.Value;
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            return null;
        }
    }

    // PS: Add-Member -Force -MemberType NoteProperty.
    private static void SetNote(PSObject output, string name, object? value)
    {
        output.Properties.Remove(name);
        output.Properties.Add(new PSNoteProperty(name, value));
    }

    // PS: Add-Member -Force -MemberType AliasProperty, as Select-DefaultView adds "X as Y".
    private static void SetAlias(PSObject output, string name, string referenced)
    {
        output.Properties.Remove(name);
        OutputHelper.AddAliasProperty(output, name, referenced);
    }
}
