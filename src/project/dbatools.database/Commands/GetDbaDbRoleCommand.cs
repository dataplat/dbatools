#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;
using SmoDatabase = Microsoft.SqlServer.Management.Smo.Database;

namespace Dataplat.Dbatools.Commands;

// Port of public/Get-DbaDbRole.ps1 at refs/pins/dbatools-2026-10-22: the nested Get-DbaDatabase selection and each database's decorated
// roles with their default view.
/// <summary>Retrieves database roles from SQL Server instances for security auditing and permission analysis.</summary>
/// <para>Retrieves all database roles (both fixed and custom) from one or more SQL Server databases, returning detailed role information for security audits and compliance reporting. This function examines the roles collection in each accessible database, allowing you to identify custom roles, exclude built-in fixed roles, or focus on specific roles by name. Essential for documenting role structures across environments, troubleshooting permission issues, and ensuring consistent security configurations during migrations or standardization projects.</para>
/// <list type="alertSet">
///   <item>
///     <term></term>
///     <description>
///       <para>Tags: Role, User</para>
///       <para>Author: Ben Miller (@DBAduck)</para>
///       <para>Website: https://dbatools.io</para>
///       <para>Copyright: (c) 2018 by dbatools, licensed under MIT</para>
///       <para>License: MIT https://opensource.org/licenses/MIT</para>
///     </description>
///   </item>
/// </list>
/// <example>
///   <prefix>PS C:\&gt;</prefix>
///   <code>Get-DbaDbRole -SqlInstance localhost</code>
///   <para>Returns all database roles in all databases on the local default SQL Server instance</para>
/// </example>
/// <example>
///   <prefix>PS C:\&gt;</prefix>
///   <code>Get-DbaDbRole -SqlInstance localhost, sql2016</code>
///   <para>Returns all roles of all database(s) on the local and sql2016 SQL Server instances</para>
/// </example>
/// <example>
///   <prefix>PS C:\&gt;</prefix>
///   <code>$servers = Get-Content C:\servers.txt
/// PS C:\&gt; $servers | Get-DbaDbRole</code>
///   <para>Returns roles of all database(s) for every server in C:\servers.txt</para>
/// </example>
/// <example>
///   <prefix>PS C:\&gt;</prefix>
///   <code>Get-DbaDbRole -SqlInstance localhost -Database msdb</code>
///   <para>Returns roles of the database msdb on localhost.</para>
/// </example>
/// <example>
///   <prefix>PS C:\&gt;</prefix>
///   <code>Get-DbaDbRole -SqlInstance localhost -Database msdb -ExcludeFixedRole</code>
///   <para>Returns all non-fixed roles in the msdb database on localhost.</para>
/// </example>
/// <example>
///   <prefix>PS C:\&gt;</prefix>
///   <code>Get-DbaDbRole -SqlInstance localhost -Database msdb -Role 'db_owner'</code>
///   <para>Returns the db_owner role in the msdb database on localhost.</para>
/// </example>
/// <seealso href="https://dbatools.io/Get-DbaDbRole"/>
[Cmdlet(VerbsCommon.Get, "DbaDbRole")]
[OutputType(typeof(DatabaseRole))]
public sealed class GetDbaDbRoleCommand : DbaBaseCmdlet
{
    // PS: Select-DefaultView -Property "ComputerName", "InstanceName", "Database", "Name", "IsFixedRole"
    private static readonly string[] DisplaySet = { "ComputerName", "InstanceName", "Database", "Name", "IsFixedRole" };

    private static readonly string[] NoteProperties = { "ComputerName", "InstanceName", "SqlInstance", "Database" };

    private bool _namedInstance;
    private bool _namedInstanceRead;

    /// <summary>
    /// <para>The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.</para>
    /// </summary>
    [Parameter(ValueFromPipeline = true, Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>
    /// <para>Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).</para>
    /// <para>Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.</para>
    /// <para>For MFA support, please use Connect-DbaInstance.</para>
    /// </summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>
    /// <para>Specifies which databases to examine for role information. Accepts wildcards for pattern matching.
    /// Use this when you need to audit roles in specific databases rather than scanning all databases on the instance.
    /// Particularly useful for focusing on user databases while skipping system databases, or for compliance audits of specific applications.</para>
    /// </summary>
    [Parameter(Position = 2)]
    [PsStringArrayCast]
    public string[]? Database { get; set; }

    /// <summary>
    /// <para>Excludes specified databases from role enumeration. Accepts wildcards for pattern matching.
    /// Use this to skip databases you don't need to audit, such as development databases during production security reviews.
    /// Commonly used to exclude system databases or databases with known standard configurations.</para>
    /// </summary>
    [Parameter(Position = 3)]
    [PsStringArrayCast]
    public string[]? ExcludeDatabase { get; set; }

    /// <summary>
    /// <para>Specifies which database roles to retrieve by name. Accepts wildcards for pattern matching.
    /// Use this when investigating specific roles across databases, such as checking for custom application roles or finding all instances of a particular role name.
    /// Particularly useful for security audits focusing on elevated permissions like 'db_owner' or custom admin roles.</para>
    /// </summary>
    [Parameter(Position = 4)]
    [PsStringArrayCast]
    public string[]? Role { get; set; }

    /// <summary>
    /// <para>Excludes specified roles from the results by name. Accepts wildcards for pattern matching.
    /// Use this to filter out roles you're not interested in, such as excluding standard fixed roles when focusing on custom application roles.
    /// Helpful for reducing noise in reports when you want to see only non-standard or suspicious role configurations.</para>
    /// </summary>
    [Parameter(Position = 5)]
    [PsStringArrayCast]
    public string[]? ExcludeRole { get; set; }

    /// <summary>
    /// <para>Excludes all built-in fixed database roles from the results, showing only custom user-defined roles.
    /// Use this when auditing custom role implementations or when you need to focus on application-specific security configurations.
    /// Fixed roles like db_owner, db_datareader, and db_datawriter are filtered out, along with the public role.</para>
    /// </summary>
    [Parameter]
    public SwitchParameter ExcludeFixedRole { get; set; }

    /// <summary>
    /// <para>Accepts database objects from Get-DbaDatabase through the pipeline for role enumeration.
    /// Use this when you need to chain database selection criteria with role analysis, such as filtering databases by size, compatibility level, or other properties first.
    /// Allows for more complex filtering scenarios than the basic Database parameter provides.</para>
    /// </summary>
    [Parameter(ValueFromPipeline = true, Position = 6)]
    public SmoDatabase[]? InputObject { get; set; }

    /// <summary>
    /// <para>By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
    /// This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
    /// Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.</para>
    /// </summary>
    [Parameter]
    public override SwitchParameter EnableException { get; set; }

    /// <summary>Notes what the command line bound, which is all that is bound before the first record.</summary>
    protected override void BeginProcessing()
    {
        _namedInstance = TestBound(nameof(SqlInstance));
    }

    /// <summary>Reads the roles of the record's databases.</summary>
    protected override void ProcessRecord()
    {
        // PS: -not $InputObject -and -not $SqlInstance. A bound null, an empty array and an array of one null all count as none.
        bool hasInstance = LanguagePrimitives.IsTrue(SqlInstance);
        if (!LanguagePrimitives.IsTrue(InputObject) && !hasInstance)
        {
            StopFunction("You must pipe in a database or specify a SqlInstance");
            return;
        }

        List<SmoDatabase?> databases = new(InputObject ?? Array.Empty<SmoDatabase>());

        // Correction sqlinstance-read-once: the source appends the instance's databases on every piped record, repeating them once per
        // record, so a named -SqlInstance is read once. Correction piped-instance-repeat: the source's $InputObject keeps what an earlier
        // record appended, so only the record's own instance is read here.
        if (hasInstance && !_namedInstanceRead)
        {
            _namedInstanceRead = _namedInstance;
            databases.AddRange(ReadDatabases());
        }

        foreach (SmoDatabase? database in databases)
            WriteRoles(database);
    }

    // PS: Get-DbaDatabase -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database -ExcludeDatabase $ExcludeDatabase -EnableException:$EnableException
    private List<SmoDatabase> ReadDatabases()
    {
        List<SmoDatabase> gathered = new();

        // Get-DbaDatabase declares -SqlInstance mandatory, so its binding refuses an array holding a null before any instance is read.
        if (Array.Exists(SqlInstance!, instance => instance is null))
        {
            SurfaceStatementFault(BindingFault());
            return gathered;
        }

        foreach (DbaInstanceParameter instance in SqlInstance!)
        {
            try
            {
                // Correction database-wildcards: the pinned help documents wildcards for both filters, which the exact-match Get-DbaDatabase
                // never honoured. Each instance's own names decide which pattern values are real names and stay literal.
                gathered.AddRange(NativeDatabaseSelection.GatherMatching(this, new[] { instance }, SqlCredential,
                    Database, true, ExcludeDatabase, true, server => SetActiveConnection(server.ConnectionContext), () => false, ConnectionFailed));
            }
            catch (Exception failure) when (failure is not PipelineStoppedException)
            {
                // PS: Invoke-QueryRawDatabases. Its Stop-Function has no -Continue, and the empty result then ends the instance.
                StopAttributedFunction("Get-DbaDatabase", "Failure", errorRecord: new ErrorRecord(failure, "dbatools_Get-DbaDatabase", ErrorCategory.NotSpecified, null), continueLoop: true);
            }
        }
        return gathered;
    }

    // PS: Get-DbaDatabase's Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue, which this command
    // gives -EnableException:$EnableException.
    private void ConnectionFailed(DbaInstanceParameter instance, Exception failure)
    {
        StopAttributedFunction("Get-DbaDatabase", "Failure", target: instance,
            errorRecord: new ErrorRecord(failure, "dbatools_Get-DbaDatabase", ErrorCategory.ConnectionError, instance),
            category: ErrorCategory.ConnectionError, continueLoop: true);
    }

    private void WriteRoles(SmoDatabase? database)
    {
        // PS: if ($db.IsAccessible -eq $false) { continue }. A null element, or a read that gives no answer, is not false.
        if (database is not null && IsInaccessible(database))
            return;

        Server? server = database?.Parent;
        WriteMessage(MessageLevel.Verbose, String.Format("Getting Database Roles for {0} on {1}", database, server));
        if (database is null)
            return;

        List<DatabaseRole>? roles = ReadRoles(database);
        if (roles is null)
            return;

        foreach (DatabaseRole role in SelectRoles(roles))
        {
            // PS: Add-Member -Force for the four properties, then Select-DefaultView.
            PSObject output = PSObject.AsPSObject(role);
            foreach (string property in NoteProperties)
                output.Properties.Remove(property);
            OutputHelper.AddInstanceProperties(output, server!);
            output.Properties.Add(new PSNoteProperty("Database", database.Name));
            OutputHelper.SetDefaultDisplayPropertySet(output, DisplaySet);
            WriteObject(output);
        }
    }

    private static bool IsInaccessible(SmoDatabase database)
    {
        try
        {
            return !database.IsAccessible;
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            // As the pin measured on a database dropped before its properties were read (evidence/pin-role2-20261102.txt, unread-*): the command
            // reports nothing here and goes on to read the roles.
            return false;
        }
    }

    // PS: the filters and foreach enumerate $db.Roles, and SMO loads the collection when it is enumerated, so a read that faults does so here. Each
    // active filter and the foreach meet the same fault, each writing the engine's record (evidence/pin-role2-20261102.txt, single-user-object*).
    private List<DatabaseRole>? ReadRoles(SmoDatabase database)
    {
        List<DatabaseRole> roles = new();
        IEnumerator? enumerator = null;
        try
        {
            enumerator = LanguagePrimitives.GetEnumerator(database.Roles);
            while (enumerator.MoveNext())
                roles.Add((DatabaseRole)enumerator.Current);
            return roles;
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            int faults = 1;
            if (LanguagePrimitives.IsTrue(Role))
                faults++;
            if (LanguagePrimitives.IsTrue(ExcludeRole))
                faults++;
            if (ExcludeFixedRole.ToBool())
                faults++;
            // Each enumeration in the pin raises its own fault, so each write is a record of its own, never the same record again
            // ("Engine error records in native ports (operator, 2026-11-12)", point 2).
            for (int written = 0; written < faults; written++)
                SurfaceStatementFault(EnumerationFault(failure, enumerator));
            return null;
        }
    }

    // The engine's record when the failure carries one (ExceptionInGetEnumerator); otherwise the record a failing MoveNext gives.
    private static ErrorRecord EnumerationFault(Exception failure, IEnumerator? enumerator)
    {
        if (failure is IContainsErrorRecord container && container.ErrorRecord is not null)
            return new ErrorRecord(container.ErrorRecord, failure);
        RuntimeException fault = new(String.Format(CultureInfo.InvariantCulture,
            "An error occurred while enumerating through a collection: {0}.", failure.Message), failure);
        return new ErrorRecord(fault, "BadEnumeration", ErrorCategory.InvalidOperation, enumerator);
    }

    private List<DatabaseRole> SelectRoles(List<DatabaseRole> roles)
    {
        List<string> names = roles.ConvertAll(role => role.Name);

        // Correction role-wildcards: the pinned help documents wildcards for both filters, which -in and -notin never honoured. Each database's
        // own role names decide which pattern values are real names and stay literal.
        if (LanguagePrimitives.IsTrue(Role))
        {
            WildcardNameMatcher included = NativeDatabaseSelection.CreateNameMatcher(Role, true, names);
            roles = roles.FindAll(role => included.Matches(role.Name));
        }
        if (LanguagePrimitives.IsTrue(ExcludeRole))
        {
            WildcardNameMatcher excluded = NativeDatabaseSelection.CreateNameMatcher(ExcludeRole, true, names);
            roles = roles.FindAll(role => !excluded.Matches(role.Name));
        }

        // Correction public-role-case: the source's -ne ignored case, which hid a custom role named PUBLIC in a case-sensitive database.
        if (ExcludeFixedRole.ToBool())
            roles = roles.FindAll(role => !role.IsFixedRole && !String.Equals(role.Name, "public", StringComparison.Ordinal));
        return roles;
    }

    // PS: the nested Get-DbaDatabase's binding of -SqlInstance. The binder's own exception type is internal, so the record carries its public base and
    // the Reason and activity callers read.
    private ErrorRecord BindingFault()
    {
        ErrorRecord record = new(new ParameterBindingException("Cannot bind argument to parameter 'SqlInstance' because it is null."),
            "ParameterArgumentValidationErrorNullNotAllowed", ErrorCategory.InvalidData, null);
        record.CategoryInfo.Reason = "ParameterBindingValidationException";
        // The pin's activity follows its id suffix (evidence/pin-role-20261102.txt, instance-null-element-*): the nested Get-DbaDatabase when the caller
        // has no try and the call has no -ErrorAction Stop. Under a caller's try or that switch the fault leaves through this command, and the engine's
        // default activity, this cmdlet's name, is already the pin's.
        bool stopAsked = MyInvocation.BoundParameters.TryGetValue("ErrorAction", out object? errorAction)
            && String.Equals(LanguagePrimitives.ConvertTo<string>(errorAction), "Stop", StringComparison.OrdinalIgnoreCase);
        if (!stopAsked && !StatementFault.CallerHasEnclosingTry(this))
            record.CategoryInfo.Activity = "Get-DbaDatabase";
        return record;
    }

    // A plain call writes the record and goes on to the source's next statement, a caller's try or trap catches it there, and -EnableException stops.
    private void SurfaceStatementFault(ErrorRecord record)
    {
        // caller-try: terminate -- -EnableException stops at a statement fault the source goes on from (keep-going rule, point 3)
        if (EnableException.ToBool())
            ThrowTerminatingError(record); // style-ok: cs-raw-streams pinned statement fault outside Stop-Function
        StatementFault.Surface(this, record);
    }
}
