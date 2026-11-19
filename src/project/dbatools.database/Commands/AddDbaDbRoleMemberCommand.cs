#nullable enable

using System;
using System.Collections.Generic;
using System.Collections.Specialized;
using System.Management.Automation;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;
using SmoDatabase = Microsoft.SqlServer.Management.Smo.Database;

namespace Dataplat.Dbatools.Commands;

/// <summary>Adds database users or roles as members to database roles across SQL Server instances</summary>
[Cmdlet(VerbsCommon.Add, "DbaDbRoleMember", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High)]
public sealed class AddDbaDbRoleMemberCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(ValueFromPipeline = true, Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The database(s) to process.</summary>
    [Parameter(Position = 2)]
    [PsStringArrayCast]
    public string[]? Database { get; set; }

    /// <summary>The role(s) to add members to.</summary>
    [Parameter(Position = 3)]
    [PsStringArrayCast]
    public string[]? Role { get; set; }

    /// <summary>The user(s) or role(s) to add to the role.</summary>
    [Parameter(Mandatory = true, Position = 4)]
    [Alias("User")]
    [PsStringArrayCast]
    public string[] Member { get; set; } = null!;

    /// <summary>A server, database, or database role object to process.</summary>
    [Parameter(ValueFromPipeline = true, Position = 5)]
    public object[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    protected override void ProcessRecord()
    {
        if (!LanguagePrimitives.IsTrue(InputObject) && !LanguagePrimitives.IsTrue(SqlInstance))
        {
            StopFunction("You must pipe in a role, database, or server or specify a SqlInstance");
            return;
        }
        if (LanguagePrimitives.IsTrue(SqlInstance))
            InputObject = SqlInstance;

        foreach (object input in InputObject ?? Array.Empty<object>())
        {
            object value = input is PSObject wrapped ? wrapped.BaseObject : input;
            var roles = new List<DatabaseRole>();
            switch (value)
            {
                case DbaInstanceParameter instance:
                    WriteMessage(MessageLevel.Verbose, "Processing DbaInstanceParameter through InputObject");
                    GatherRoles(roles, NativeDatabaseSelection.GatherMatching(this, new[] { instance }, SqlCredential, Database, true, null, false,
                        server => SetActiveConnection(server.ConnectionContext), () => Stopping));
                    break;
                case Server server:
                    WriteMessage(MessageLevel.Verbose, "Processing Server through InputObject");
                    GatherRoles(roles, NativeDatabaseSelection.GatherMatching(this, new[] { new DbaInstanceParameter(server) }, SqlCredential, Database, true, null, false,
                        connected => SetActiveConnection(connected.ConnectionContext), () => Stopping));
                    break;
                case SmoDatabase database:
                    WriteMessage(MessageLevel.Verbose, "Processing Database through InputObject");
                    GatherRoles(roles, new[] { database });
                    break;
                case DatabaseRole role:
                    WriteMessage(MessageLevel.Verbose, "Processing DatabaseRole through InputObject");
                    roles.Add(role);
                    break;
                default:
                    StopFunction("InputObject is not a server, database, or database role.");
                    return;
            }
            if (!TestBound(nameof(Role)) && value is not DatabaseRole)
            {
                StopFunction("You must pipe in a DatabaseRole or specify a Role.");
                return;
            }
            foreach (DatabaseRole role in roles)
                AddMembers(role);
        }
    }

    private void GatherRoles(List<DatabaseRole> roles, IEnumerable<SmoDatabase> databases)
    {
        foreach (SmoDatabase database in databases)
        {
            if (!database.IsAccessible)
                continue;
            WriteAttributedMessage("Get-DbaDbRole", MessageLevel.Verbose,
                string.Format("Getting Database Roles for {0} on {1}", database, database.Parent));
            foreach (DatabaseRole role in database.Roles)
            {
                if (LanguagePrimitives.IsTrue(Role) && !NativeDatabaseSelection.ContainsName(Role, role.Name))
                    continue;
                PSObject output = PSObject.AsPSObject(role);
                foreach (string property in new[] { "ComputerName", "InstanceName", "SqlInstance", "Database" })
                    output.Properties.Remove(property);
                OutputHelper.AddInstanceProperties(output, database.Parent);
                output.Properties.Add(new PSNoteProperty("Database", database.Name));
                OutputHelper.SetDefaultDisplayPropertySet(output, "ComputerName", "InstanceName", "Database", "Name", "IsFixedRole");
                roles.Add(role);
            }
        }
    }

    private void AddMembers(DatabaseRole role)
    {
        SmoDatabase database = role.Parent;
        Server server = database.Parent;
        WriteMessage(MessageLevel.Verbose, string.Format("Getting Database Role Members for {0} in {1} on {2}", role, database, server));
        StringCollection members;
        try
        {
            members = role.EnumMembers();
        }
        catch (Exception exception) when (exception is not PipelineStoppedException)
        {
            // caller-try: terminate -- proceeding without the membership snapshot could repeat server changes.
            ThrowTerminatingError(MethodFault(exception, "EnumMembers", 0)); // style-ok: cs-raw-streams uncaught SMO method fault, not a Stop-Function site
            return;
        }

        var existingMembers = new List<string>();
        foreach (string? member in members)
        {
            if (member is not null)
                existingMembers.Add(member);
        }
        foreach (string member in Member)
        {
            var users = new List<string>();
            foreach (User user in database.Users)
                users.Add(user.Name);
            string? kind = NativeDatabaseSelection.ContainsName(users.ToArray(), member) ? "user" : null;
            if (kind is null)
            {
                var roleNames = new List<string>();
                foreach (DatabaseRole databaseRole in database.Roles)
                    roleNames.Add(databaseRole.Name);
                if (NativeDatabaseSelection.ContainsName(roleNames.ToArray(), member))
                    kind = "role";
            }
            if (kind is null)
            {
                WriteMessage(MessageLevel.Warning, string.Format("User or role {0} does not exist in {1} on {2}", member, database, server));
                continue;
            }
            if (NativeDatabaseSelection.ContainsName(existingMembers.ToArray(), member))
                continue;
            if (!ShouldProcess(server.ToString(), string.Format("Adding {0} {1} to role: {2} in database {3}", kind, member, role, database)))
                continue;
            WriteMessage(MessageLevel.Verbose, string.Format("Adding {0} {1} to role: {2} in database {3} on {4}", kind, member, role, database, server));
            try
            {
                role.AddMember(member);
            }
            catch (Exception exception) when (exception is not PipelineStoppedException)
            {
                // caller-try: terminate -- the source leaves AddMember outside a try and no safe continuation is established.
                ThrowTerminatingError(MethodFault(exception, "AddMember", 1)); // style-ok: cs-raw-streams preserve the uncaught SMO method fault independently of EnableException
            }
        }
    }

    private static ErrorRecord MethodFault(Exception exception, string method, int arguments)
    {
        MethodInvocationException fault = new(string.Format("Exception calling \"{0}\" with \"{1}\" argument(s): \"{2}\"", method, arguments, exception.Message), exception);
        return new ErrorRecord(fault, exception.GetType().Name, ErrorCategory.NotSpecified, null);
    }
}
