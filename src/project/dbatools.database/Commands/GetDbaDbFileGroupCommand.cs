#nullable enable

using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Management.Automation;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;
using SmoDatabase = Microsoft.SqlServer.Management.Smo.Database;
using SmoFileGroup = Microsoft.SqlServer.Management.Smo.FileGroup;

namespace Dataplat.Dbatools.Commands;

// Port of public/Get-DbaDbFileGroup.ps1 at refs/pins/dbatools-2026-10-22: the nested Get-DbaDatabase selection and the
// decorated $db.Filegroups with their default view.
/// <summary>Retrieves filegroup configuration and storage details from SQL Server databases</summary>
/// <para>
/// Retrieves detailed filegroup information from one or more databases, including filegroup type, size, and configuration details. This function helps DBAs analyze database storage organization, plan storage capacity, and document database structure for compliance or migration planning. Returns filegroup objects that can be filtered by database or specific filegroup names, making it useful for targeted storage analysis and troubleshooting performance issues related to data distribution.
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaDbFileGroup -SqlInstance sql2016
/// </code>
/// <para>
/// Return all FileGroups for all databases on instance sql2016
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaDbFileGroup -SqlInstance sql2016 -Database MyDB
/// </code>
/// <para>
/// Return all FileGroups for database MyDB on instance sql2016
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaDbFileGroup -SqlInstance sql2016 -FileGroup Primary
/// </code>
/// <para>
/// Returns information on filegroup called Primary if it exists in any database on the server sql2016
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; 'localhost','localhost\namedinstance' | Get-DbaDbFileGroup
/// </code>
/// <para>
/// Returns information on all FileGroups for all databases on instances 'localhost','localhost\namedinstance'
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; 'localhost','localhost\namedinstance' | Get-DbaDbFileGroup
/// </code>
/// <para>
/// Returns information on all FileGroups for all databases on instances 'localhost','localhost\namedinstance'
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaDatabase -SqlInstance SQL1\SQLExpress,SQL2 -ExcludeDatabase model,master | Get-DbaDbFileGroup
/// </code>
/// <para>
/// Returns information on all FileGroups for all databases except model and master on instances SQL1\SQLExpress,SQL2
/// </para>
/// </example>
/// <list type="alertSet">
/// <item>
/// <term />
/// <description>
/// <para>
/// Tags: Storage, File, Data
/// Author: Patrick Flynn (@sqllensman)
/// </para>
/// <para>
/// Website: https://dbatools.io
/// Copyright: (c) 2018 by dbatools, licensed under MIT
/// License: MIT https://opensource.org/licenses/MIT
/// </para>
/// </description>
/// </item>
/// </list>
/// <seealso href="https://dbatools.io/Get-DbaDbFileGroup" />
[Cmdlet(VerbsCommon.Get, "DbaDbFileGroup")]
[OutputType(typeof(SmoFileGroup))]
public sealed class GetDbaDbFileGroupCommand : DbaBaseCmdlet
{
    // PS: Select-DefaultView -Property ComputerName, InstanceName, SqlInstance, Parent, FileGroupType, Name, Size
    private static readonly string[] DisplaySet =
    {
        "ComputerName", "InstanceName", "SqlInstance", "Parent", "FileGroupType", "Name", "Size"
    };

    private static readonly string[] InstanceProperties = { "ComputerName", "InstanceName", "SqlInstance" };

    private bool _namedInstance;
    private bool _namedInput;
    private Server? _matcherServer;
    private WildcardNameMatcher? _databaseMatcher;

    /// <para>
    /// The target SQL Server instance or instances. This can be a collection and receive pipeline input.
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
    /// Specifies which databases to analyze for filegroup information. Accepts wildcards and multiple database names.
    /// Use this when you need to focus on specific databases instead of scanning all databases on the instance, which is helpful for large environments or targeted storage analysis.
    /// </para>
    [Parameter(Position = 2)]
    public object[]? Database { get; set; }

    /// <para>
    /// Accepts database objects from Get-DbaDatabase pipeline input for processing filegroups.
    /// Use this when you want to chain database filtering with filegroup analysis, such as excluding system databases or filtering by database properties before examining storage structure.
    /// </para>
    [Parameter(ValueFromPipeline = true, Position = 3)]
    public SmoDatabase[]? InputObject { get; set; }

    /// <para>
    /// Filters results to specific filegroups by name, such as 'PRIMARY' or custom filegroups.
    /// Use this when troubleshooting storage issues with particular filegroups or when you need to verify configuration of specific data placement strategies.
    /// </para>
    [Parameter(Position = 4)]
    [PsStringArrayCast]
    public string[]? FileGroup { get; set; }

    /// <summary>Notes what the command line bound, which is all that is bound before the first record.</summary>
    protected override void BeginProcessing()
    {
        _namedInstance = TestBound(nameof(SqlInstance));
        _namedInput = TestBound(nameof(InputObject));
    }

    /// <summary>Reads the filegroups of the record's databases.</summary>
    protected override void ProcessRecord()
    {
        if (Interrupted)
            return;
        bool hasInstance = TestBound(nameof(SqlInstance));
        bool hasInput = TestBound(nameof(InputObject));
        if (!hasInstance && !hasInput)
        {
            WriteMessage(MessageLevel.Warning, "You must specify either a SQL instance or supply an InputObject");
            return;
        }

        // BoundParameters keeps a parameter an earlier piped record bound after its value is reset, so the record decides:
        // an instance it pipes is read even after a piped database or null record. Otherwise a bound -InputObject stands.
        bool pipedInstance = !_namedInstance && SqlInstance is not null;
        bool readInput = InputObject is not null || _namedInput || (hasInput && !pipedInstance);
        IEnumerable<SmoDatabase?> databases = InputObject ?? Array.Empty<SmoDatabase>();
        if (!readInput)
        {
            // Get-DbaDatabase declares -SqlInstance mandatory, so its binding refuses what this parameter accepted. The
            // binder checks each element too: one null refuses the whole array before any instance is read. The pin then
            // resumes at its foreach over an $InputObject that holds nothing of this record.
            if (SqlInstance is null || Array.Exists(SqlInstance, instance => instance is null))
            {
                ReportBindingFault("ParameterArgumentValidationErrorNullNotAllowed", "null");
                return;
            }
            if (SqlInstance.Length == 0)
            {
                ReportBindingFault("ParameterArgumentValidationErrorEmptyArrayNotAllowed", "an empty array");
                return;
            }

            // PS: Get-DbaDatabase -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database
            databases = ReadDatabases();
        }

        foreach (SmoDatabase? database in databases)
        {
            if (Interrupted)
                return;
            // The name filter runs before the accessibility test, so a database narrowed away is not reported as skipped.
            if (TestBound(nameof(Database)) && !DatabaseSelected(database))
                continue;
            WriteFileGroups(database);
        }
    }

    // PS: $Database -notcontains $db.Name, plus the wildcards -Database documents; a real name of the instance stays literal.
    private bool DatabaseSelected(SmoDatabase? database)
    {
        if (database is null)
            return NativeDatabaseSelection.ContainsInOperand(Database, null!);
        Server server = database.Parent;
        if (!ReferenceEquals(server, _matcherServer))
        {
            _matcherServer = server;
            _databaseMatcher = NativeDatabaseSelection.CreateInOperandMatcher(Database, true,
                NativeDatabaseSelection.DatabaseNames(server));
        }
        return _databaseMatcher!.Matches(database.Name);
    }

    // Binder section, points 1 and 2, with the StatementFault section's point 5.
    private void ReportBindingFault(string errorId, string problem)
    {
        ErrorRecord fault = new ErrorRecord(
            new ParameterBindingException(String.Format("Cannot bind argument to parameter 'SqlInstance' because it is {0}.", problem)),
            errorId, ErrorCategory.InvalidData, null);
        // The binder's own exception type is internal, so the record carries its public base and the Reason callers read.
        fault.CategoryInfo.Reason = "ParameterBindingValidationException";
        // The pin's activity follows its id suffix: the nested command when the caller has no try and the call has no -ErrorAction Stop.
        // Under a caller's try or that switch the fault leaves through this command, and the engine's default activity is already the pin's.
        bool stopAsked = MyInvocation.BoundParameters.TryGetValue("ErrorAction", out object? errorAction)
            && String.Equals(LanguagePrimitives.ConvertTo<string>(errorAction), "Stop", StringComparison.OrdinalIgnoreCase);
        if (!stopAsked && !StatementFault.CallerHasEnclosingTry(this))
            fault.CategoryInfo.Activity = "Get-DbaDatabase";

        // Differences from the pin kept by the binder section's point 2 and the keep-going section's point 3: -EnableException stops here with this
        // record, where the pin writes it and goes on; -ErrorAction Stop has the effect PowerShell gives WriteError. $ErrorActionPreference set in the
        // caller's scope acts on this WriteError as for any compiled command, where the pin ignores it: harness-edits.md, "Script-scope preferences and
        // the one-line connect warning", points 1 and 2.
        if (EnableException.ToBool())
        {
            // caller-try: terminate -- -EnableException asks for the stop
            ThrowTerminatingError(fault); // style-ok: cs-raw-streams binder fault of the nested Get-DbaDatabase, outside Stop-Function, as in the pin
        }

        // A plain call goes on to the next record; under a caller try the record stops the command, as the binder fault stops the pin's statement.
        StatementFault.Surface(this, fault);
    }

    private List<SmoDatabase> ReadDatabases()
    {
        string[]? names = Database is null ? null :
            (string[])LanguagePrimitives.ConvertTo(Database, typeof(string[]), CultureInfo.InvariantCulture);
        return NativeDatabaseSelection.GatherMatching(this, SqlInstance, SqlCredential, names, true, null, false,
            server => SetActiveConnection(server.ConnectionContext), () => Interrupted);
    }

    private void WriteFileGroups(SmoDatabase? database)
    {
        if (database is null || !database.IsAccessible)
        {
            // sys.filegroups is database scoped, so there is nothing to read from master for a database that cannot be opened.
            WriteMessage(MessageLevel.Warning,
                String.Format("Skipping database {0} on {1} because it is not accessible, so its filegroups cannot be read", database, database?.Parent), database);
            return;
        }

        WriteMessage(MessageLevel.Verbose, String.Format("Processing database: {0}", database));
        Server server = database.Parent;
        List<SmoFileGroup> fileGroups = database.FileGroups.Cast<SmoFileGroup>().ToList();
        if (TestBound(nameof(FileGroup)))
            fileGroups = fileGroups.FindAll(fileGroup => NativeDatabaseSelection.ContainsInOperand(FileGroup, fileGroup.Name));

        foreach (SmoFileGroup fileGroup in fileGroups)
        {
            if (Interrupted)
                return;
            WriteMessage(MessageLevel.Verbose, String.Format("Processing filegroup {0}", fileGroup.Name));
            PSObject output = PSObject.AsPSObject(fileGroup);
            foreach (string property in InstanceProperties)
                output.Properties.Remove(property);
            OutputHelper.AddInstanceProperties(output, server);
            OutputHelper.SetDefaultDisplayPropertySet(output, DisplaySet);
            WriteObject(output);
        }
    }
}
