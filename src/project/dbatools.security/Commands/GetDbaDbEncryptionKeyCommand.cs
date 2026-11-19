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

// Port of public/Get-DbaDbEncryptionKey.ps1 at refs/pins/dbatools-2026-10-22: the nested Get-DbaDatabase selection and the
// decorated $db.DatabaseEncryptionKey with its default view.
/// <summary>Retrieves Transparent Data Encryption (TDE) database encryption keys from SQL Server databases</summary>
/// <para>
/// Retrieves detailed information about Transparent Data Encryption (TDE) database encryption keys including encryption state, algorithm, and certificate details. This function helps DBAs audit encrypted databases, verify TDE configuration, and gather key information for compliance reporting or troubleshooting encryption issues. Returns comprehensive key properties like thumbprint, encryption type, and important dates for certificate rotation planning.
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaDbEncryptionKey -SqlInstance sql2016
/// </code>
/// <para>
/// Gets all encryption keys from sql2016
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaDbEncryptionKey -SqlInstance sql01 -Database db1
/// </code>
/// <para>
/// Gets the encryption key for the db1 database on the sql01 instance
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaDbEncryptionKey -SqlInstance sql01 -Database db1 -Certificate cert1
/// </code>
/// <para>
/// Gets the cert1 encryption key within the db1 database
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaDbEncryptionKey -SqlInstance sql01 -Database db1 -Subject 'Availability Group Cert'
/// </code>
/// <para>
/// Gets the encryption key within the db1 database that has the subject 'Availability Group Cert' on sql01
/// </para>
/// </example>
/// <list type="alertSet">
/// <item>
/// <term />
/// <description>
/// <para>
/// Tags: Certificate, Security
/// Author: Chrissy LeMaire (@cl), netnerds.net
/// </para>
/// <para>
/// Website: https://dbatools.io
/// Copyright: (c) 2022 by dbatools, licensed under MIT
/// License: MIT https://opensource.org/licenses/MIT
/// </para>
/// </description>
/// </item>
/// </list>
/// <seealso href="https://dbatools.io/Get-DbaDbEncryptionKey" />
[Cmdlet(VerbsCommon.Get, "DbaDbEncryptionKey")]
[OutputType(typeof(DatabaseEncryptionKey))]
public sealed class GetDbaDbEncryptionKeyCommand : DbaInstanceCmdlet
{
    // PS: Select-DefaultView -Property ComputerName, InstanceName, SqlInstance, Database, CreateDate, EncryptionAlgorithm,
    // EncryptionState, EncryptionType, EncryptorName, ModifyDate, OpenedDate, RegenerateDate, SetDate, Thumbprint
    private static readonly string[] DisplaySet =
    {
        "ComputerName", "InstanceName", "SqlInstance", "Database", "CreateDate", "EncryptionAlgorithm", "EncryptionState",
        "EncryptionType", "EncryptorName", "ModifyDate", "OpenedDate", "RegenerateDate", "SetDate", "Thumbprint"
    };

    private static readonly string[] InstanceProperties = { "ComputerName", "InstanceName", "SqlInstance" };

    // Get-DbaDatabase's default -Status, any overlap sufficient.
    private const DatabaseStatus DefaultStatus = DatabaseStatus.Normal | DatabaseStatus.Restoring |
        DatabaseStatus.RecoveryPending | DatabaseStatus.Recovering | DatabaseStatus.Suspect |
        DatabaseStatus.Offline | DatabaseStatus.Standby | DatabaseStatus.EmergencyMode;

    private const string KeyCountSql = "SELECT COUNT(*) FROM sys.dm_database_encryption_keys WHERE database_id = {0};";

    private const string AzureKeySql ="SELECT encryption_state, create_date, opened_date, regenerate_date, modify_date, set_date, key_algorithm, key_length, encryptor_thumbprint, encryptor_type FROM sys.dm_database_encryption_keys WHERE database_id = DB_ID();";

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
    /// Specifies which databases to retrieve TDE encryption keys from. Accepts wildcards for pattern matching.
    /// Use this when you need to check encryption status for specific databases instead of all databases on the instance.
    /// </para>
    [Parameter(Position = 2)]
    public string[]? Database { get; set; }

    /// <para>
    /// Excludes specific databases from the encryption key retrieval operation. Useful when scanning all databases except certain ones like system databases or test databases.
    /// Commonly used to skip tempdb or databases that are known to be unencrypted.
    /// </para>
    [Parameter(Position = 3)]
    public string[]? ExcludeDatabase { get; set; }

    /// <para>
    /// Accepts database objects piped from Get-DbaDatabase or other dbatools commands. This allows you to filter databases using Get-DbaDatabase's extensive filtering options before checking encryption keys.
    /// Particularly useful for complex database selection scenarios or when working with specific database collections.
    /// </para>
    [Parameter(ValueFromPipeline = true, Position = 4)]
    public SmoDatabase[]? InputObject { get; set; }

    /// <summary>Reads the keys of the record's piped databases and of any -SqlInstance databases.</summary>
    protected override void ProcessRecord()
    {
        // PS: if ($SqlInstance) { $InputObject += Get-DbaDatabase ... }, built before the first key is read.
        // Correction sqlinstance-read-once: a command-line -SqlInstance is read after the first record's piped databases and
        // not again, where the pin reads it for every piped record and repeats its keys.
        List<SmoDatabase?> databases = new(InputObject ?? Array.Empty<SmoDatabase>());
        if (LanguagePrimitives.IsTrue(SqlInstance) && !_instancesRead)
        {
            _instancesRead = true;
            databases.AddRange(GatherDatabases());
        }

        foreach (SmoDatabase? database in databases)
        {
            if (database is null || !database.IsAccessible)
            {
                WriteMessage(MessageLevel.Warning, String.Format("{0} is not accessible, skipping", database));
                continue;
            }

            object? key;
            try
            {
                key = database.Parent.DatabaseEngineType == DatabaseEngineType.SqlAzureDatabase ? ReadAzureKey(database) : ReadKey(database);
            }
            catch (Exception failure) when (failure is not PipelineStoppedException)
            {
                // Correction refused-key-read: an audit must not report a read that failed as no key.
                StopFunction(String.Format("Failure reading the encryption key of the {0} database on {1}", database, database.Parent.Name), target: database, exception: failure, continueLoop: true);
                continue;
            }
            if (key is null)
            {
                WriteMessage(MessageLevel.Verbose, String.Format("No encryption key exists in the {0} database on {1}", database, database.Parent.Name), database);
                continue;
            }

            // PS: Add-Member -Force replaces the notes an earlier call left on the same SMO object, then Select-DefaultView.
            // Correction raw-database-instance: the instance columns come from the database's server, so a database piped
            // straight from SMO, which has no Get-DbaDatabase notes, reports them too.
            PSObject output = PSObject.AsPSObject(key);
            foreach (string property in InstanceProperties)
                output.Properties.Remove(property);
            output.Properties.Remove("Database");
            OutputHelper.AddInstanceProperties(output, database.Parent);
            output.Properties.Add(new PSNoteProperty("Database", database.Name));
            OutputHelper.SetDefaultDisplayPropertySet(output, DisplaySet);
            WriteObject(output);
        }
    }

    // PS: $db.DatabaseEncryptionKey | Where-Object EncryptionAlgorithm.
    // Corrections aes128-key and refused-key-read: that filter drops Aes128, the value 0, and takes a read that failed as no
    // value. The engine's own row says whether the key exists, and a read that fails reaches the caller.
    private static DatabaseEncryptionKey? ReadKey(SmoDatabase database)
    {
        string sql = String.Format(CultureInfo.InvariantCulture, KeyCountSql, database.ID);
        if (Convert.ToInt32(database.Parent.ConnectionContext.ExecuteScalar(sql), CultureInfo.InvariantCulture) == 0)
            return null;

        // Read here, so a failure is this command's and not the next one's in the pipeline.
        DatabaseEncryptionKey key = database.DatabaseEncryptionKey;
        _ = key.EncryptionAlgorithm;
        return key;
    }

    // Correction azure-database-key: SMO's key cannot load on Azure SQL Database (no cloud enumerator, and it joins
    // master.sys.certificates), so that engine's own view supplies the same properties. The service holds the protector, so
    // no view names it and EncryptorName stays empty.
    private static PSObject? ReadAzureKey(SmoDatabase database)
    {
        DataSet result = database.ExecuteWithResults(AzureKeySql);
        if (result.Tables[0].Rows.Count == 0)
            return null;

        DataRow row = result.Tables[0].Rows[0];
        PSObject output = new();
        output.Properties.Add(new PSNoteProperty("CreateDate", ToValue(row["create_date"])));
        output.Properties.Add(new PSNoteProperty("EncryptionAlgorithm", ToAlgorithm(row["key_algorithm"], row["key_length"])));
        output.Properties.Add(new PSNoteProperty("EncryptionState", (DatabaseEncryptionState)Convert.ToInt32(row["encryption_state"], CultureInfo.InvariantCulture)));
        output.Properties.Add(new PSNoteProperty("EncryptionType", ToEncryptionType(row["encryptor_type"])));
        output.Properties.Add(new PSNoteProperty("EncryptorName", null));
        output.Properties.Add(new PSNoteProperty("ModifyDate", ToValue(row["modify_date"])));
        output.Properties.Add(new PSNoteProperty("OpenedDate", ToValue(row["opened_date"])));
        output.Properties.Add(new PSNoteProperty("RegenerateDate", ToValue(row["regenerate_date"])));
        output.Properties.Add(new PSNoteProperty("SetDate", ToValue(row["set_date"])));
        output.Properties.Add(new PSNoteProperty("Thumbprint", ToValue(row["encryptor_thumbprint"])));
        return output;
    }

    // SMO's enumerator maps the view the same way: AES by its length, and TRIPLE_DES_3KEY. Anything newer stays as the engine named it.
    private static object? ToAlgorithm(object algorithm, object length)
    {
        string name = algorithm as string ?? String.Empty;
        if (String.Equals(name, "TRIPLE_DES_3KEY", StringComparison.OrdinalIgnoreCase))
            return DatabaseEncryptionAlgorithm.TripleDes;
        if (String.Equals(name, "AES", StringComparison.OrdinalIgnoreCase))
        {
            switch (Convert.ToInt32(length, CultureInfo.InvariantCulture))
            {
                case 128:
                    return DatabaseEncryptionAlgorithm.Aes128;
                case 192:
                    return DatabaseEncryptionAlgorithm.Aes192;
                case 256:
                    return DatabaseEncryptionAlgorithm.Aes256;
            }
        }
        return ToValue(algorithm);
    }

    // The engine adds the padding to the name: the lab's service-managed database reports CERTIFICATE_OAEP_256.
    private static object? ToEncryptionType(object encryptor)
    {
        string name = encryptor as string ?? String.Empty;
        if (name.StartsWith("CERTIFICATE", StringComparison.OrdinalIgnoreCase))
            return DatabaseEncryptionType.ServerCertificate;
        if (name.StartsWith("ASYMMETRIC", StringComparison.OrdinalIgnoreCase))
            return DatabaseEncryptionType.ServerAsymmetricKey;
        return ToValue(encryptor);
    }

    private static object? ToValue(object value) => value is DBNull ? null : value;

    // PS: Get-DbaDatabase -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database -ExcludeDatabase $ExcludeDatabase.
    // The output is decorated and in instance order. -EnableException never reaches this call, so its Stop-Function warns.
    private List<SmoDatabase> GatherDatabases()
    {
        List<SmoDatabase> gathered = new();
        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            Server? server = Connect(instance);
            if (server is not null)
                gathered.AddRange(SelectDatabases(server));
        }
        return gathered;
    }

    private Server? Connect(DbaInstanceParameter instance)
    {
        try
        {
            WriteAttributedMessage("Connect-DbaInstance", MessageLevel.Debug, "Starting process block");
            SmoConnectionRequest request = new()
            {
                Instance = instance,
                SqlCredential = SqlCredential,
                BoundParameters = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "SqlInstance", "SqlCredential" },
                MessageCallback = (level, message) => WriteAttributedMessage("Connect-DbaInstance", level, message)
            };
            Server server = ConnectionService.GetServer(request);
            WriteAttributedMessage("Connect-DbaInstance", MessageLevel.Debug, "We are finished with this instance");
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

    private List<SmoDatabase> SelectDatabases(Server server)
    {
        List<SmoDatabase> available = new();
        foreach (SmoDatabase database in server.Databases)
            available.Add(database);
        List<string> names = available.ConvertAll(item => item.Name);
        // Correction database-wildcards: the pinned help documents wildcards for -Database, which the exact-match Get-DbaDatabase
        // call never honoured. Each instance's own names decide which pattern values are real names and stay literal.
        WildcardNameMatcher included = NameMatcher(Database, true, names);
        WildcardNameMatcher excluded = NameMatcher(ExcludeDatabase, false, names);

        return available.FindAll(database =>
            (!LanguagePrimitives.IsTrue(Database) || included.Matches(database.Name)) &&
            (!LanguagePrimitives.IsTrue(ExcludeDatabase) || !excluded.Matches(database.Name)) &&
            (database.Status & DefaultStatus) != 0);
    }

    // PS: -in compares each value with the name, ignoring case. A pattern is tried only where allowed.
    private static WildcardNameMatcher NameMatcher(string[]? values, bool allowPatterns, List<string> scope)
    {
        return WildcardNameFilter.CreateMatcher(values, allowPatterns,
            (value, name) => LanguagePrimitives.Equals(name, value, true, CultureInfo.InvariantCulture), scope);
    }
}
