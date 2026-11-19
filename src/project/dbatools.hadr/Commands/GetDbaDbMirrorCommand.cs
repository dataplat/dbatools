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

namespace Dataplat.Dbatools.Commands;

// Port of public/Get-DbaDbMirror.ps1 at refs/pins/dbatools-2026-10-22: the nested Get-DbaDatabase selection, the databases that name a
// mirroring partner, then one object of its own for each row of sys.database_mirroring_witnesses (operator, 2026-11-02, option B).
/// <summary>Retrieves database mirroring configuration and status for mirrored databases and their witness servers</summary>
/// <para>This command collects detailed mirroring information from databases configured with SQL Server Database Mirroring, including partner servers, witness servers, safety levels, and synchronization status. It queries both the database properties and the sys.database_mirroring_witnesses system view to provide complete mirroring topology details. Use this when you need to audit your mirroring setup, troubleshoot mirroring issues, or verify mirroring configuration across multiple instances without manually checking each database's mirroring properties in SSMS.</para>
/// <list type="alertSet">
///   <item>
///     <term></term>
///     <description>
///       <para>Tags: Mirroring, Mirror, HA</para>
///       <para>Author: Chrissy LeMaire (@cl), netnerds.net</para>
///       <para>Website: https://dbatools.io</para>
///       <para>Copyright: (c) 2018 by dbatools, licensed under MIT</para>
///       <para>License: MIT https://opensource.org/licenses/MIT</para>
///     </description>
///   </item>
/// </list>
/// <example>
///   <prefix>PS C:\&gt;</prefix>
///   <code>Get-DbaDbMirror -SqlInstance localhost</code>
///   <para>Gets properties of database mirrors and mirror witnesses on localhost</para>
/// </example>
/// <example>
///   <prefix>PS C:\&gt;</prefix>
///   <code>Get-DbaDbMirror -SqlInstance localhost, sql2016</code>
///   <para>Gets properties of database mirrors and mirror witnesses on localhost and sql2016 SQL Server instances</para>
/// </example>
/// <example>
///   <prefix>PS C:\&gt;</prefix>
///   <code>Get-DbaDbMirror -SqlInstance localhost, sql2016 -Database mymirror</code>
///   <para>Gets properties of database mirrors and mirror witnesses on localhost and sql2016 SQL Server instances for databases named mymirror</para>
/// </example>
/// <seealso href="https://dbatools.io/Get-DbaDbMirror"/>
[Cmdlet(VerbsCommon.Get, "DbaDbMirror")]
public sealed class GetDbaDbMirrorCommand : DbaInstanceCmdlet
{
    // PS: the Get-DbaDatabase query for SQL Server 2008 and later. Its rows set the database order.
    private const string DatabasesQuery = "SELECT name, state, SUSER_SNAME(owner_sid) AS [Owner], is_cdc_enabled FROM sys.databases";

    // PS: the Get-DbaDatabase query behind a Size that SMO cannot report, as for a mirror copy that is restoring.
    private const string SizesQuery = @"SELECT DB_NAME(database_id) AS name,
                    CAST(SUM(CAST(size AS BIGINT)) * 8.0 / 1024 AS DECIMAL(18,2)) AS SizeMB
                FROM sys.master_files
                GROUP BY database_id";

    // PS: the witness query, verbatim.
    private const string WitnessQuery = "SELECT DISTINCT database_name, principal_server_name, safety_level, safety_level_desc, partner_sync_state FROM master.sys.database_mirroring_witnesses";

    // Get-DbaDatabase's default -Status, any overlap sufficient.
    private const DatabaseStatus DefaultStatus = DatabaseStatus.Normal | DatabaseStatus.Restoring |
        DatabaseStatus.RecoveryPending | DatabaseStatus.Recovering | DatabaseStatus.Suspect |
        DatabaseStatus.Offline | DatabaseStatus.Standby | DatabaseStatus.EmergencyMode;

    private static readonly string[] DisplayProperties =
    {
        "ComputerName", "InstanceName", "SqlInstance", "Name", "MirroringSafetyLevel", "MirroringStatus", "MirroringPartner",
        "MirroringPartnerInstance", "MirroringFailoverLogSequenceNumber", "MirroringID", "MirroringRedoQueueMaxSize",
        "MirroringRoleSequence", "MirroringSafetySequence", "MirroringTimeout", "MirroringWitness", "MirroringWitnessStatus"
    };

    /// <para>The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function</para>
    /// <para>to be executed against multiple SQL Server instances.</para>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public override DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <para>Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).</para>
    /// <para>Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.</para>
    /// <para>For MFA support, please use Connect-DbaInstance.</para>
    [Parameter(Position = 1)]
    public override PSCredential? SqlCredential { get; set; }

    /// <para>Specifies which databases to check for mirroring configuration. Accepts multiple database names and supports wildcards.</para>
    /// <para>Use this when you want to examine mirroring status for specific databases instead of checking all databases on the instance.</para>
    [Parameter(Position = 2)]
    [PsStringArrayCast]
    public string[]? Database { get; set; }

    // Overridden only to carry the pinned .PARAMETER EnableException help; same bare [Parameter] as the base.
    /// <para>By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.</para>
    /// <para>This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.</para>
    /// <para>Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.</para>
    [Parameter]
    public override SwitchParameter EnableException { get; set; }

    protected override void ProcessRecord()
    {
        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            Server? server = OpenServer(instance);
            if (server is null)
                continue;

            // PS: $partners = $dbs | Where-Object MirroringPartner, each written with its own default view.
            foreach (PSObject output in SelectDatabases(server))
            {
                if (LanguagePrimitives.IsTrue(ReadMember(output, "MirroringPartner")))
                    WriteDatabase(output);
            }

            // PS: the witness read and its loop. The read now runs even when -Database leaves no local database, where the pin's $dbs[0]
            // failed into its catch (correction witness-rows).
            DataTable? witnesses = ReadWitnesses(server);
            if (witnesses is not null)
                WriteWitnesses(server, witnesses);
        }
    }

    // PS: Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential, inside Get-DbaDatabase's own try. The pinned command
    // never passes -EnableException on, so a failed connection warns under Get-DbaDatabase's name and the next instance is read.
    private Server? OpenServer(DbaInstanceParameter instance)
    {
        SmoConnectionRequest request = new();
        request.Instance = instance;
        request.SqlCredential = SqlCredential;
        // Correction azure-refusal: Azure SQL Database has no database mirroring, and the pin returned nothing with no word of why.
        request.AzureUnsupported = true;
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
        catch (ConnectionResolutionException refusal) when (refusal.Kind == ConnectionResolutionFailure.AzureUnsupported)
        {
            ErrorRecord record = new(refusal, "dbatools_Get-DbaDbMirror", ErrorCategory.ConnectionError, instance);
            StopFunction("Failure", target: instance, errorRecord: record, category: ErrorCategory.ConnectionError, continueLoop: true);
            return null;
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            ErrorRecord record = new(failure, "dbatools_Get-DbaDatabase", ErrorCategory.ConnectionError, instance);
            WarnNestedStopFunction("Get-DbaDatabase", "Failure", instance, record, ErrorCategory.ConnectionError);
            return null;
        }
    }

    // PS: the Where-Object filters of Get-DbaDatabase, by name in the order sys.databases gave, with what it adds to each database.
    // Correction database-wildcards: the pinned help documents wildcards for -Database, which the literal -in never honoured. The
    // instance's own names decide which pattern values are real names and stay literal.
    private List<PSObject> SelectDatabases(Server server)
    {
        List<PSObject> selected = new();
        DataTable? rows = ReadDatabases(server);
        if (rows is null)
            return selected;

        List<string> names = new();
        foreach (DataRow row in rows.Rows)
            names.Add((string)row["name"]);
        WildcardNameMatcher included = CreateDatabaseMatcher(names);

        DataTable? sizes = ReadSizes(server);
        foreach (DataRow row in rows.Rows)
        {
            string name = (string)row["name"];
            if (LanguagePrimitives.IsTrue(Database) && !included.Matches(name))
                continue;
            SmoDatabase? database = server.Databases[name];
            if (database is not null && (database.Status & DefaultStatus) != 0)
                selected.Add(AddDatabaseMembers(database, server, row["is_cdc_enabled"], sizes));
        }
        return selected;
    }

    // The -Database comparison, case-insensitive as -in is, over the names in scope, which also decide which pattern values stay literal.
    private WildcardNameMatcher CreateDatabaseMatcher(List<string> names)
    {
        return WildcardNameFilter.CreateMatcher(Database, true,
            (value, name) => LanguagePrimitives.Equals(name, value, true, CultureInfo.InvariantCulture), names);
    }

    // PS: Invoke-QueryRawDatabases. Its Stop-Function has no -Continue, and the empty result then ends the instance.
    private DataTable? ReadDatabases(Server server)
    {
        try
        {
            return server.ConnectionContext.ExecuteWithResults(DatabasesQuery).Tables[0];
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            ErrorRecord record = new(failure, "dbatools_Get-DbaDatabase", ErrorCategory.NotSpecified, null);
            WarnNestedStopFunction("Get-DbaDatabase", "Failure", errorRecord: record);
            return null;
        }
    }

    // PS: Invoke-QueryDatabaseSizes, whose failure leaves every Size as SMO reports it.
    private DataTable? ReadSizes(Server server)
    {
        try
        {
            return server.ConnectionContext.ExecuteWithResults(SizesQuery).Tables[0];
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            WriteAttributedMessage("Get-DbaDatabase", MessageLevel.Warning, "Could not retrieve database sizes via T-SQL: " + failure.Message);
            return null;
        }
    }

    // PS: the Add-Member calls of Get-DbaDatabase, in its order, then the aliases its Select-DefaultView adds.
    private static PSObject AddDatabaseMembers(SmoDatabase database, Server server, object isCdcEnabled, DataTable? sizes)
    {
        PSObject output = PSObject.AsPSObject(database);
        object? size = ReadSize(output, database.Name, sizes);

        SetNote(output, "BackupStatus", null);
        foreach (string property in new[] { "ComputerName", "InstanceName", "SqlInstance" })
            output.Properties.Remove(property);
        OutputHelper.AddInstanceProperties(output, server);
        SetNote(output, "LastRead", null);
        SetNote(output, "LastWrite", null);
        SetNote(output, "IsCdcEnabled", isCdcEnabled);
        if (size is not null)
            SetNote(output, "Size", size);

        SetAlias(output, "SizeMB", "Size");
        SetAlias(output, "Compatibility", "CompatibilityLevel");
        SetAlias(output, "Encrypted", "EncryptionEnabled");
        SetAlias(output, "LastFullBackup", "LastBackupDate");
        SetAlias(output, "LastDiffBackup", "LastDifferentialBackupDate");
        SetAlias(output, "LastLogBackup", "LastLogBackupDate");
        return output;
    }

    // PS: $db.Size, and the sizes query's row for a Size that is null or 0. The first read fails or gives 0 on a restoring mirror copy,
    // and the query's value is a decimal (evidence/pin-mirror-r2-20261102.txt).
    private static object? ReadSize(PSObject output, string name, DataTable? sizes)
    {
        object? size = ReadMember(output, "Size");
        if (sizes is null || (size is not null && !LanguagePrimitives.Equals(size, 0)))
            return size;
        foreach (DataRow row in sizes.Rows)
        {
            if (LanguagePrimitives.Equals(row["name"], name, true, CultureInfo.InvariantCulture))
                return row["SizeMB"];
        }
        return size;
    }

    // PS: try { $witnesses = $dbs[0].Parent.Query(...) } catch { continue }.
    private static DataTable? ReadWitnesses(Server server)
    {
        try
        {
            return server.ConnectionContext.ExecuteWithResults(WitnessQuery).Tables[0];
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            // A failed witness read moves on to the next instance with no record, as the pin's catch does: the operator kept that
            // when approving the witness rows (2026-11-02, answer.txt).
            return null;
        }
    }

    // PS: foreach ($witness in $witnesses). Corrections witness-rows and witness-overlay (operator, 2026-11-02): one object of its own for
    // each row that -Database selects, whether or not the witness server holds a database of that name. The pin wrote nothing for a
    // witness that holds none, which is how a witness is set up, and over one that did it overwrote that unrelated database's members.
    private void WriteWitnesses(Server server, DataTable witnesses)
    {
        List<string> names = new();
        foreach (DataRow witness in witnesses.Rows)
            names.Add((string)witness["database_name"]);
        WildcardNameMatcher included = CreateDatabaseMatcher(names);

        foreach (DataRow witness in witnesses.Rows)
        {
            if (LanguagePrimitives.IsTrue(Database) && !included.Matches((string)witness["database_name"]))
                continue;
            PSObject output = new();
            OutputHelper.AddInstanceProperties(output, server);
            for (int index = 3; index < DisplayProperties.Length; index++)
                output.Properties.Add(new PSNoteProperty(DisplayProperties[index], WitnessValue(DisplayProperties[index], witness)));
            WriteObject(output);
        }
    }

    // The values the pin's loop took from a witness row; the rest of the sixteen names have no value on a witness.
    private static object? WitnessValue(string property, DataRow witness)
    {
        object? value = property switch
        {
            "Name" => witness["database_name"],
            "MirroringSafetyLevel" => witness["safety_level_desc"],
            "MirroringPartner" => witness["principal_server_name"],
            "MirroringWitnessStatus" => WitnessStatus(witness["partner_sync_state"]),
            _ => null
        };
        return value is DBNull ? null : value;
    }

    // PS: the switch on partner_sync_state. Correction witness-out-of-sync: the view reports 6 for partners that are not synchronized,
    // which the pin's switch did not name, so that row's status was null; 6 is now OutOfSync. Any other unnamed value stays null.
    private static string? WitnessStatus(object state)
    {
        return state switch
        {
            (byte)0 => "None",
            (byte)1 => "Suspended",
            (byte)2 => "Disconnected",
            (byte)3 => "Synchronizing",
            (byte)4 => "PendingFailover",
            (byte)5 => "Synchronized",
            (byte)6 => "OutOfSync",
            _ => null
        };
    }

    // PS: Select-DefaultView -Property ComputerName, InstanceName, ...
    private void WriteDatabase(PSObject output)
    {
        OutputHelper.SetDefaultDisplayPropertySet(output, DisplayProperties);
        WriteObject(output);
    }

    // PS: $db.Name-style member access, which sees a member added earlier and reads a getter that fails as $null, with no record.
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

    // PS: Add-Member -Force -MemberType AliasProperty.
    private static void SetAlias(PSObject output, string name, string referenced)
    {
        output.Properties.Remove(name);
        output.Properties.Add(new PSAliasProperty(name, referenced));
    }
}
