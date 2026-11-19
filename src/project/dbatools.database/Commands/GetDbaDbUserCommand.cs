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
using SmoUser = Microsoft.SqlServer.Management.Smo.User;

namespace Dataplat.Dbatools.Commands;

// Port of public/Get-DbaDbUser.ps1 at refs/pins/dbatools-2026-10-22: the users of each database Get-DbaDatabase -OnlyAccessible selects, on the connection of each instance.
// Expected values as the pin measured on both editions: evidence/pin-user-20261103.txt and evidence/pin-user2-20261103.txt, whose case names the comments below use.
/// <summary>Retrieves database user accounts and their associated login mappings from SQL Server databases</summary>
/// <para>
/// Retrieves all database user accounts from one or more databases, showing their associated server logins, authentication types, and access states. This function is essential for security audits, user access reviews, and compliance reporting where you need to see who has database-level access and how their accounts are configured. You can filter results by specific users, logins, databases, or exclude system accounts to focus on custom user accounts that require regular review.
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaDbUser -SqlInstance sql2016
/// </code>
/// <para>
/// Gets all database users
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaDbUser -SqlInstance Server1 -Database db1
/// </code>
/// <para>
/// Gets the users for the db1 database
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaDbUser -SqlInstance Server1 -ExcludeDatabase db1
/// </code>
/// <para>
/// Gets the users for all databases except db1
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaDbUser -SqlInstance Server1 -ExcludeSystemUser
/// </code>
/// <para>
/// Gets the users for all databases that are not system objects, like 'dbo', 'guest' or 'INFORMATION_SCHEMA'
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; 'Sql1','Sql2/sqlexpress' | Get-DbaDbUser
/// </code>
/// <para>
/// Gets the users for the databases on Sql1 and Sql2/sqlexpress
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaDbUser -SqlInstance Server1 -Database db1 -User user1, user2
/// </code>
/// <para>
/// Gets the users 'user1' and 'user2' from the db1 database
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaDbUser -SqlInstance Server1 -Login login1, login2
/// </code>
/// <para>
/// Gets the users associated with the logins 'login1' and 'login2'
/// </para>
/// </example>
/// <list type="alertSet">
/// <item>
/// <term />
/// <description>
/// <para>
/// Tags: User, Database
/// Author: Klaas Vandenberghe (@PowerDbaKlaas)
/// </para>
/// <para>
/// Website: https://dbatools.io
/// Copyright: (c) 2018 by dbatools, licensed under MIT
/// License: MIT https://opensource.org/licenses/MIT
/// </para>
/// </description>
/// </item>
/// </list>
/// <seealso href="https://dbatools.io/Get-DbaDbUser" />
[Cmdlet(VerbsCommon.Get, "DbaDbUser")]
public sealed class GetDbaDbUserCommand : DbaInstanceCmdlet
{
    private const string DatabaseCommand = "Get-DbaDatabase";
    private const string RawDatabasesCommand = "Invoke-QueryRawDatabases";
    private const int OfflineState = 6;

    // PS: the default -Status of Get-DbaDatabase, with any overlap sufficient.
    private const DatabaseStatus ListedStatus = DatabaseStatus.EmergencyMode | DatabaseStatus.Normal | DatabaseStatus.Offline |
        DatabaseStatus.Recovering | DatabaseStatus.RecoveryPending | DatabaseStatus.Restoring | DatabaseStatus.Standby | DatabaseStatus.Suspect;

    /// <para>
    /// The target SQL Server instance or instances
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
    /// Specifies which databases to query for user accounts. Accepts multiple database names and supports wildcards.
    /// Use this when you need to audit users in specific databases rather than scanning all databases on the instance.
    /// </para>
    [Parameter(Position = 2)]
    public object[]? Database { get; set; }

    /// <para>
    /// Specifies databases to skip when retrieving user accounts. Useful for excluding system databases or databases you don't manage.
    /// Common practice is to exclude tempdb, model, or development databases when focusing on production user access reviews.
    /// </para>
    [Parameter(Position = 3)]
    public object[]? ExcludeDatabase { get; set; }

    /// <para>
    /// Excludes built-in system users like 'dbo', 'guest', 'INFORMATION_SCHEMA', and other system-created accounts.
    /// Use this switch during security audits to focus only on custom user accounts that require regular access review and management.
    /// </para>
    [Parameter]
    public SwitchParameter ExcludeSystemUser { get; set; }

    /// <para>
    /// Filters results to specific database user names. Accepts multiple user names for targeted queries.
    /// Use this when investigating specific user accounts or verifying permissions for particular users during access reviews or troubleshooting.
    /// </para>
    [Parameter(Position = 4)]
    [PsStringArrayCast]
    public string[]? User { get; set; }

    /// <para>
    /// Filters results to database users associated with specific server logins. Shows which databases a login has user accounts in.
    /// Essential for understanding a login's database-level access across the instance, especially during user access audits or when removing departing employees.
    /// </para>
    [Parameter(Position = 5)]
    [PsStringArrayCast]
    public string[]? Login { get; set; }

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
            Server? server = ConnectInstance(instance, "Failure");
            if (server is null)
                continue;

            foreach (SmoDatabase database in SelectDatabases(server))
                WriteUsers(server, database);
        }
    }

    // PS: Get-DbaDatabase -SqlInstance $server -SqlCredential $SqlCredential -Database $Database -ExcludeDatabase $ExcludeDatabase -OnlyAccessible: its Where-Object filters
    // over the rows of sys.databases, in their order, on the connection this command already has. It gets no -EnableException.
    // Correction database-wildcards: the pinned help documents wildcards for -Database, which the exact -in of Get-DbaDatabase never honoured (wildcard-database). It documents
    // none for -ExcludeDatabase, which stays exact (wildcard-exclude-database). The instance's own names decide which pattern values are real names and stay literal.
    private List<SmoDatabase> SelectDatabases(Server server)
    {
        List<SmoDatabase> selected = new();
        bool azure = SmoServerExtensions.GetIsAzure(server);
        DataTable? rows = ReadDatabaseRows(server, azure);
        if (rows is null)
            return selected;

        List<string> names = new();
        foreach (DataRow row in rows.Rows)
            names.Add(NativeDatabaseNotes.RowName(row));

        // PS: the [string[]] parameters of Get-DbaDatabase take these [object[]] values, so a null element reads as "" and an object as its text (database-null-element).
        string[]? included = ToNames(Database);
        string[]? excluded = ToNames(ExcludeDatabase);
        WildcardNameMatcher includes = NativeDatabaseSelection.CreateNameMatcher(included, true, names);
        WildcardNameMatcher excludes = NativeDatabaseSelection.CreateNameMatcher(excluded, false, names);
        bool including = LanguagePrimitives.IsTrue(included);
        bool excluding = LanguagePrimitives.IsTrue(excluded);

        List<SmoDatabase>? known = KnownDatabases(server);
        DataTable? sizes = azure ? null : NativeDatabaseNotes.ReadInstanceSizes(this, server);
        foreach (DataRow row in rows.Rows)
        {
            string name = NativeDatabaseNotes.RowName(row);
            if ((including && !includes.Matches(name)) || (excluding && excludes.Matches(name)))
                continue;
            if (Convert.ToInt32(row["state"], CultureInfo.InvariantCulture) == OfflineState)
                continue;
            foreach (SmoDatabase database in Named(server, known, name))
            {
                // PS: the Azure branch of Get-DbaDatabase reads neither IsAccessible nor Status.
                if (azure || IsAccessibleAndListed(database))
                {
                    NativeDatabaseNotes.AddDatabaseNotes(server, database, row, sizes, azure);
                    selected.Add(database);
                }
            }
        }
        return selected;
    }

    private static string[]? ToNames(object[]? values)
    {
        return values is null ? null : (string[])LanguagePrimitives.ConvertTo(values, typeof(string[]), CultureInfo.InvariantCulture);
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

    // PS: $server.Databases, enumerated once here; the pin enumerates the same cached collection for each row. Its catch was written for a failure its comment could not reproduce,
    // and neither can a native test; disclosed in the corrections record, raw-databases-untested.
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
            WriteAttributedMessage(DatabaseCommand, MessageLevel.Verbose, "Failure: " + EnumerationFault(failure).Exception.Message);
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
            if (String.Equals(database.Name, name, StringComparison.Ordinal))
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

    // PS: $_.IsAccessible -in $true and the -Status overlap. The default ReadOnly and IsSystemObject filters list both values, so they pass every database whose value can be read;
    // a getter that fails reads as $null, which they drop. A connection that read IsAccessible before a hold keeps reading true, and the users then fault (evidence/pin-user2).
    private static bool IsAccessibleAndListed(SmoDatabase database)
    {
        try
        {
            _ = database.ReadOnly;
            _ = database.IsSystemObject;
            return database.IsAccessible && (database.Status & ListedStatus) != 0;
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            return false;
        }
    }

    // PS: $users = $db.users, then a statement per active filter and the ForEach-Object over what they left. if (!$users) never fires, and its "No users exist" line with it:
    // the collection is not a list, so it reads as true however many users it holds (every case's verbose list is empty).
    private void WriteUsers(Server server, SmoDatabase database)
    {
        List<SmoUser>? users = null;
        if (ExcludeSystemUser.ToBool())
            users = Filter(database, users, user => !user.IsSystemObject);
        if (TestBound(nameof(User)))
            users = Filter(database, users, user => IsNamed(User, user.Name));
        if (TestBound(nameof(Login)))
            users = Filter(database, users, user => IsNamed(Login, user.Login));

        foreach (SmoUser user in users ?? ReadUsers(database) ?? new List<SmoUser>())
            WriteObject(Decorate(server, database, user));
    }

    // PS: $users = $users | Where-Object { ... }. A fault leaves $users the collection, so the next statement enumerates it again, and each writes a record (held-user, held-all-filters).
    private List<SmoUser>? Filter(SmoDatabase database, List<SmoUser>? users, Func<SmoUser, bool> keep)
    {
        List<SmoUser>? read = users ?? ReadUsers(database);
        if (read is null)
            return null;

        List<SmoUser> kept = new();
        foreach (SmoUser user in read)
        {
            if (Keeps(keep, user))
                kept.Add(user);
        }
        return kept;
    }

    // A getter that fails reads as $null, which neither -eq $false nor -in keeps.
    private static bool Keeps(Func<SmoUser, bool> keep, SmoUser user)
    {
        try
        {
            return keep(user);
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            return false;
        }
    }

    // PS: -in over a [string[]], exact and in any case: no wildcards (user-wildcard, login-wildcard), and a null array holds nothing (user-null, login-null).
    private static bool IsNamed(string[]? names, string value)
    {
        foreach (string name in names ?? Array.Empty<string>())
        {
            if (LanguagePrimitives.Equals(name, value, true, CultureInfo.InvariantCulture))
                return true;
        }
        return false;
    }

    // PS: the pipeline over $db.users, which enumerates the collection; SMO keeps what it read, so the fault comes only from a read that has not yet worked.
    private List<SmoUser>? ReadUsers(SmoDatabase database)
    {
        try
        {
            List<SmoUser> users = new();
            foreach (SmoUser user in database.Users)
                users.Add(user);
            return users;
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            SurfaceFault(EnumerationFault(failure));
            return null;
        }
    }

    // Add-Member -Force and Select-DefaultView.
    private static PSObject Decorate(Server server, SmoDatabase database, SmoUser user)
    {
        PSObject output = PSObject.AsPSObject(user);
        NativeDatabaseNotes.AddInstanceNotes(output, server);
        output.Properties.Remove("Database");
        output.Properties.Add(new PSNoteProperty("Database", database.Name));
        OutputHelper.SetDefaultDisplayPropertySet(output, "ComputerName", "InstanceName", "SqlInstance", "Database", "CreateDate", "DateLastModified", "Name", "Login", "LoginType",
            "AuthenticationType", "State", "HasDbAccess", "DefaultSchema");
        return output;
    }

    // Accepted differences from the pin at these statements (harness-edits.md, keep-going and StatementFault sections; "Script-scope preferences and the one-line connect warning", point 1).
    // -EnableException stops here with the record; the pin ignores the switch at them and goes on (held-ee). $ErrorActionPreference = "Stop" set in the caller's scope or at a
    // script's top stops at this WriteError, and "SilentlyContinue" there silences the record, as for any compiled command; the pin ignores both there.
    private void SurfaceFault(ErrorRecord fault)
    {
        if (EnableException.ToBool())
        {
            // caller-try: terminate -- -EnableException asks for the stop
            ThrowTerminatingError(fault); // style-ok: cs-raw-streams a statement fault of the pin, outside Stop-Function
        }

        // A plain call writes the record and goes on, as the pin does; under a caller's try the record stops the command, as the fault stops the pin's statement.
        StatementFault.Surface(this, fault);
    }

    // PS: the engine's record for a collection that faults when a pipeline enumerates it (held-plain).
    private static ErrorRecord EnumerationFault(Exception failure)
    {
        return new ErrorRecord(new ExtendedTypeSystemException(String.Format(CultureInfo.InvariantCulture,
            "The following exception occurred while trying to enumerate the collection: \"{0}\".", failure.Message), failure),
            "ExceptionInGetEnumerator", ErrorCategory.NotSpecified, null);
    }
}
