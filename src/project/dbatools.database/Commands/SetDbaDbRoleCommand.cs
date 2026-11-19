#nullable enable

using System;
using System.Collections.Generic;
using System.Management.Automation;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;
using SmoDatabase = Microsoft.SqlServer.Management.Smo.Database;
using SmoDatabaseRole = Microsoft.SqlServer.Management.Smo.DatabaseRole;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Alters database roles. Completes the database-role CRUD family (New-/Get-/Remove-DbaDbRole
/// already existed; no Set- did). NEW designed command - no PS ancestor, pure C#, no hop. Surface
/// pinned by migration/designed/Set-DbaDbRole.json (signed 2026-07-21).
///
/// ALTER DOES EXACTLY ONE THING - CHANGE THE OWNER. DatabaseRole.Alter() (Smo/DatabaseRoleBase.cs:542)
/// routes to ScriptAlter (:548-551), whose entire body is ScriptChangeOwner (Smo/SqlSmoObject.cs:382),
/// which fires only when the Owner property is non-null AND dirty and emits
/// "ALTER AUTHORIZATION ON &lt;prefix&gt;&lt;role&gt; TO [owner]" (:399-411). So Alter() on a role with a clean
/// Owner emits nothing. Owner is the one hand-written property on the class (:523-540); its setter
/// calls ThrowIfBelowVersion90 before SetValueWithConsistencyCheck, so owner changes require SQL
/// 2005+. There is no SetOwner() on either role class, so this command sets the property and calls
/// Alter().
///
/// RENAME IS A SEPARATE DDL ROUND-TRIP, NOT PART OF Alter(). Rename() (:477) goes through RenameImpl
/// and its own ScriptRename (:482-492), unreachable from ScriptAlter. So -NewName drives a SECOND
/// statement against the server, which is why this command declares TWO shouldProcessTargets: the two
/// operations are not atomic together. ScriptRename floors at ServerVersion.Major &lt; 9 (SQL 2005),
/// emitting "ALTER ROLE &lt;name&gt; WITH NAME=&lt;new&gt;". The catalog's "rename needs SQL 2012+" is wrong for
/// THIS command - that 2012 floor belongs to Set-DbaServerRole (Smo/ServerRoleBase.cs:107).
///
/// FIXED ROLES. DatabaseRole carries IsFixedRole. SMO does NOT block altering a fixed role on the
/// Alter path, so this command checks IsFixedRole itself and StopFunctions per item rather than
/// letting the server raise a less specific error.
///
/// MEMBERSHIP IS NOT ON THIS SURFACE. Add-DbaDbRoleMember and Remove-DbaDbRoleMember already own it,
/// so there is deliberately no -Member/-Login/-User even though SMO exposes AddMember/DropMember.
///
/// DUALITY. Either -SqlInstance or -InputObject, no parameter sets (new-commands.md 1.2).
/// -ExcludeDatabase applies to the -SqlInstance feeder only. -Role is REQUIRED on that feeder.
/// </summary>
[Cmdlet(VerbsCommon.Set, "DbaDbRole", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
[OutputType(typeof(Microsoft.SqlServer.Management.Smo.DatabaseRole))]
public sealed class SetDbaDbRoleCommand : DbaInstanceCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    public override DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter(Position = 1)]
    public override PSCredential? SqlCredential { get; set; }

    /// <summary>The database(s) holding the role(s) to alter.</summary>
    [Parameter(Position = 2)]
    public string[]? Database { get; set; }

    /// <summary>The database(s) to skip. Applies to the -SqlInstance feeder only.</summary>
    [Parameter(Position = 3)]
    public string[]? ExcludeDatabase { get; set; }

    /// <summary>The database role(s) to alter. Required when -SqlInstance is used.</summary>
    [Parameter(Position = 4)]
    public string[]? Role { get; set; }

    /// <summary>The database user that should own the role.</summary>
    [Parameter(Position = 5)]
    public string? Owner { get; set; }

    /// <summary>Renames the role. A SECOND statement against the server, not part of the alter.</summary>
    [Parameter(Position = 6)]
    public string? NewName { get; set; }

    /// <summary>SMO DatabaseRole object(s) from Get-DbaDbRole.</summary>
    [Parameter(ValueFromPipeline = true, Position = 7)]
    public SmoDatabaseRole[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        // The duality check lives here rather than in BeginProcessing because a pipeline-bound
        // InputObject does not appear in BoundParameters until ProcessRecord.
        if (!TestBound(nameof(SqlInstance), nameof(InputObject)))
        {
            StopFunction("You must supply either -SqlInstance or an Input Object");
            return;
        }

        if (TestBound(nameof(SqlInstance)))
        {
            if (!FilterHelper.IsActive(Role))
            {
                StopFunction("Role is required when SqlInstance is specified");
                return;
            }

            foreach (DbaInstanceParameter instance in SqlInstance ?? Array.Empty<DbaInstanceParameter>())
            {
                Server? server = ConnectInstance(instance, "Failure");
                if (server is null)
                {
                    continue;
                }

                foreach (SmoDatabaseRole role in ResolveRoles(server))
                {
                    ProcessRole(role);
                }
            }
        }

        // Feeder 2: DatabaseRole objects piped from Get-DbaDbRole. The parent chain is resolved PER
        // RECORD (role.Parent = Database, .Parent = Server) - never carried across records.
        foreach (SmoDatabaseRole role in InputObject ?? Array.Empty<SmoDatabaseRole>())
        {
            ProcessRole(role);
        }
    }

    // One worker, two feeders (new-commands.md 1.2).
    private void ProcessRole(SmoDatabaseRole role)
    {
        SmoDatabase? db = role.Parent;
        if (db is null)
        {
            StopFunction(String.Format("Database role {0} has no parent database", role.Name),
                target: role, category: ErrorCategory.InvalidData, continueLoop: true);
            return;
        }

        Server? server = db.Parent;
        if (server is null)
        {
            StopFunction(String.Format("Database {0} has no parent server", db.Name),
                target: role, category: ErrorCategory.InvalidData, continueLoop: true);
            return;
        }

        // SMO does not stop an Alter/Rename on a fixed role - check it here so the failure is
        // specific and per-item rather than a raw server error.
        if (role.IsFixedRole)
        {
            StopFunction(String.Format("Database role {0} in database {1} is a fixed role and cannot be altered", role.Name, db.Name),
                target: role, category: ErrorCategory.InvalidOperation, continueLoop: true);
            return;
        }

        string target = Dataplat.Dbatools.Connection.SmoServerExtensions.GetDomainInstanceName(server);

        if (TestBound(nameof(Owner)))
        {
            // ShouldProcess strings are VERBATIM from the signed spec's shouldProcessTargets.
            string alterAction = String.Format("Altering database role {0} in database {1}", role.Name, db.Name);
            if (ShouldProcess(target, alterAction))
            {
                try
                {
                    role.Owner = Owner;
                    role.Alter();
                }
                catch (Exception ex)
                {
                    StopFunction(String.Format("Failure altering database role {0} in database {1} on {2}", role.Name, db.Name, target),
                        target: role,
                        errorRecord: new ErrorRecord(ex, "dbatools_SetDbaDbRole", ErrorCategory.InvalidOperation, role),
                        continueLoop: true);
                    return;
                }
            }
        }

        if (TestBound(nameof(NewName)))
        {
            // The rename is a SECOND round-trip with its OWN ShouldProcess, exactly as the spec's
            // second shouldProcessTargets entry declares. -WhatIf must show both lines.
            string renameAction = String.Format("Renaming database role {0} to {1} in database {2}", role.Name, NewName, db.Name);
            if (ShouldProcess(target, renameAction))
            {
                if (String.IsNullOrEmpty(NewName))
                {
                    StopFunction("NewName cannot be empty", target: role,
                        category: ErrorCategory.InvalidArgument, continueLoop: true);
                    return;
                }

                if (server.VersionMajor < 9)
                {
                    // ScriptRename floors at server major < 9 (Smo/DatabaseRoleBase.cs:484-487).
                    StopFunction(String.Format("Renaming a database role requires SQL Server 2005 or later; {0} is version {1}", target, server.VersionMajor),
                        target: role, category: ErrorCategory.InvalidOperation, continueLoop: true);
                    return;
                }

                try
                {
                    role.Rename(NewName);
                }
                catch (Exception ex)
                {
                    StopFunction(String.Format("Failure renaming database role {0} in database {1} on {2}", role.Name, db.Name, target),
                        target: role,
                        errorRecord: new ErrorRecord(ex, "dbatools_SetDbaDbRole", ErrorCategory.InvalidOperation, role),
                        continueLoop: true);
                    return;
                }
            }
        }

        try
        {
            role.Refresh();
        }
        catch (Exception)
        {
            // A refresh failure must not lose the object the caller just successfully altered.
        }

        WriteRole(role, db, server);
    }

    // Decorated exactly like Get-DbaDbRole (GetDbaDbRoleCommand.cs:147-152) so Get -> Set -> Get
    // composes. Replace-then-add, never AddInstanceProperties: anything piped in from the
    // getCounterpart is ALREADY decorated and Properties.Add throws on a duplicate member name.
    // The view is only five columns and OMITS SqlInstance while carrying it as a NoteProperty - that
    // asymmetry is Get-DbaDbRole's and is reproduced verbatim because Get -> Set -> Get composition
    // is what section 1.5 binds to.
    private void WriteRole(SmoDatabaseRole role, SmoDatabase db, Server server)
    {
        PSObject wrapped = PSObject.AsPSObject(role);
        ReplaceNoteProperty(wrapped, "ComputerName", Dataplat.Dbatools.Connection.SmoServerExtensions.GetComputerName(server));
        ReplaceNoteProperty(wrapped, "InstanceName", server.ServiceName);
        ReplaceNoteProperty(wrapped, "SqlInstance", Dataplat.Dbatools.Connection.SmoServerExtensions.GetDomainInstanceName(server));
        ReplaceNoteProperty(wrapped, "Database", db.Name);
        OutputHelper.SetDefaultDisplayPropertySet(wrapped,
            "ComputerName", "InstanceName", "Database", "Name", "IsFixedRole");
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

    // Not a lazy iterator ON PURPOSE: a requested-but-missing database or role must be REPORTED
    // (warn + continue, terminating under -EnableException), never silently skipped.
    private List<SmoDatabaseRole> ResolveRoles(Server server)
    {
        List<SmoDatabaseRole> resolved = new();

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

            foreach (string roleName in Role ?? Array.Empty<string>())
            {
                SmoDatabaseRole? role = db.Roles[roleName];
                if (role is null)
                {
                    StopFunction(String.Format("Database role {0} does not exist in database {1} on {2}", roleName, db.Name, server.Name),
                        target: roleName, category: ErrorCategory.ObjectNotFound, continueLoop: true);
                    continue;
                }

                resolved.Add(role);
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
