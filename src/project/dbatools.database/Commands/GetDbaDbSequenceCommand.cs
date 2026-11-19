#nullable enable

using System;
using System.Collections.Generic;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;
using SmoDatabase = Microsoft.SqlServer.Management.Smo.Database;
using SmoSequence = Microsoft.SqlServer.Management.Smo.Sequence;

namespace Dataplat.Dbatools.Commands;

// Port of public/Get-DbaDbSequence.ps1 at refs/pins/dbatools-2026-10-22: the nested Get-DbaDatabase selection and the decorated
// $db.Sequences with their default view. Measured on the pin: evidence/pin-sequence-20261103.txt.
/// <summary>Retrieves SQL Server sequence objects and their configuration details from specified databases.</summary>
/// <para>
/// Retrieves sequence objects from SQL Server databases, returning detailed information about each sequence including data type, start value, increment value, and schema location. Sequences provide a flexible alternative to IDENTITY columns for generating sequential numeric values, allowing values to be shared across multiple tables and offering more control over numbering behavior. This function helps DBAs inventory sequences across databases, verify sequence configurations, and identify sequences that may need maintenance or optimization.
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaDbSequence -SqlInstance sqldev01 -Database TestDB -Sequence TestSequence
/// </code>
/// <para>
/// Finds the sequence TestSequence in the TestDB database on the sqldev01 instance.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaDatabase -SqlInstance sqldev01 -Database TestDB | Get-DbaDbSequence -Sequence TestSequence -Schema TestSchema
/// </code>
/// <para>
/// Using a pipeline this command finds the sequence named TestSchema.TestSequence in the TestDB database on the sqldev01 instance.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaDbSequence -SqlInstance localhost
/// </code>
/// <para>
/// Finds all the sequences on the localhost instance.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaDbSequence -SqlInstance localhost -Database db
/// </code>
/// <para>
/// Finds all the sequences in the db database on the localhost instance.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaDbSequence -SqlInstance localhost -Sequence seq
/// </code>
/// <para>
/// Finds all the sequences named seq on the localhost instance.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaDbSequence -SqlInstance localhost -Schema sch
/// </code>
/// <para>
/// Finds all the sequences in the sch schema on the localhost instance.
/// </para>
/// </example>
/// <list type="alertSet">
/// <item>
/// <term />
/// <description>
/// <para>
/// Tags: Data, Sequence, Table
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
/// <seealso href="https://dbatools.io/Get-DbaDbSequence" />
[Cmdlet(VerbsCommon.Get, "DbaDbSequence")]
[OutputType(typeof(SmoSequence))]
public sealed class GetDbaDbSequenceCommand : DbaBaseCmdlet
{
    // PS: Select-DefaultView -Property ComputerName, InstanceName, SqlInstance, Database, Schema, Name, DataType, StartValue, IncrementValue
    private static readonly string[] DisplaySet =
    {
        "ComputerName", "InstanceName", "SqlInstance", "Database", "Schema", "Name", "DataType", "StartValue", "IncrementValue"
    };

    private static readonly string[] Notes = { "ComputerName", "InstanceName", "SqlInstance", "Database" };

    private bool _namedInstance;
    private bool _namedRead;

    /// <para>
    /// The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function
    /// to be executed against multiple SQL Server instances.
    /// </para>
    [Parameter(ValueFromPipeline = true, Position = 0)]
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
    /// Specifies which databases to search for sequence objects. Accepts wildcards and multiple database names.
    /// Use this when you need to limit the search to specific databases instead of scanning all databases on the instance.
    /// </para>
    [Parameter(Position = 2)]
    [PsStringArrayCast]
    public string[]? Database { get; set; }

    /// <para>
    /// Filters results to sequences with specific names. Accepts multiple sequence names and supports exact name matching.
    /// Use this when you need to find specific sequences across databases rather than retrieving all sequences.
    /// </para>
    [Parameter(Position = 3)]
    [Alias("Name")]
    [PsStringArrayCast]
    public string[]? Sequence { get; set; }

    /// <para>
    /// Filters results to sequences within specific schemas. Accepts multiple schema names for searching across different schemas.
    /// Use this when you need to examine sequences in particular schemas, such as application-specific schemas or custom organizational structures.
    /// </para>
    [Parameter(Position = 4)]
    [PsStringArrayCast]
    public string[]? Schema { get; set; }

    /// <para>
    /// Accepts database objects from Get-DbaDatabase pipeline input, allowing you to target specific databases already retrieved.
    /// Use this approach when you need to chain commands or work with databases that meet specific criteria from previous filtering operations.
    /// </para>
    [Parameter(ValueFromPipeline = true, Position = 5)]
    public SmoDatabase[]? InputObject { get; set; }

    /// <summary>Notes whether -SqlInstance was named on the command line, which a piped instance is not.</summary>
    protected override void BeginProcessing()
    {
        base.BeginProcessing();
        _namedInstance = TestBound(nameof(SqlInstance));
    }

    /// <summary>Reads the sequences of the record's databases.</summary>
    protected override void ProcessRecord()
    {
        // The pin has no Test-FunctionInterrupt: a record that stops here leaves the next record to run.
        bool hasInstance = LanguagePrimitives.IsTrue(SqlInstance);
        if (!LanguagePrimitives.IsTrue(InputObject) && !hasInstance)
        {
            StopFunction("You must pipe in a database or specify a SqlInstance");
            return;
        }

        // Corrections piped-instance-repeat and named-instance-repeat: the pin's $InputObject += keeps what earlier records added, so its rows repeat.
        // Here a record reads its own input, and a named -SqlInstance is read once.
        List<SmoDatabase?> databases = InputObject is null ? new List<SmoDatabase?>() : new List<SmoDatabase?>(InputObject);
        if (hasInstance)
        {
            // Get-DbaDatabase declares -SqlInstance mandatory, so its binder refuses a null element before any instance is read; the pin then
            // resumes at its foreach. A null or empty -SqlInstance is falsy and has already stopped above.
            if (Array.Exists(SqlInstance!, instance => instance is null))
            {
                ReportBindingFault();
            }
            else if (!_namedRead)
            {
                databases.AddRange(ReadDatabases());
                _namedRead = _namedInstance;
            }
        }

        foreach (SmoDatabase? database in databases)
            WriteSequences(database);
    }

    // Binder section, points 1 and 2, with the StatementFault section's point 5. The pin's activity follows its id suffix: the nested command when the
    // caller has no try and the call has no -ErrorAction Stop. Under either, the fault leaves through this command, and the engine's default is the pin's.
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
            fault.CategoryInfo.Activity = "Get-DbaDatabase";
        ReportFault(fault);
    }

    // Accepted differences kept by the keep-going section's point 3: -EnableException stops here with this record, where the pin writes it and goes on;
    // -ErrorAction Stop has the effect PowerShell gives WriteError. $ErrorActionPreference set in the caller's scope acts on this WriteError as for any
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

    private List<SmoDatabase> ReadDatabases()
    {
        // PS: Get-DbaDatabase -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database -ExcludeDatabase $ExcludeDatabase. The pin has no
        // -ExcludeDatabase parameter, so that variable is null. -EnableException is not passed, so a failed connection warns and the next instance is read.
        // Correction database-wildcards: -Database takes the wildcards its help documents.
        return NativeDatabaseSelection.GatherMatching(this, SqlInstance, SqlCredential, Database, true, null, false,
            server => SetActiveConnection(server.ConnectionContext), () => false);
    }

    private void WriteSequences(SmoDatabase? database)
    {
        // PS: $null -eq $false is false, so a null element passes the accessibility test and has no sequences to read.
        if (database is null)
        {
            WriteMessage(MessageLevel.Verbose, "Getting Database Sequences for  on ");
            return;
        }
        if (!database.IsAccessible)
            return;

        Server server = database.Parent;
        WriteMessage(MessageLevel.Verbose, String.Format("Getting Database Sequences for {0} on {1}", database, server));

        // PS: $dbSequences = $db.Sequences does not enumerate; each filter and the foreach do. A filter whose enumeration faults leaves $dbSequences as
        // the collection, so the next statement enumerates it again: measured, one record per attempt (held-plain 1, held-sequence 2, held-both 3).
        List<SmoSequence>? rows = null;
        if (LanguagePrimitives.IsTrue(Sequence) && TryReadSequences(database, out List<SmoSequence> named))
            rows = named.FindAll(sequence => NativeDatabaseSelection.ContainsInOperand(Sequence, sequence.Name));
        if (LanguagePrimitives.IsTrue(Schema))
        {
            List<SmoSequence>? source = rows;
            if (source is not null || TryReadSequences(database, out source))
                rows = source!.FindAll(sequence => NativeDatabaseSelection.ContainsInOperand(Schema, sequence.Schema));
        }
        if (rows is null && !TryReadSequences(database, out rows))
            return;

        foreach (SmoSequence sequence in rows!)
        {
            PSObject output = PSObject.AsPSObject(sequence);
            // Add-Member -Force replaces notes left on the same SMO object by an earlier call.
            foreach (string note in Notes)
                output.Properties.Remove(note);
            OutputHelper.AddInstanceProperties(output, server);
            output.Properties.Add(new PSNoteProperty("Database", database.Name));
            OutputHelper.SetDefaultDisplayPropertySet(output, DisplaySet);
            WriteObject(output);
        }
    }

    // The enumeration fault of the pin's statements: a database held in single-user mode by another session, measured. The record's id, category, reason,
    // message and inner chain are the pin's; the engine adds this cmdlet's id suffix and activity, which the pin has only under a caller's try.
    private bool TryReadSequences(SmoDatabase database, out List<SmoSequence> sequences)
    {
        sequences = new List<SmoSequence>();
        ErrorRecord fault;
        try
        {
            foreach (SmoSequence sequence in database.Sequences)
                sequences.Add(sequence);
            return true;
        }
        catch (Exception exception) when (exception is not PipelineStoppedException)
        {
            string wrapped = String.Format(CultureInfo.InvariantCulture,
                "The following exception occurred while trying to enumerate the collection: \"{0}\".", exception.Message);
            fault = new ErrorRecord(new ExtendedTypeSystemException(wrapped, exception), "ExceptionInGetEnumerator", ErrorCategory.NotSpecified, null);
        }
        ReportFault(fault);
        return false;
    }
}
