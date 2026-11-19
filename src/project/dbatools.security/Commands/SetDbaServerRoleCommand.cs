#nullable enable

using System;
using System.Collections.Generic;
using System.Collections.Specialized;
using System.Management.Automation;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;
using SmoServerRole = Microsoft.SqlServer.Management.Smo.ServerRole;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Alters server roles. Completes the server-role CRUD family (New-/Get-/Remove-DbaServerRole
/// already existed; no Set- did) - and unlike the rest of the security-principals batch, its module
/// placement (dbatools.security) already matches its family. NEW designed command - no PS ancestor,
/// pure C#, no hop. Surface pinned by migration/designed/Set-DbaServerRole.json (signed 2026-07-21).
///
/// ALTER DOES EXACTLY ONE THING - CHANGE THE OWNER, and it carries a hard SQL 2012 floor.
/// ServerRole.Alter() (Smo/ServerRoleBase.cs:42) routes to ScriptAlter (:105-117), which calls
/// ThrowIfSourceOrDestBelowVersion110 (:107, floor is ServerVersion.Major &lt; 11), then rejects a
/// dirty empty-string Owner with FailedOperationException (:111-114), then delegates to
/// ScriptChangeOwner (Smo/SqlSmoObject.cs:382/:399-411), emitting
/// "ALTER AUTHORIZATION ON &lt;prefix&gt;&lt;role&gt; TO [owner]" only when Owner is dirty. This command connects
/// with a 2012 minimum and StopFunctions gracefully below it, and validates -Owner non-empty up
/// front, rather than surfacing raw SMO exceptions.
///
/// RENAME IS A SEPARATE DDL ROUND-TRIP, NOT PART OF Alter(). Rename() (:70) routes through RenameImpl
/// and its own ScriptRename (:125-131), unreachable from ScriptAlter. So -NewName drives a SECOND
/// statement (also 2012-floored), which is why this command declares TWO shouldProcessTargets: the
/// two operations are not atomic together.
///
/// FIXED ROLES - THE RESPONSIBILITY IS THE CMDLET'S. The catalog reads as though SMO blocks altering
/// a fixed role; it does NOT on the Alter/Rename path (there is no IsFixedRole check in ScriptAlter
/// or ScriptRename). So this command reads IsFixedRole itself and StopFunctions per item before
/// touching Owner or calling Rename - without it the user gets a raw server error.
///
/// MEMBERSHIP IS NOT ON THIS SURFACE. Add-DbaServerRoleMember and Remove-DbaServerRoleMember already
/// own it, so there is deliberately no -Member/-Login even though SMO exposes AddMember/AddMembership.
/// But output DECORATION still calls EnumMemberNames() for the Login note-property, exactly as
/// Get-DbaServerRole does - omitting it would silently change the shape of piped objects.
///
/// DUALITY. Either -SqlInstance or -InputObject, no parameter sets (new-commands.md 1.2). -ServerRole
/// is REQUIRED on the -SqlInstance feeder.
/// </summary>
[Cmdlet(VerbsCommon.Set, "DbaServerRole", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
[OutputType(typeof(Microsoft.SqlServer.Management.Smo.ServerRole))]
public sealed class SetDbaServerRoleCommand : DbaInstanceCmdlet
{
    /// <summary>The target SQL Server instance or instances (SQL Server 2012 or later).</summary>
    [Parameter(Position = 0)]
    public override DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter(Position = 1)]
    public override PSCredential? SqlCredential { get; set; }

    /// <summary>The server role(s) to alter. Required when -SqlInstance is used.</summary>
    [Parameter(Position = 2)]
    public string[]? ServerRole { get; set; }

    /// <summary>The login that should own the role.</summary>
    [Parameter(Position = 3)]
    public string? Owner { get; set; }

    /// <summary>Renames the role. A SECOND statement against the server, not part of the alter.</summary>
    [Parameter(Position = 4)]
    public string? NewName { get; set; }

    /// <summary>SMO ServerRole object(s) from Get-DbaServerRole.</summary>
    [Parameter(ValueFromPipeline = true, Position = 5)]
    public SmoServerRole[]? InputObject { get; set; }

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

        // SMO throws FailedOperationException on a dirty empty Owner - validate up front with a
        // dbatools message instead. An unbound Owner is fine (no owner change requested).
        if (TestBound(nameof(Owner)) && String.IsNullOrEmpty(Owner))
        {
            StopFunction("Owner cannot be an empty string");
            return;
        }

        if (TestBound(nameof(SqlInstance)))
        {
            if (!FilterHelper.IsActive(ServerRole))
            {
                StopFunction("ServerRole is required when SqlInstance is specified");
                return;
            }

            foreach (DbaInstanceParameter instance in SqlInstance ?? Array.Empty<DbaInstanceParameter>())
            {
                // 2012 minimum - ConnectInstance StopFunctions per instance below the floor.
                Server? server = ConnectInstance(instance, "Failure", minimumVersion: 11);
                if (server is null)
                {
                    continue;
                }

                foreach (SmoServerRole role in ResolveRoles(server))
                {
                    ProcessRole(role);
                }
            }
        }

        // Feeder 2: ServerRole objects piped from Get-DbaServerRole. The parent server is resolved
        // PER RECORD (role.Parent = Server) - never carried across records.
        foreach (SmoServerRole role in InputObject ?? Array.Empty<SmoServerRole>())
        {
            ProcessRole(role);
        }
    }

    // One worker, two feeders (new-commands.md 1.2).
    private void ProcessRole(SmoServerRole role)
    {
        Server? server = role.Parent;
        if (server is null)
        {
            StopFunction(String.Format("Server role {0} has no parent server", role.Name),
                target: role, category: ErrorCategory.InvalidData, continueLoop: true);
            return;
        }

        string target = Dataplat.Dbatools.Connection.SmoServerExtensions.GetDomainInstanceName(server);

        // Both alter and rename are 2012-floored. The InputObject feeder does not pass through the
        // minimumVersion connect, so the floor is enforced here for every record uniformly.
        if (server.VersionMajor < 11)
        {
            StopFunction(String.Format("Altering a server role requires SQL Server 2012 or later; {0} is version {1}", target, server.VersionMajor),
                target: role, category: ErrorCategory.InvalidOperation, continueLoop: true);
            return;
        }

        // SMO does not stop an Alter/Rename on a fixed role - check it here so the failure is
        // specific and per-item rather than a raw server error.
        if (role.IsFixedRole)
        {
            StopFunction(String.Format("Server role {0} is a fixed role and cannot be altered", role.Name),
                target: role, category: ErrorCategory.InvalidOperation, continueLoop: true);
            return;
        }

        if (TestBound(nameof(Owner)))
        {
            // ShouldProcess strings are VERBATIM from the signed spec's shouldProcessTargets.
            string alterAction = String.Format("Altering server role {0}", role.Name);
            if (ShouldProcess(target, alterAction))
            {
                try
                {
                    role.Owner = Owner;
                    role.Alter();
                }
                catch (Exception ex)
                {
                    StopFunction(String.Format("Failure altering server role {0} on {1}", role.Name, target),
                        target: role,
                        errorRecord: new ErrorRecord(ex, "dbatools_SetDbaServerRole", ErrorCategory.InvalidOperation, role),
                        continueLoop: true);
                    return;
                }
            }
        }

        if (TestBound(nameof(NewName)))
        {
            // The rename is a SECOND round-trip with its OWN ShouldProcess. -WhatIf must show both.
            string renameAction = String.Format("Renaming server role {0} to {1}", role.Name, NewName);
            if (ShouldProcess(target, renameAction))
            {
                if (String.IsNullOrEmpty(NewName))
                {
                    StopFunction("NewName cannot be empty", target: role,
                        category: ErrorCategory.InvalidArgument, continueLoop: true);
                    return;
                }

                try
                {
                    role.Rename(NewName);
                }
                catch (Exception ex)
                {
                    StopFunction(String.Format("Failure renaming server role {0} on {1}", role.Name, target),
                        target: role,
                        errorRecord: new ErrorRecord(ex, "dbatools_SetDbaServerRole", ErrorCategory.InvalidOperation, role),
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

        WriteRole(role, server);
    }

    // Decorated exactly like Get-DbaServerRole (GetDbaServerRoleCommand.cs:141-150) so Get -> Set ->
    // Get composes. Replace-then-add, never AddInstanceProperties: anything piped in from the
    // getCounterpart is ALREADY decorated and Properties.Add throws on a duplicate member name. The
    // Login note-property comes from EnumMemberNames() even though this command does not manage
    // membership - omitting it would change the shape of piped objects.
    private void WriteRole(SmoServerRole role, Server server)
    {
        StringCollection members;
        try
        {
            members = role.EnumMemberNames();
        }
        catch (Exception)
        {
            members = new StringCollection();
        }

        PSObject wrapped = PSObject.AsPSObject(role);
        ReplaceNoteProperty(wrapped, "Login", members);
        ReplaceNoteProperty(wrapped, "ComputerName", Dataplat.Dbatools.Connection.SmoServerExtensions.GetComputerName(server));
        ReplaceNoteProperty(wrapped, "InstanceName", server.ServiceName);
        ReplaceNoteProperty(wrapped, "SqlInstance", Dataplat.Dbatools.Connection.SmoServerExtensions.GetDomainInstanceName(server));
        ReplaceNoteProperty(wrapped, "Role", role.Name);
        ReplaceNoteProperty(wrapped, "ServerRole", role.Name);
        OutputHelper.SetDefaultDisplayPropertySet(wrapped,
            "ComputerName", "InstanceName", "SqlInstance", "Role", "Login", "Owner", "IsFixedRole", "DateCreated", "DateModified");
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

    // Not a lazy iterator ON PURPOSE: a requested-but-missing role must be REPORTED (warn + continue,
    // terminating under -EnableException), never silently skipped.
    private List<SmoServerRole> ResolveRoles(Server server)
    {
        List<SmoServerRole> resolved = new();

        foreach (string roleName in ServerRole ?? Array.Empty<string>())
        {
            SmoServerRole? role = server.Roles[roleName];
            if (role is null)
            {
                StopFunction(String.Format("Server role {0} does not exist on {1}", roleName, server.Name),
                    target: roleName, category: ErrorCategory.ObjectNotFound, continueLoop: true);
                continue;
            }

            resolved.Add(role);
        }

        return resolved;
    }
}
