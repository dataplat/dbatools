#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Data;
using System.Globalization;
using System.Linq;
using System.Management.Automation;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;
using SmoDatabase = Microsoft.SqlServer.Management.Smo.Database;

namespace Dataplat.Dbatools.Commands;

// Port of public/Get-DbaDbEncryption.ps1 at refs/pins/dbatools-2026-10-22: the database selection, then for each database
// its TDE row and one row per certificate, asymmetric key and symmetric key.
/// <summary>Retrieves comprehensive encryption inventory from SQL Server databases including TDE status, certificates, and keys.</summary>
/// <para>
/// Audits database-level encryption across SQL Server instances by examining TDE encryption status, certificates, asymmetric keys, and symmetric keys within each database. Returns detailed information including key algorithms, lengths, owners, backup dates, and expiration dates for compliance reporting and security assessments. Particularly useful for encryption audits, certificate lifecycle management, and ensuring regulatory compliance across your SQL Server environment.
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaDbEncryption -SqlInstance DEV01
/// </code>
/// <para>
/// List all encryption found on the instance by database
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaDbEncryption -SqlInstance DEV01 -Database MyDB
/// </code>
/// <para>
/// List all encryption found for the MyDB database.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaDbEncryption -SqlInstance DEV01 -ExcludeDatabase MyDB
/// </code>
/// <para>
/// List all encryption found for all databases except MyDB.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaDbEncryption -SqlInstance DEV01 -IncludeSystemDBs
/// </code>
/// <para>
/// List all encryption found for all databases including the system databases.
/// </para>
/// </example>
/// <list type="alertSet">
/// <item>
/// <term />
/// <description>
/// <para>
/// Tags: Encryption
/// Author: Stephen Bennett, sqlnotesfromtheunderground.wordpress.com
/// </para>
/// <para>
/// Website: https://dbatools.io
/// Copyright: (c) 2018 by dbatools, licensed under MIT
/// License: MIT https://opensource.org/licenses/MIT
/// </para>
/// </description>
/// </item>
/// </list>
/// <seealso href="https://dbatools.io/Get-DbaDbEncryption" />
[Cmdlet(VerbsCommon.Get, "DbaDbEncryption")]
public sealed class GetDbaDbEncryptionCommand : DbaInstanceCmdlet
{
    private const string KeyAlgorithmQuery = "SELECT key_algorithm, key_length FROM sys.dm_database_encryption_keys WHERE database_id = DB_ID();";

    private const string KeyEncryptionsQuery = "SELECT sk.name, ke.crypt_type FROM sys.key_encryptions AS ke " +
        "INNER JOIN sys.symmetric_keys AS sk ON sk.symmetric_key_id = ke.key_id ORDER BY sk.name, ke.crypt_type;";

    /// <para>
    /// The target SQL Server instance or instances. This can be a collection and receive pipeline input.
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
    /// Specifies which databases to examine for encryption objects including TDE, certificates, and keys. Accepts database names as strings or arrays.
    /// Use this to focus encryption audits on specific databases rather than scanning all user databases on the instance.
    /// </para>
    [Parameter(Position = 2)]
    public object[]? Database { get; set; }

    /// <para>
    /// Excludes specific databases from the encryption inventory scan. Useful when you need to audit most databases but skip certain ones.
    /// Commonly used to exclude databases with known encryption issues or maintenance databases that don't require encryption compliance checks.
    /// </para>
    [Parameter(Position = 3)]
    public object[]? ExcludeDatabase { get; set; }

    /// <para>
    /// Includes system databases (master, model, msdb, tempdb) in the encryption inventory. By default, only user databases are scanned.
    /// Use this when conducting comprehensive security audits that require visibility into system database encryption objects and TDE configurations.
    /// </para>
    [Parameter]
    public SwitchParameter IncludeSystemDBs { get; set; }

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
        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            Server? server = ConnectInstance(instance);
            if (server is null)
                continue;

            List<SmoDatabase>? databases = GatherDatabases(server, instance);
            if (databases is null)
                continue;

            foreach (SmoDatabase database in databases)
            {
                WriteMessage(MessageLevel.Verbose, String.Format(CultureInfo.InvariantCulture, "Processing {0}", database));

                // PS: Stop-Function -Continue in the TDE branch leaves this database's objects unread.
                if (LanguagePrimitives.IsTrue(Member(database, "EncryptionEnabled")) && !WriteEncryptionRow(server, database, instance))
                    continue;

                foreach (Certificate certificate in ReadObjects<Certificate>(database.Certificates))
                    WriteObject(CertificateRow(server, database, certificate));

                foreach (AsymmetricKey key in ReadObjects<AsymmetricKey>(database.AsymmetricKeys))
                    WriteObject(AsymmetricKeyRow(server, database, key));

                List<SymmetricKey> symmetricKeys = ReadObjects<SymmetricKey>(database.SymmetricKeys);
                if (symmetricKeys.Count == 0)
                    continue;

                Dictionary<string, object> keyEncryptions = ReadKeyEncryptions(database);
                foreach (SymmetricKey key in symmetricKeys)
                {
                    keyEncryptions.TryGetValue(key.Name, out object? keyEncryption);
                    WriteObject(SymmetricKeyRow(server, database, key, keyEncryption));
                }
            }
        }
    }

    // PS: the try around the Where-Object filters; a failed enumeration reaches its catch, which carries no record of its
    // own. -Database takes offline databases too. $_.IsSystemObject -eq 0 is false for null as well as for true.
    private List<SmoDatabase>? GatherDatabases(Server server, DbaInstanceParameter instance)
    {
        try
        {
            List<SmoDatabase> databases = new();
            foreach (SmoDatabase database in server.Databases)
            {
                bool selected;
                if (LanguagePrimitives.IsTrue(Database))
                    selected = NameIn(database, Database);
                else if (IncludeSystemDBs.ToBool())
                    selected = LanguagePrimitives.IsTrue(Member(database, "IsAccessible"));
                else
                    selected = LanguagePrimitives.IsTrue(Member(database, "IsAccessible")) && Member(database, "IsSystemObject") is false;

                if (selected && !(LanguagePrimitives.IsTrue(ExcludeDatabase) && NameIn(database, ExcludeDatabase)))
                    databases.Add(database);
            }
            return databases;
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            StopFunction(String.Format(CultureInfo.InvariantCulture, "Unable to gather dbs for {0}", instance), target: instance, continueLoop: true);
            return null;
        }
    }

    // PS: Where-Object Name -In $values compares with each value as the left operand, ignoring case.
    private static bool NameIn(SmoDatabase database, object[]? values)
    {
        string name = database.Name;
        return values is not null && values.Any(value => LanguagePrimitives.Equals(value, name, true, CultureInfo.InvariantCulture));
    }

    // False when Stop-Function -Continue ended this database. Azure SQL Database gives no DatabaseEncryptionKey object, and
    // tempdb's key has no server certificate, so their rows name no certificate.
    private bool WriteEncryptionRow(Server server, SmoDatabase database, DbaInstanceParameter instance)
    {
        object? key = Member(database, "DatabaseEncryptionKey");
        if (Member(key, "EncryptionType") is not DatabaseEncryptionType.ServerCertificate)
        {
            // Correction tde-key-algorithm: the pin filled the algorithm only with a server certificate.
            WriteObject(NewRow(server, database, "EncryptionEnabled (TDE)", null, null, null, ReadKeyAlgorithm(database), null, null, null, null));
            return true;
        }

        byte[]? thumbprint = Member(key, "Thumbprint") as byte[];
        Certificate? certificate = ReadObjects<Certificate>(server.Databases["master"]?.Certificates)
            .Find(candidate => thumbprint is not null && Member(candidate, "Thumbprint") is byte[] candidateThumbprint && candidateThumbprint.SequenceEqual(thumbprint));
        if (certificate is null)
        {
            // PS: $($db.DatabaseEncryptionKey.Name) reads a member DatabaseEncryptionKey does not have.
            StopFunction("Could not locate TDE server certificate ", target: instance, continueLoop: true);
            return false;
        }

        WriteObject(NewRow(server, database, "EncryptionEnabled (TDE)", Member(certificate, "Name"), Member(certificate, "LastBackupDate"),
            Member(certificate, "PrivateKeyEncryptionType"), Member(key, "EncryptionAlgorithm"), null, Member(certificate, "Owner"), certificate,
            Member(certificate, "ExpirationDate")));
        return true;
    }

    private static PSObject CertificateRow(Server server, SmoDatabase database, Certificate certificate)
    {
        return NewRow(server, database, "Certificate", Member(certificate, "Name"), Member(certificate, "LastBackupDate"),
            Member(certificate, "PrivateKeyEncryptionType"), null, null, Member(certificate, "Owner"), certificate, Member(certificate, "ExpirationDate"));
    }

    private static PSObject AsymmetricKeyRow(Server server, SmoDatabase database, AsymmetricKey key)
    {
        return NewRow(server, database, "Asymmetric key", Member(key, "Name"), null, Member(key, "PrivateKeyEncryptionType"),
            Member(key, "KeyEncryptionAlgorithm"), Member(key, "KeyLength"), Member(key, "Owner"), key, null);
    }

    // Correction symmetric-instance-columns: the pin's row has only Server and Instance, which stay for the scripts that read
    // them. Correction symmetric-algorithm: the pin read $ak.EncryptionAlgorithm, the leftover asymmetric key.
    private static PSObject SymmetricKeyRow(Server server, SmoDatabase database, SymmetricKey key, object? keyEncryption)
    {
        PSObject row = new();
        OutputHelper.AddInstanceProperties(row, server);
        row.Properties.Add(new PSNoteProperty("Server", Member(server, "Name")));
        row.Properties.Add(new PSNoteProperty("Instance", Member(server, "InstanceName")));
        AddDetails(row, database, "Symmetric key", Member(key, "Name"), null, keyEncryption, Member(key, "EncryptionAlgorithm"), Member(key, "KeyLength"),
            Member(key, "Owner"), key, null);
        return row;
    }

    // Correction symmetric-key-encryption: SMO's SymmetricKey has no PrivateKeyEncryptionType and its EnumKeyEncryptions refuses
    // Azure SQL Database, so the catalog answers on both. One value for one encryption, an array in crypt_type order for several.
    private Dictionary<string, object> ReadKeyEncryptions(SmoDatabase database)
    {
        DataTable? rows = ReadCatalog(database, KeyEncryptionsQuery);
        if (rows is null)
            return new Dictionary<string, object>(StringComparer.Ordinal);

        return rows.Rows.Cast<DataRow>()
            .GroupBy(row => (string)row["name"], StringComparer.Ordinal)
            .ToDictionary(group => group.Key, group => OneOrAll(group.Select(row => EncryptedBy((string)row["crypt_type"])).Distinct().ToArray()), StringComparer.Ordinal);
    }

    private static object OneOrAll(object[] values)
    {
        return values.Length == 1 ? values[0] : values;
    }

    // sys.key_encryptions, crypt_type, on Microsoft Learn. A code Learn does not list stays visible rather than dropped.
    private static object EncryptedBy(string cryptType)
    {
        return cryptType switch
        {
            "ESKS" => SymmetricKeyEncryptionType.SymmetricKey,
            "EPUC" or "C256" => SymmetricKeyEncryptionType.Certificate,
            "EPUA" or "A256" => SymmetricKeyEncryptionType.AsymmetricKey,
            "ESKM" => SymmetricKeyEncryptionType.MasterKey,
            "ESKP" or "ESP2" or "ESP3" => SymmetricKeyEncryptionType.Password,
            _ => cryptType
        };
    }

    // The value the server certificate branch reports from SMO's DatabaseEncryptionKey.EncryptionAlgorithm.
    private object? ReadKeyAlgorithm(SmoDatabase database)
    {
        DataTable? rows = ReadCatalog(database, KeyAlgorithmQuery);
        if (rows is null || rows.Rows.Count == 0)
            return null;

        object algorithm = rows.Rows[0]["key_algorithm"];
        return (algorithm, rows.Rows[0]["key_length"]) switch
        {
            ("AES", 128) => DatabaseEncryptionAlgorithm.Aes128,
            ("AES", 192) => DatabaseEncryptionAlgorithm.Aes192,
            ("AES", 256) => DatabaseEncryptionAlgorithm.Aes256,
            ("TRIPLE_DES_3KEY", _) => DatabaseEncryptionAlgorithm.TripleDes,
            _ => algorithm
        };
    }

    // A column must not cost its row: a read that fails, for example without VIEW SERVER STATE, leaves the pin's null.
    private DataTable? ReadCatalog(SmoDatabase database, string query)
    {
        try
        {
            return database.ExecuteWithResults(query).Tables[0];
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            WriteMessage(MessageLevel.Verbose, String.Format(CultureInfo.InvariantCulture, "Unable to read the encryption details of {0}: {1}", database, failure.GetBaseException().Message));
            return null;
        }
    }

    private static PSObject NewRow(Server server, SmoDatabase database, string encryption, object? name, object? lastBackup,
        object? privateKeyEncryptionType, object? encryptionAlgorithm, object? keyLength, object? owner, object? source, object? expirationDate)
    {
        PSObject row = new();
        OutputHelper.AddInstanceProperties(row, server);
        AddDetails(row, database, encryption, name, lastBackup, privateKeyEncryptionType, encryptionAlgorithm, keyLength, owner, source, expirationDate);
        return row;
    }

    private static void AddDetails(PSObject row, SmoDatabase database, string encryption, object? name, object? lastBackup,
        object? privateKeyEncryptionType, object? encryptionAlgorithm, object? keyLength, object? owner, object? source, object? expirationDate)
    {
        row.Properties.Add(new PSNoteProperty("Database", database.Name));
        row.Properties.Add(new PSNoteProperty("Encryption", encryption));
        row.Properties.Add(new PSNoteProperty("Name", name));
        row.Properties.Add(new PSNoteProperty("LastBackup", lastBackup));
        row.Properties.Add(new PSNoteProperty("PrivateKeyEncryptionType", privateKeyEncryptionType));
        row.Properties.Add(new PSNoteProperty("EncryptionAlgorithm", encryptionAlgorithm));
        row.Properties.Add(new PSNoteProperty("KeyLength", keyLength));
        row.Properties.Add(new PSNoteProperty("Owner", owner));
        row.Properties.Add(new PSNoteProperty("Object", source));
        row.Properties.Add(new PSNoteProperty("ExpirationDate", expirationDate));
    }

    // PS: $object.Member outside strict mode. A null object, a member the type lacks and a getter that throws all read as
    // null with no error: measured on Azure ($cert.LastBackupDate) and on an offline database's key.
    private static object? Member(object? source, string name)
    {
        if (source is null)
            return null;
        try
        {
            return PSObject.AsPSObject(source).Properties[name]?.Value;
        }
        catch (GetValueException)
        {
            return null;
        }
    }

    // PS: foreach ($item in $collection). SMO loads a collection when it is enumerated, so an offline database faults here,
    // once per collection, and the statement yields nothing.
    private List<T> ReadObjects<T>(IEnumerable? collection)
    {
        List<T> items = new();
        IEnumerator? enumerator = null;
        try
        {
            enumerator = LanguagePrimitives.GetEnumerator(collection);
            while (enumerator is not null && enumerator.MoveNext())
                items.Add((T)enumerator.Current);
            return items;
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            WriteStatementFault(EnumerationFault(failure, enumerator));
            return new List<T>();
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

    // The pinned faults are statement-terminating, so what follows them depends on a caller's try, which no public API shows
    // a command.
    private void WriteStatementFault(ErrorRecord record)
    {
        // caller-try: continue -- read-only; no input dropped, no partial row; the fault is reported and every other object is still read
        if (EnableException)
            ThrowTerminatingError(record); // style-ok: cs-raw-streams pinned statement fault outside Stop-Function
        WriteError(record);
    }
}
