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
using SmoSchema = Microsoft.SqlServer.Management.Smo.Schema;

namespace Dataplat.Dbatools.Commands;

// Port of public/Get-DbaDbSchema.ps1 at refs/pins/dbatools-2026-10-22: a nested Get-DbaDatabase for each instance, then the decorated, filtered $db.Schemas with their
// default view. Measured on the pin: evidence/pin-schema-20261104.txt.
/// <summary>Retrieves database schema objects from SQL Server instances for inventory, security auditing, and management tasks</summary>
/// <para>
/// Returns SQL Server Management Object (SMO) schema objects from one or more databases, allowing you to inspect schema ownership, enumerate database organization, and identify schema-level security configurations. This function is essential for database documentation, security auditing when you need to track who owns which schemas, and migration planning where schema ownership and structure must be preserved. You can filter results by specific schema names, schema owners, or databases, and optionally include system schemas like dbo, sys, and INFORMATION_SCHEMA which are excluded by default.
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaDbSchema -SqlInstance localhost
/// </code>
/// <para>
/// Gets all non-system database schemas from all user databases on the localhost instance. Note: the dbo schema is a system schema and won't be included in the output from this example. To include the dbo schema specify -IncludeSystemSchemas
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaDbSchema -SqlInstance localhost -Schema dbo -IncludeSystemSchemas
/// </code>
/// <para>
/// Returns the dbo schema from the databases on the localhost instance.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaDbSchema -SqlInstance localhost -IncludeSystemDatabases -IncludeSystemSchemas
/// </code>
/// <para>
/// Gets all database schemas from all databases on the localhost instance.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaDbSchema -SqlInstance localhost -Schema TestSchema
/// </code>
/// <para>
/// Finds and returns the TestSchema schema from the localhost instance.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaDbSchema -SqlInstance localhost -SchemaOwner DBUser1
/// </code>
/// <para>
/// Finds and returns the schemas owned by DBUser1 from the localhost instance.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaDbSchema -SqlInstance localhost -Database TestDB -SchemaOwner DBUser1
/// </code>
/// <para>
/// Finds and returns the schemas owned by DBUser1 in the TestDB database from the localhost instance.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; $schema = Get-DbaDbSchema -SqlInstance localhost -Database TestDB -Schema TestSchema
/// PS C:\&gt; $schema.Owner = DBUser2
/// PS C:\&gt; $schema.Alter()
/// </code>
/// <para>
/// Finds the TestSchema in the TestDB on the localhost instance and then changes the schema owner to DBUser2
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; $schema = Get-DbaDbSchema -SqlInstance localhost -Database TestDB -Schema TestSchema
/// PS C:\&gt; $schema.Drop()
/// </code>
/// <para>
/// Finds the TestSchema in the TestDB on the localhost instance and then drops it. Note: to drop a schema all objects must be transferred to another schema or dropped.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; $db = Get-DbaDatabase -SqlInstance localhost -Database TestDB
/// PS C:\&gt; $schema = $db | Get-DbaDbSchema -Schema TestSchema
/// </code>
/// <para>
/// Finds the TestSchema in the TestDB which is passed via pipeline into the Get-DbaDbSchema command.
/// </para>
/// </example>
/// <list type="alertSet">
/// <item>
/// <term />
/// <description>
/// <para>
/// Tags: Database, Schema
/// Author: Adam Lancaster, github.com/lancasteradam
/// </para>
/// <para>
/// dbatools PowerShell module (https://dbatools.io)
/// Copyright: (c) 2021 by dbatools, licensed under MIT
/// License: MIT https://opensource.org/licenses/MIT
/// </para>
/// </description>
/// </item>
/// </list>
/// <seealso href="https://dbatools.io/Get-DbaDbSchema" />
[Cmdlet(VerbsCommon.Get, "DbaDbSchema", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Low)]
[OutputType(typeof(SmoSchema))]
public sealed class GetDbaDbSchemaCommand : DbaBaseCmdlet
{
    private const string DatabaseCommand = "Get-DbaDatabase";
    private const string RawDatabasesCommand = "Invoke-QueryRawDatabases";

    // PS: Select-DefaultView -Property ComputerName, InstanceName, SqlInstance, Name, IsSystemObject
    private static readonly string[] DisplaySet = { "ComputerName", "InstanceName", "SqlInstance", "Name", "IsSystemObject" };

    private static readonly string[] Notes = { "ComputerName", "InstanceName", "SqlInstance", "DatabaseName", "DatabaseId" };

    private bool _namedRead;

    /// <para>
    /// The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function
    /// to be executed against multiple SQL Server instances.
    /// </para>
    [Parameter(Position = 0)]
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
    /// Specifies which databases to retrieve schemas from. Accepts wildcards for pattern matching.
    /// Use this when you need to focus on specific databases instead of all databases on the instance.
    /// </para>
    [Parameter(Position = 2)]
    [PsStringArrayCast]
    public string[]? Database { get; set; }

    /// <para>
    /// Filters results to include only schemas with the specified names. Accepts multiple schema names.
    /// Use this when you need to check specific schemas like custom application schemas or verify particular schema configurations.
    /// </para>
    [Parameter(Position = 3)]
    [PsStringArrayCast]
    public string[]? Schema { get; set; }

    /// <para>
    /// Filters results to schemas owned by the specified database users or roles. Accepts multiple owner names.
    /// Use this for security audits to identify all schemas owned by specific users, or when troubleshooting schema ownership issues.
    /// </para>
    [Parameter(Position = 4)]
    [PsStringArrayCast]
    public string[]? SchemaOwner { get; set; }

    /// <para>
    /// Includes system databases (master, model, msdb, tempdb) in the schema retrieval.
    /// Use this when you need to audit or document schema configurations across all databases including system databases.
    /// </para>
    [Parameter]
    public SwitchParameter IncludeSystemDatabases { get; set; }

    /// <para>
    /// Includes built-in system schemas like dbo, sys, guest, and INFORMATION_SCHEMA in the results.
    /// Use this when you need complete schema inventory including system schemas, or when specifically working with dbo schema objects.
    /// </para>
    [Parameter]
    public SwitchParameter IncludeSystemSchemas { get; set; }

    /// <para>
    /// Accepts database objects from Get-DbaDatabase via pipeline input for processing.
    /// Use this to chain database operations or when you already have database objects and want to retrieve their schemas efficiently.
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

    /// <summary>Reads the schemas of the record's databases, then of each -SqlInstance.</summary>
    protected override void ProcessRecord()
    {
        List<SmoDatabase?> databases = InputObject is null ? new List<SmoDatabase?>() : new List<SmoDatabase?>(InputObject);

        // Correction named-instance-repeat: at every piped record the pin's foreach reads each -SqlInstance again, so its rows repeat (piped-databases-beside-named-instance).
        // Here the named instances are read once, at the first record.
        if (!_namedRead)
        {
            _namedRead = true;
            foreach (DbaInstanceParameter? instance in SqlInstance ?? Array.Empty<DbaInstanceParameter>())
            {
                // Get-DbaDatabase declares -SqlInstance mandatory, so its binder refuses a null element; the pin's foreach then reads the next.
                if (instance is null)
                    ReportBindingFault();
                else
                    databases.AddRange(ReadDatabases(instance));
            }
        }

        foreach (SmoDatabase? database in databases)
            WriteSchemas(database);
    }

    // Binder section, points 1 and 2, with the StatementFault section's point 5. The pin's activity follows its id suffix: the nested command when the
    // caller has no try and the call has no -ErrorAction Stop (instance-null-element-first). Under either, the fault leaves through this command, and the engine's default is the pin's.
    private void ReportBindingFault()
    {
        ErrorRecord fault = new ErrorRecord(
            new ParameterBindingException("Cannot bind argument to parameter 'SqlInstance' because it is null."),
            "ParameterArgumentValidationErrorNullNotAllowed", ErrorCategory.InvalidData, null);
        // The binder's own exception type is internal, so the record carries its public base and the Reason callers read.
        fault.CategoryInfo.Reason = "ParameterBindingValidationException";
        bool stopAsked = MyInvocation.BoundParameters.TryGetValue("ErrorAction", out object? errorAction)
            && String.Equals(LanguagePrimitives.ConvertTo<string>(errorAction), "Stop", StringComparison.OrdinalIgnoreCase);
        if (!stopAsked && !StatementFault.CallerHasEnclosingTry(this))
            fault.CategoryInfo.Activity = DatabaseCommand;
        ReportFault(fault);
    }

    // Accepted differences kept by the keep-going section's point 3: -EnableException stops here with this record, where the pin writes it and goes on (held-ee,
    // instance-null-element-ee); -ErrorAction Stop has the effect PowerShell gives WriteError. $ErrorActionPreference set in the caller's scope acts on this WriteError as for any
    // compiled command, where the pin ignores it: harness-edits.md, "Script-scope preferences and the one-line connect warning", points 1 and 2.
    private void ReportFault(ErrorRecord fault)
    {
        if (EnableException.ToBool())
        {
            // caller-try: terminate -- -EnableException asks for the stop
            ThrowTerminatingError(fault); // style-ok: cs-raw-streams a statement fault of the pin, outside Stop-Function
        }

        // A plain call goes on; under a caller try the record stops the command, as the fault stops the pin's statement.
        StatementFault.Surface(this, fault);
    }

    // PS: Get-DbaDatabase -SqlInstance $instance -SqlCredential $SqlCredential -Database $Database -ExcludeSystem:(-not $IncludeSystemDatabases). -EnableException is not passed, so a
    // failed connection warns and the next instance is read (bad-ee).
    // Correction database-wildcards: the pinned help documents wildcards for -Database, which the exact -in of Get-DbaDatabase never honoured (wildcard-database). The shared
    // selection expands them, and a value that is a real database name on the instance stays literal.
    private List<SmoDatabase> ReadDatabases(DbaInstanceParameter instance)
    {
        List<SmoDatabase> selected = new();
        Server? connected = null;
        List<SmoDatabase> gathered;
        try
        {
            gathered = NativeDatabaseSelection.GatherMatching(this, new[] { instance }, SqlCredential, Database, true, null, false, server =>
            {
                connected = server;
                SetActiveConnection(server.ConnectionContext);
            }, () => false);
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            // PS: its catch around $server.Databases writes this line and falls back to the indexer; no fixture reaches it. Disclosed in the corrections record, raw-databases-untested.
            WriteAttributedMessage(DatabaseCommand, MessageLevel.Verbose, "Failure: " + EnumerationFault(failure).Exception.Message);
            return selected;
        }

        if (connected is null)
            return selected;

        // PS: the Where-Object filters of Get-DbaDatabase run over the rows of sys.databases, in their order (all-databases-dbo: master, tempdb, model, msdb). The helper keeps SMO's name order.
        bool azure = SmoServerExtensions.GetIsAzure(connected);
        DataTable? rows = ReadDatabaseRows(connected, azure);
        if (rows is null)
            return selected;

        // PS: $dbSizes = Invoke-QueryDatabaseSizes, once for the instance; on Azure the helper asks a database itself, and only one whose Size SMO reports as null or 0.
        DataTable? sizes = azure ? null : NativeDatabaseNotes.ReadInstanceSizes(this, connected);
        foreach (DataRow row in rows.Rows)
        {
            string name = NativeDatabaseNotes.RowName(row);
            foreach (SmoDatabase database in gathered)
            {
                if (String.Equals(database.Name, name, StringComparison.Ordinal) && IsListed(database, azure))
                {
                    // PS: the Add-Member calls of Get-DbaDatabase, which callers read through $schema.Parent.
                    NativeDatabaseNotes.AddDatabaseNotes(connected, database, row, sizes, azure);
                    selected.Add(database);
                }
            }
        }
        return selected;
    }

    // PS: $_.IsSystemObject -in $DBType, with the default ReadOnly and IsAccessible filters, which list both values and so pass every database whose value can be read; a getter that
    // fails reads as $null, which they drop. The pin's Azure branch reads none of them, so -ExcludeSystem keeps master there, by reading: the probe's Azure cases did not connect.
    private bool IsListed(SmoDatabase database, bool azure)
    {
        if (azure)
            return true;
        try
        {
            _ = database.ReadOnly;
            _ = database.IsAccessible;
            return IncludeSystemDatabases.ToBool() || !database.IsSystemObject;
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            return false;
        }
    }

    // PS: Invoke-QueryRawDatabases. Its Stop-Function has no -Continue and runs without -EnableException here, so it only warns, whatever this command's switch says, and the instance
    // then has no database. Every login may read sys.databases, so no native test reaches it; disclosed in the corrections record, raw-databases-untested.
    private DataTable? ReadDatabaseRows(Server server, bool azure)
    {
        try
        {
            return server.ConnectionContext.ExecuteWithResults(azure ? NativeDatabaseNotes.AzureDatabasesQuery : NativeDatabaseNotes.InstanceDatabasesQuery).Tables[0];
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            ErrorRecord record = new(failure, "dbatools_" + RawDatabasesCommand, ErrorCategory.NotSpecified, null);
            MessageService.Write(this, new MessageService.MessageRequest
            {
                FunctionName = RawDatabasesCommand, ModuleName = "dbatools", Level = MessageLevel.Warning,
                Message = "Failure | " + MessageService.GetErrorMessage(record), EnableException = false,
                File = MyInvocation.ScriptName, Line = MyInvocation.ScriptLineNumber
            });
            return null;
        }
    }

    private void WriteSchemas(SmoDatabase? database)
    {
        // PS: $null.Schemas enumerates nothing and every filter drops the $null that the pipeline carries (input-null-element).
        if (database is null)
            return;

        // Correction stale-schema-list: when reading the database faults, the pin's assignment does not happen, so its foreach walks the list of the database before it and writes
        // those schemas again under this database's name (offline-piped-good-first, held-good-first). Here the record is written and this database has no rows.
        if (!TryReadSchemas(database, out List<SmoSchema> schemas))
            return;

        Server server = database.Parent;
        foreach (SmoSchema schema in schemas.FindAll(IsSelected))
        {
            PSObject output = PSObject.AsPSObject(schema);
            // Add-Member -Force replaces notes left on the same SMO object by an earlier call.
            foreach (string note in Notes)
                output.Properties.Remove(note);
            OutputHelper.AddInstanceProperties(output, server);
            output.Properties.Add(new PSNoteProperty("DatabaseName", database.Name));
            output.Properties.Add(new PSNoteProperty("DatabaseId", database.ID));
            OutputHelper.SetDefaultDisplayPropertySet(output, DisplaySet);
            WriteObject(output);
        }
    }

    // PS: the three Where-Object filters. ($null -eq $Schema) is true only for a null -Schema, so an empty array or "" selects nothing (schema-empty-array, schema-empty-string), and
    // -in compares without regard to case, also in a case-sensitive database, and takes no patterns (case-sensitive-any-case, wildcard-schema).
    private bool IsSelected(SmoSchema schema)
    {
        if (schema.IsSystemObject && !IncludeSystemSchemas.ToBool())
            return false;
        if (Schema is not null && !NativeDatabaseSelection.ContainsInOperand(Schema, schema.Name))
            return false;
        if (SchemaOwner is null)
            return true;
        // A login that may not see a schema's owner reads it empty (low-user-no-permission).
        string? owner = schema.Owner;
        return owner is not null && NativeDatabaseSelection.ContainsInOperand(SchemaOwner, owner);
    }

    // The enumeration fault of the pin's statement: an offline database, one held in single-user mode by another session, one the login has no user in, measured. The record's id,
    // category, reason, message and inner chain are the pin's; the engine adds this cmdlet's id suffix and activity, which the pin has only under a caller's try.
    private bool TryReadSchemas(SmoDatabase database, out List<SmoSchema> schemas)
    {
        schemas = new List<SmoSchema>();
        ErrorRecord fault;
        try
        {
            foreach (SmoSchema schema in database.Schemas)
                schemas.Add(schema);
            return true;
        }
        catch (Exception exception) when (exception is not PipelineStoppedException)
        {
            fault = EnumerationFault(exception);
        }
        ReportFault(fault);
        return false;
    }

    private static ErrorRecord EnumerationFault(Exception exception)
    {
        string wrapped = String.Format(CultureInfo.InvariantCulture,
            "The following exception occurred while trying to enumerate the collection: \"{0}\".", exception.Message);
        return new ErrorRecord(new ExtendedTypeSystemException(wrapped, exception), "ExceptionInGetEnumerator", ErrorCategory.NotSpecified, null);
    }
}
