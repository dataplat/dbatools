#nullable enable

using System;
using System.Collections.Generic;
using System.Management.Automation;
using System.Text;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;
using SmoDatabase = Microsoft.SqlServer.Management.Smo.Database;
using SmoUser = Microsoft.SqlServer.Management.Smo.User;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Alters database users. Completes the database-user CRUD family (New-/Get-/Remove-DbaDbUser
/// already existed; no Set- did). NEW designed command - no PS ancestor, pure C#, no hop. Surface
/// pinned by migration/designed/Set-DbaDbUser.json (signed 2026-07-21).
///
/// THE ALTERABLE SURFACE IS EXACTLY TWO PROPERTIES. User.Alter() (Smo/UserBase.cs:1108) routes to
/// ScriptAlter (:1157), which emits an ALTER USER only for DEFAULT_SCHEMA (:1170-1177, dirty-gated)
/// and LOGIN (:1189-1195, dirty-gated), plus DEFAULT_LANGUAGE via AddDefaultLanguageOptionToScript
/// (:1197). Everything else on User is unsettable post-creation: UserType is read_only_after_creation
/// (SqlEnum/xml/user.xml:70); AuthenticationType, LoginType and HasDBAccess are access='Read'
/// (:71, :50, :51). DEFAULT_LANGUAGE is deliberately omitted from this surface because
/// ValidateAlterInputs (:1113-1144) only permits it for contained users, which are out of scope for
/// v1 - a contained user's password is not settable through Alter() at all (it is a private field,
/// :31, mutated only by ChangePassword :717/:772).
///
/// RENAME IS A SEPARATE DDL ROUND-TRIP, NOT PART OF Alter(). ScriptRename (:1368-1379) emits its own
/// "ALTER USER &lt;name&gt; WITH NAME=&lt;new&gt;" (:1377) and is unreachable from ScriptAlter. Setting .Name and
/// calling Alter() silently does nothing. -NewName therefore drives Rename() (:1363) as a SECOND
/// statement against the server, which is why this command declares TWO shouldProcessTargets: the
/// two operations are not atomic together and the user must be able to see that.
///
/// UPSTREAM SMO DEFECT - "DEFAULT_SCHEMA==NULL", AND IT IS BROADER THAN THE SPEC RECORDED. The
/// else-branch at Smo/UserBase.cs:1178-1187 appends the literal string "DEFAULT_SCHEMA==NULL" with a
/// DOUBLE equals sign (:1185) whenever LoginType is WindowsGroup and the LIVE ServerVersion.Major is
/// >= 11 (:1182 - note it tests ServerVersion, not sp.TargetServerVersion like the rest of the
/// method). The signed spec described this as reachable "whenever this command clears DefaultSchema
/// on a Windows-group user on SQL 2012+". Reading the code, it is wider than that: the else-branch is
/// taken whenever the DefaultSchema property is not BOTH dirty AND non-empty (:1171-1172), so on a
/// Windows-group user at SQL 2012+ it also fires when the caller sets ONLY -Login, and when the
/// caller sets nothing at all. Every such Alter() emits malformed T-SQL and fails. This command
/// therefore does not route Windows-group users on major >= 11 through Alter() at all - it builds and
/// issues the correct ALTER USER itself (see AlterViaTsql). Recorded here rather than filed upstream
/// because dataplat does not own sqlmanagementobjects.
///
/// DUALITY. Either -SqlInstance or -InputObject, no parameter sets (new-commands.md 1.2).
/// -ExcludeDatabase applies to the -SqlInstance feeder only. -User is REQUIRED on that feeder: a Set-
/// that fans across every user in every database because a filter was omitted is not a defensible
/// default, and it mirrors how -LocalLogin is required on Set-DbaLinkedServerLogin.
/// </summary>
[Cmdlet(VerbsCommon.Set, "DbaDbUser", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
[OutputType(typeof(Microsoft.SqlServer.Management.Smo.User))]
public sealed class SetDbaDbUserCommand : DbaInstanceCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    public override DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter(Position = 1)]
    public override PSCredential? SqlCredential { get; set; }

    /// <summary>The database(s) holding the user(s) to alter. Unbound means every accessible database.</summary>
    [Parameter(Position = 2)]
    public string[]? Database { get; set; }

    /// <summary>The database(s) to skip. Applies to the -SqlInstance feeder only.</summary>
    [Parameter(Position = 3)]
    public string[]? ExcludeDatabase { get; set; }

    /// <summary>The database user(s) to alter. Required when -SqlInstance is used.</summary>
    [Parameter(Position = 4)]
    [Alias("Username")]
    public string[]? User { get; set; }

    /// <summary>The schema to make the user's default. Named exactly as on New-DbaDbUser.</summary>
    [Parameter(Position = 5)]
    public string? DefaultSchema { get; set; }

    /// <summary>Remaps the user to a different server login. Does not create the login.</summary>
    [Parameter(Position = 6)]
    public string? Login { get; set; }

    /// <summary>Renames the user. A SECOND statement against the server, not part of the alter.</summary>
    [Parameter(Position = 7)]
    public string? NewName { get; set; }

    /// <summary>SMO User object(s) from Get-DbaDbUser.</summary>
    [Parameter(ValueFromPipeline = true, Position = 8)]
    public SmoUser[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        // The duality check lives here rather than in BeginProcessing because a pipeline-bound
        // InputObject does not appear in BoundParameters until ProcessRecord - a Begin-time check
        // would false-fail pure pipeline usage.
        if (!TestBound(nameof(SqlInstance), nameof(InputObject)))
        {
            StopFunction("You must supply either -SqlInstance or an Input Object");
            return;
        }

        if (TestBound(nameof(SqlInstance)))
        {
            if (!FilterHelper.IsActive(User))
            {
                StopFunction("User is required when SqlInstance is specified");
                return;
            }

            foreach (DbaInstanceParameter instance in SqlInstance ?? Array.Empty<DbaInstanceParameter>())
            {
                Server? server = ConnectInstance(instance, "Failure");
                if (server is null)
                {
                    continue;
                }

                foreach (SmoUser user in ResolveUsers(server))
                {
                    ProcessUser(user);
                }
            }
        }

        // Feeder 2: User objects piped from Get-DbaDbUser. The parent chain is resolved PER RECORD
        // (user.Parent = Database, .Parent = Server) - never carried across records.
        foreach (SmoUser user in InputObject ?? Array.Empty<SmoUser>())
        {
            ProcessUser(user);
        }
    }

    // One worker, two feeders (new-commands.md 1.2).
    private void ProcessUser(SmoUser user)
    {
        SmoDatabase? db = user.Parent;
        if (db is null)
        {
            StopFunction(String.Format("Database user {0} has no parent database", user.Name),
                target: user, category: ErrorCategory.InvalidData, continueLoop: true);
            return;
        }

        Server? server = db.Parent;
        if (server is null)
        {
            StopFunction(String.Format("Database {0} has no parent server", db.Name),
                target: user, category: ErrorCategory.InvalidData, continueLoop: true);
            return;
        }

        string target = Dataplat.Dbatools.Connection.SmoServerExtensions.GetDomainInstanceName(server);
        bool alterRequested = TestBound(nameof(DefaultSchema)) || TestBound(nameof(Login));

        if (alterRequested)
        {
            // ShouldProcess strings are VERBATIM from the signed spec's shouldProcessTargets.
            string alterAction = String.Format("Altering database user {0} in database {1}", user.Name, db.Name);
            if (ShouldProcess(target, alterAction))
            {
                if (!Alter(user, db, server))
                {
                    return;
                }
            }
        }

        if (TestBound(nameof(NewName)))
        {
            // The rename is a SECOND round-trip with its OWN ShouldProcess, exactly as the spec's
            // second shouldProcessTargets entry declares. -WhatIf must show both lines.
            string renameAction = String.Format("Renaming database user {0} to {1} in database {2}", user.Name, NewName, db.Name);
            if (ShouldProcess(target, renameAction))
            {
                if (String.IsNullOrEmpty(NewName))
                {
                    StopFunction("NewName cannot be empty", target: user,
                        category: ErrorCategory.InvalidArgument, continueLoop: true);
                    return;
                }

                if (server.VersionMajor < 9)
                {
                    // ScriptRename floors at server major < 9 (Smo/UserBase.cs:1370-1372); surfaced
                    // here as a message rather than letting SMO throw an opaque version exception.
                    StopFunction(String.Format("Renaming a database user requires SQL Server 2005 or later; {0} is version {1}", target, server.VersionMajor),
                        target: user, category: ErrorCategory.InvalidOperation, continueLoop: true);
                    return;
                }

                try
                {
                    user.Rename(NewName);
                }
                catch (Exception ex)
                {
                    StopFunction(String.Format("Failure renaming database user {0} in database {1} on {2}", user.Name, db.Name, target),
                        target: user,
                        errorRecord: new ErrorRecord(ex, "dbatools_SetDbaDbUser", ErrorCategory.InvalidOperation, user),
                        continueLoop: true);
                    return;
                }
            }
        }

        try
        {
            user.Refresh();
        }
        catch (Exception)
        {
            // A refresh failure must not lose the object the caller just successfully altered.
        }

        WriteUser(user, db, server);
    }

    // Returns false when the alter failed and the record should be abandoned.
    private bool Alter(SmoUser user, SmoDatabase db, Server server)
    {
        string target = Dataplat.Dbatools.Connection.SmoServerExtensions.GetDomainInstanceName(server);

        try
        {
            // The upstream DEFAULT_SCHEMA==NULL defect (see the class remarks) makes Alter()
            // unusable for Windows-group users on SQL 2012+ UNLESS DefaultSchema is being set to a
            // non-empty value, which is the one path that takes the correct if-branch at
            // Smo/UserBase.cs:1171-1177. Every other combination falls into the malformed
            // else-branch, so those go through T-SQL this command emits itself.
            bool settingSchemaToValue = TestBound(nameof(DefaultSchema)) && !String.IsNullOrEmpty(DefaultSchema);
            bool windowsGroupTrap = server.VersionMajor >= 11
                && user.LoginType == LoginType.WindowsGroup
                && !settingSchemaToValue;

            if (windowsGroupTrap)
            {
                return AlterViaTsql(user, db, server);
            }

            if (TestBound(nameof(DefaultSchema)))
            {
                if (String.IsNullOrEmpty(DefaultSchema))
                {
                    // Clearing DEFAULT_SCHEMA is only legal for Windows-group users on 2012+, which
                    // is the branch above. SMO would silently emit nothing here; say so instead.
                    WriteMessage(MessageLevel.Warning,
                        String.Format("Clearing -DefaultSchema is only supported for Windows group users on SQL Server 2012 or later; leaving the default schema on {0} in {1} unchanged", user.Name, db.Name),
                        target: user);
                }
                else
                {
                    user.DefaultSchema = DefaultSchema;
                }
            }

            if (TestBound(nameof(Login)))
            {
                if (String.IsNullOrEmpty(Login))
                {
                    // LOGIN is dirty-gated on a non-empty value (Smo/UserBase.cs:1190-1191), so an
                    // empty -Login emits nothing rather than unmapping the user.
                    WriteMessage(MessageLevel.Warning,
                        String.Format("-Login cannot be cleared; leaving the login mapping on {0} in {1} unchanged", user.Name, db.Name),
                        target: user);
                }
                else
                {
                    user.Login = Login;
                }
            }

            user.Alter();
        }
        catch (Exception ex)
        {
            StopFunction(String.Format("Failure altering database user {0} in database {1} on {2}", user.Name, db.Name, target),
                target: user,
                errorRecord: new ErrorRecord(ex, "dbatools_SetDbaDbUser", ErrorCategory.InvalidOperation, user),
                continueLoop: true);
            return false;
        }

        return true;
    }

    // The correct ALTER USER that SMO fails to emit for Windows-group users on SQL 2012+. Builds only
    // the clauses the caller actually bound - an omitted clause genuinely leaves that property alone,
    // which is true of ALTER USER and is why no state-restatement is needed here.
    private bool AlterViaTsql(SmoUser user, SmoDatabase db, Server server)
    {
        string target = Dataplat.Dbatools.Connection.SmoServerExtensions.GetDomainInstanceName(server);
        StringBuilder options = new StringBuilder();

        if (TestBound(nameof(DefaultSchema)))
        {
            // Bound and empty is the only way to reach here with a schema clause, since a non-empty
            // value would have kept us on the SMO path.
            options.Append("DEFAULT_SCHEMA=NULL");
        }

        if (TestBound(nameof(Login)) && !String.IsNullOrEmpty(Login))
        {
            if (options.Length > 0)
            {
                options.Append(", ");
            }
            options.Append("LOGIN=").Append(QuoteName(Login!));
        }

        if (options.Length == 0)
        {
            return true;
        }

        string sql = String.Format("ALTER USER {0} WITH {1}", QuoteName(user.Name), options);

        try
        {
            db.ExecuteNonQuery(sql);
        }
        catch (Exception ex)
        {
            StopFunction(String.Format("Failure altering database user {0} in database {1} on {2}", user.Name, db.Name, target),
                target: user,
                errorRecord: new ErrorRecord(ex, "dbatools_SetDbaDbUser", ErrorCategory.InvalidOperation, user),
                continueLoop: true);
            return false;
        }

        return true;
    }

    // Decorated exactly like Get-DbaDbUser (GetDbaDbUserCommand.cs:149-154) so Get -> Set -> Get
    // composes. Replace-then-add, never AddInstanceProperties: anything piped in from the
    // getCounterpart is ALREADY decorated and Properties.Add throws on a duplicate member name.
    // The view spells it HasDbAccess while the SMO property is HasDBAccess - PowerShell resolves the
    // view string case-insensitively, and the string is reproduced here exactly as Get- emits it.
    private void WriteUser(SmoUser user, SmoDatabase db, Server server)
    {
        PSObject wrapped = PSObject.AsPSObject(user);
        ReplaceNoteProperty(wrapped, "ComputerName", Dataplat.Dbatools.Connection.SmoServerExtensions.GetComputerName(server));
        ReplaceNoteProperty(wrapped, "InstanceName", server.ServiceName);
        ReplaceNoteProperty(wrapped, "SqlInstance", Dataplat.Dbatools.Connection.SmoServerExtensions.GetDomainInstanceName(server));
        ReplaceNoteProperty(wrapped, "Database", db.Name);
        OutputHelper.SetDefaultDisplayPropertySet(wrapped,
            "ComputerName", "InstanceName", "SqlInstance", "Database", "CreateDate", "DateLastModified",
            "Name", "Login", "LoginType", "AuthenticationType", "State", "HasDbAccess", "DefaultSchema");
        WriteObject(wrapped);
    }

    private static void ReplaceNoteProperty(PSObject wrapped, string name, object? value)
    {
        if (wrapped.Properties[name] is PSNoteProperty)
        {
            wrapped.Properties.Remove(name);
        }
        wrapped.Properties.Add(new PSNoteProperty(name, value));
    }

    private static string QuoteName(string name)
    {
        return String.Format("[{0}]", name.Replace("]", "]]"));
    }

    // Not a lazy iterator ON PURPOSE: a requested-but-missing database or user must be REPORTED
    // (warn + continue, terminating under -EnableException), never silently skipped.
    private List<SmoUser> ResolveUsers(Server server)
    {
        List<SmoUser> resolved = new();

        foreach (SmoDatabase db in server.Databases)
        {
            if (FilterHelper.IsActive(Database) && !ContainsName(Database!, db.Name))
            {
                continue;
            }

            if (FilterHelper.IsActive(ExcludeDatabase) && ContainsName(ExcludeDatabase!, db.Name))
            {
                continue;
            }

            if (!db.IsAccessible)
            {
                WriteMessage(MessageLevel.Warning, String.Format("{0} is not accessible, skipping", db.Name), target: db);
                continue;
            }

            foreach (string userName in User ?? Array.Empty<string>())
            {
                SmoUser? user = db.Users[userName];
                if (user is null)
                {
                    StopFunction(String.Format("Database user {0} does not exist in database {1} on {2}", userName, db.Name, server.Name),
                        target: userName, category: ErrorCategory.ObjectNotFound, continueLoop: true);
                    continue;
                }

                resolved.Add(user);
            }
        }

        return resolved;
    }

    private static bool ContainsName(string[] values, string? name)
    {
        foreach (string value in values)
        {
            if (String.Equals(value, name, StringComparison.OrdinalIgnoreCase))
            {
                return true;
            }
        }
        return false;
    }
}
