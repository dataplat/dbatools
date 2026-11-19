#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;
using SmoDatabase = Microsoft.SqlServer.Management.Smo.Database;

namespace Dataplat.Dbatools.Commands;

// Port of public/Get-DbaDbAsymmetricKey.ps1 at refs/pins/dbatools-2026-10-22: the nested Get-DbaDatabase selection and
// the decorated $db.AsymmetricKeys with their default view.
/// <summary>Retrieves asymmetric keys from SQL Server databases for encryption management and security auditing</summary>
/// <para>
/// Retrieves asymmetric keys stored in SQL Server databases, including their encryption algorithms, key lengths, owners, and thumbprints.
/// This function is essential for security audits and encryption key management, allowing DBAs to inventory all asymmetric keys across databases without manually querying system catalogs.
/// Asymmetric keys are used for encryption, digital signatures, and certificate creation in SQL Server's transparent data encryption and column-level encryption features.
/// Returns detailed key properties to help with compliance reporting and security assessments.
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaDbAsymmetricKey -SqlInstance sql2016
/// </code>
/// <para>
/// Gets all Asymmetric Keys
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaDbAsymmetricKey -SqlInstance Server1 -Database db1
/// </code>
/// <para>
/// Gets the Asymmetric Keys for the db1 database
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaDbAsymmetricKey -SqlInstance Server1 -Database db1 -Name key1
/// </code>
/// <para>
/// Gets the key1 Asymmetric Key within the db1 database
/// </para>
/// </example>
/// <list type="alertSet">
/// <item>
/// <term />
/// <description>
/// <para>
/// Tags: Certificate, Security
/// Author: Stuart Moore (@napalmgram), stuart-moore.com
/// </para>
/// <para>
/// Website: https://dbatools.io
/// Copyright: (c) 2018 by dbatools, licensed under MIT
/// License: MIT https://opensource.org/licenses/MIT
/// </para>
/// </description>
/// </item>
/// </list>
/// <seealso href="https://dbatools.io/Get-DbaDbAsymmetricKey" />
[Cmdlet(VerbsCommon.Get, "DbaDbAsymmetricKey")]
[OutputType(typeof(AsymmetricKey))]
public sealed class GetDbaDbAsymmetricKeyCommand : DbaInstanceCmdlet
{
    // PS: Select-DefaultView -Property ComputerName, InstanceName, SqlInstance, Database, Name, Owner, KeyEncryptionAlgorithm,
    // KeyLength, PrivateKeyEncryptionType, Thumbprint
    private static readonly string[] DisplaySet =
    {
        "ComputerName", "InstanceName", "SqlInstance", "Database", "Name", "Owner", "KeyEncryptionAlgorithm", "KeyLength",
        "PrivateKeyEncryptionType", "Thumbprint"
    };

    private static readonly string[] InstanceProperties = { "ComputerName", "InstanceName", "SqlInstance" };

    // Get-DbaDatabase's default -Status, any overlap sufficient.
    private const DatabaseStatus DefaultStatus = DatabaseStatus.Normal | DatabaseStatus.Restoring |
        DatabaseStatus.RecoveryPending | DatabaseStatus.Recovering | DatabaseStatus.Suspect |
        DatabaseStatus.Offline | DatabaseStatus.Standby | DatabaseStatus.EmergencyMode;

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
    /// Specifies which databases to scan for asymmetric keys. Accepts wildcards for pattern matching.
    /// Use this when you need to audit encryption keys in specific databases instead of scanning all databases on the instance.
    /// Essential for targeted security assessments or compliance audits of particular applications.
    /// </para>
    [Parameter(Position = 2)]
    public string[]? Database { get; set; }

    /// <para>
    /// Excludes specific databases from the asymmetric key scan. Accepts wildcards for pattern matching.
    /// Use this to skip system databases, test databases, or databases known to not contain encryption keys.
    /// Helps focus audits on production databases and reduces noise in security assessments.
    /// </para>
    [Parameter(Position = 3)]
    public string[]? ExcludeDatabase { get; set; }

    /// <para>
    /// Filters results to asymmetric keys with specific names. Accepts wildcards and multiple key names.
    /// Use this when tracking specific keys during key rotation, compliance audits, or troubleshooting encryption issues.
    /// Common when validating that required encryption keys exist across multiple databases.
    /// </para>
    [Parameter(Position = 4)]
    public string[]? Name { get; set; }

    /// <para>
    /// Accepts database objects from the pipeline, typically from Get-DbaDatabase.
    /// Use this to chain database filtering with key retrieval, such as getting keys from databases with specific properties.
    /// Enables advanced filtering scenarios like scanning only databases created after a certain date or with particular owners.
    /// </para>
    [Parameter(ValueFromPipeline = true, Position = 5)]
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
        // PS: if ($SqlInstance) { $InputObject += Get-DbaDatabase ... }, built before the first key is read.
        List<SmoDatabase?> databases = new(InputObject ?? Array.Empty<SmoDatabase>());
        if (LanguagePrimitives.IsTrue(SqlInstance))
            databases.AddRange(GatherDatabases());

        foreach (SmoDatabase? database in databases)
        {
            if (database is null || !database.IsAccessible)
            {
                WriteMessage(MessageLevel.Warning, String.Format("{0} is not accessible, skipping", database));
                continue;
            }

            AsymmetricKeyCollection? collection = database.AsymmetricKeys;
            if (collection is null)
            {
                // The pinned command has no instance variable in this scope.
                WriteMessage(MessageLevel.Verbose, String.Format("No Asymmetic Keys exists in the {0} database on ", database), database);
                continue;
            }

            List<AsymmetricKey>? keys = ReadKeys(collection);
            if (keys is null)
                continue;

            foreach (AsymmetricKey key in keys)
            {
                // PS: Add-Member -Force replaces the notes an earlier call left on the same SMO object, then Select-DefaultView.
                // Correction raw-database-instance: the instance columns come from the database's server, so a database
                // piped straight from SMO, which has no Get-DbaDatabase notes, reports them too.
                PSObject output = PSObject.AsPSObject(key);
                foreach (string property in InstanceProperties)
                    output.Properties.Remove(property);
                output.Properties.Remove("Database");
                output.Properties.Remove("DatabaseId");
                OutputHelper.AddInstanceProperties(output, database.Parent);
                output.Properties.Add(new PSNoteProperty("Database", database.Name));
                output.Properties.Add(new PSNoteProperty("DatabaseId", database.ID));
                OutputHelper.SetDefaultDisplayPropertySet(output, DisplaySet);
                WriteObject(output);
            }
        }
    }

    // PS: Get-DbaDatabase -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database -ExcludeDatabase $ExcludeDatabase.
    // The output is decorated and in instance order. -EnableException never reaches this call, so its Stop-Function warns.
    private List<SmoDatabase> GatherDatabases()
    {
        List<SmoDatabase> gathered = new();
        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            Server server;
            try
            {
                WriteAttributedMessage("Connect-DbaInstance", MessageLevel.Debug, "Starting process block");
                server = ConnectionService.GetServer(new SmoConnectionRequest
                {
                    Instance = instance,
                    SqlCredential = SqlCredential,
                    BoundParameters = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "SqlInstance", "SqlCredential" },
                    MessageCallback = (level, message) => WriteAttributedMessage("Connect-DbaInstance", level, message)
                });
                WriteAttributedMessage("Connect-DbaInstance", MessageLevel.Debug, "We are finished with this instance");
            }
            catch (Exception failure) when (failure is not PipelineStoppedException)
            {
                ErrorRecord record = new(failure, "dbatools_Get-DbaDatabase", ErrorCategory.ConnectionError, instance);
                WarnNestedStopFunction("Get-DbaDatabase", "Failure", instance, record, ErrorCategory.ConnectionError);
                continue;
            }
            SetActiveConnection(server.ConnectionContext);

            // Correction database-wildcards: the pinned help documents wildcards here, which the exact-match Get-DbaDatabase
            // call never honoured. Each instance's own names decide which pattern values are real names and stay literal.
            List<SmoDatabase> available = new();
            foreach (SmoDatabase database in server.Databases)
                available.Add(database);
            WildcardNameMatcher included = NameMatcher(Database, true, available.ConvertAll(item => item.Name));
            WildcardNameMatcher excluded = NameMatcher(ExcludeDatabase, true, available.ConvertAll(item => item.Name));
            foreach (SmoDatabase database in available)
            {
                if (LanguagePrimitives.IsTrue(Database) && !included.Matches(database.Name))
                    continue;
                if (LanguagePrimitives.IsTrue(ExcludeDatabase) && excluded.Matches(database.Name))
                    continue;
                if ((database.Status & DefaultStatus) == 0)
                    continue;

                PSObject decorated = PSObject.AsPSObject(database);
                foreach (string property in InstanceProperties)
                    decorated.Properties.Remove(property);
                OutputHelper.AddInstanceProperties(decorated, server);
                gathered.Add(database);
            }
        }
        return gathered;
    }

    // PS: foreach ($akey in $akeys), after $akeys | Where-Object Name -in $Name under -Name. SMO loads the collection when
    // it is enumerated, so a denied read faults here.
    private List<AsymmetricKey>? ReadKeys(AsymmetricKeyCollection collection)
    {
        List<AsymmetricKey> keys = new();
        IEnumerator? enumerator = null;
        try
        {
            enumerator = LanguagePrimitives.GetEnumerator(collection);
            while (enumerator is not null && enumerator.MoveNext())
                keys.Add((AsymmetricKey)enumerator.Current);
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            // The engine's record when the failure carries one (ExceptionInGetEnumerator); otherwise the record a failing
            // MoveNext gives (BadEnumeration, InvalidOperation, the enumerator as target).
            ErrorRecord record;
            if (failure is IContainsErrorRecord container && container.ErrorRecord is not null)
                record = new ErrorRecord(container.ErrorRecord, failure);
            else
            {
                RuntimeException fault = new(String.Format(CultureInfo.InvariantCulture,
                    "An error occurred while enumerating through a collection: {0}.", failure.Message), failure);
                record = new ErrorRecord(fault, "BadEnumeration", ErrorCategory.InvalidOperation, enumerator);
            }
            // caller-try: continue -- read-only; no input dropped, no stale rows; the other databases are still read, once each
            if (EnableException)
                ThrowTerminatingError(record); // style-ok: cs-raw-streams pinned statement fault outside Stop-Function
            WriteError(record);
            return null;
        }

        // Correction name-wildcards: the pinned help documents wildcards for -Name, which -in never honoured.
        if (!LanguagePrimitives.IsTrue(Name))
            return keys;
        WildcardNameMatcher matcher = NameMatcher(Name, true, keys.ConvertAll(item => item.Name));
        return keys.FindAll(item => matcher.Matches(item.Name));
    }

    // PS: -in compares each value with the name, ignoring case. A pattern is tried only where allowed (rule E+), and the
    // scope's real names stay literal.
    private static WildcardNameMatcher NameMatcher(string[]? values, bool allowPatterns, List<string> scope)
    {
        return WildcardNameFilter.CreateMatcher(values, allowPatterns,
            (value, name) => LanguagePrimitives.Equals(name, value, true, CultureInfo.InvariantCulture), scope);
    }
}
