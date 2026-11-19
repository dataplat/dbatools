#nullable enable

using System;
using System.Collections.Generic;
using System.Collections.Specialized;
using System.Data;
using System.Globalization;
using System.Linq;
using System.Management.Automation;
using System.Text;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Migrates custom server roles and their permissions between SQL Server instances
/// </summary>
/// <para>
/// Copies user-defined server roles from the source server to one or more destination servers. This is essential when migrating SQL Server instances that use custom server roles for granular permission management, or when standardizing security configurations across multiple environments.
/// </para>
/// <para>
/// Only custom (user-defined) server roles are copied by default. Fixed server roles like sysadmin, serveradmin, etc. are built into SQL Server and cannot be created or dropped. Use -IncludeFixedRole to also synchronize memberships for fixed roles.
/// </para>
/// <para>
/// Server role permissions and memberships are migrated along with the role definition. This includes server-level permissions granted to the role (like CONNECT ANY DATABASE, VIEW ANY DATABASE) and login memberships in the role.
/// </para>
/// <para>
/// By default, existing server roles on the destination are skipped to prevent conflicts. Use -Force to drop and recreate existing roles, which will also reapply all permissions and memberships.
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Copy-DbaServerRole -Source sqlserver2014a -Destination sqlcluster
/// </code>
/// <para>
/// Copies all custom server roles from sqlserver2014a to sqlcluster using Windows credentials. If roles with the same name exist on sqlcluster, they will be skipped.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Copy-DbaServerRole -Source sqlserver2014a -SourceSqlCredential $scred -Destination sqlcluster -DestinationSqlCredential $dcred -ServerRole "CustomRole1" -Force
/// </code>
/// <para>
/// Copies only the custom server role named "CustomRole1" from sqlserver2014a to sqlcluster using SQL credentials. If the role exists on sqlcluster, it will be dropped and recreated because -Force was used.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Copy-DbaServerRole -Source sqlserver2014a -Destination sqlcluster -ExcludeServerRole "TestRole" -Force
/// </code>
/// <para>
/// Copies all custom server roles found on sqlserver2014a except "TestRole" to sqlcluster. If roles with the same name exist on sqlcluster, they will be updated because -Force was used.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Copy-DbaServerRole -Source sqlserver2014a -Destination sqlcluster -WhatIf -Force
/// </code>
/// <para>
/// Shows what would happen if the command were executed using force.
/// </para>
/// </example>
/// <list type="alertSet">
/// <item>
/// <term />
/// <description>
/// <para>
/// Tags: Migration, ServerRole, Security
/// Author: the dbatools team + Claude
/// </para>
/// <para>
/// Website: https://dbatools.io
/// Copyright: (c) 2018 by dbatools, licensed under MIT
/// License: MIT https://opensource.org/licenses/MIT
/// </para>
/// <para>
/// Requires: sysadmin access on SQL Servers, SQL Server 2012+
/// </para>
/// </description>
/// </item>
/// </list>
/// <seealso href="https://dbatools.io/Copy-DbaServerRole" />
[Cmdlet(VerbsCommon.Copy, "DbaServerRole", DefaultParameterSetName = "Default",
    SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
public sealed class CopyDbaServerRoleCommand : DbaBaseCmdlet
{
    /// <para>
    /// Source SQL Server. You must have sysadmin access and server version must be SQL Server version 2012 or higher.
    /// </para>
    [Parameter(Mandatory = true, Position = 0)]
    public DbaInstanceParameter Source { get; set; } = null!;

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
    public PSCredential? SourceSqlCredential { get; set; }

    /// <para>
    /// Destination SQL Server. You must have sysadmin access and the server must be SQL Server 2012 or higher.
    /// </para>
    [Parameter(Mandatory = true, Position = 2)]
    public DbaInstanceParameter[] Destination { get; set; } = null!;

    /// <para>
    /// Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).
    /// </para>
    /// <para>
    /// Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.
    /// </para>
    /// <para>
    /// For MFA support, please use Connect-DbaInstance.
    /// </para>
    [Parameter(Position = 3)]
    public PSCredential? DestinationSqlCredential { get; set; }

    /// <para>
    /// Specifies which server roles to migrate from the source server. Only the specified roles will be copied to the destination.
    /// Use this when you need to migrate specific custom roles rather than all of them, such as when standardizing only certain security roles across environments.
    /// </para>
    [Parameter(Position = 4)]
    public object[]? ServerRole { get; set; }

    /// <para>
    /// Specifies which server roles to skip during migration. All custom server roles except the excluded ones will be copied.
    /// Use this when you want to migrate most roles but exclude problematic ones, or when certain roles are environment-specific and shouldn't be copied.
    /// </para>
    [Parameter(Position = 5)]
    public object[]? ExcludeServerRole { get; set; }

    /// <para>
    /// Drops and recreates existing custom server roles on the destination server, reapplying all permissions and memberships from the source.
    /// Use this when you need to update server role permissions that have changed on the source, or when synchronizing role definitions across environments.
    /// </para>
    [Parameter]
    public SwitchParameter Force { get; set; }

    /// <para>
    /// By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
    /// This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
    /// Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.
    /// </para>
    [Parameter]
    public override SwitchParameter EnableException { get; set; }

    private const string CommandName = "Copy-DbaServerRole";

    // The server rows the nested Get-DbaPermission -IncludeServerLevel call returned to the pinned function (:199-203), in
    // the form native Get-DbaPermission writes them (GetDbaPermissionCommand.Queries.cs, ServerPermissionSql, with its
    // recorded corrections to the statement's state, scope and quoting). Its second branch, the fixed roles' built-in
    // permissions, has empty statements that the pinned loop skips, and no custom role carries a fixed role's name.
    // Correction server-scope-permissions: no database permission rows (see ProcessRecord).
    private const string RolePermissionSql = @"SELECT [Grantee] = SUSER_NAME(perm.grantee_principal_id),
    [GrantStatement] = CASE perm.state_desc WHEN 'GRANT_WITH_GRANT_OPTION' THEN 'GRANT' ELSE perm.state_desc END + ' ' + perm.permission_name + scope.Clause
        + CASE perm.state_desc WHEN 'REVOKE' THEN ' FROM ' ELSE ' TO ' END + QUOTENAME(SUSER_NAME(perm.grantee_principal_id))
        + CASE perm.state_desc WHEN 'GRANT_WITH_GRANT_OPTION' THEN ' WITH GRANT OPTION' ELSE '' END
FROM sys.server_permissions AS perm
    INNER JOIN sys.server_principals AS grantee ON grantee.principal_id = perm.grantee_principal_id
    LEFT OUTER JOIN sys.server_principals AS target ON perm.class = 101 AND target.principal_id = perm.major_id
    CROSS APPLY (SELECT CASE perm.class
        WHEN 101 THEN ' ON ' + CASE WHEN target.type = 'R' THEN 'SERVER ROLE::' ELSE 'LOGIN::' END + QUOTENAME(target.name)
        WHEN 105 THEN ' ON ENDPOINT::' + (SELECT TOP (1) QUOTENAME(ep.name) FROM sys.endpoints AS ep WHERE ep.endpoint_id = perm.major_id)
        WHEN 108 THEN ' ON AVAILABILITY GROUP::' + (SELECT TOP (1) QUOTENAME(ag.name) FROM sys.availability_replicas AS ar INNER JOIN sys.availability_groups AS ag ON ag.group_id = ar.group_id WHERE ar.replica_metadata_id = perm.major_id)
        ELSE ' ' + COALESCE(QUOTENAME(OBJECT_NAME(perm.major_id)), '')
        END COLLATE DATABASE_DEFAULT AS Clause) AS scope;";

    private Server? _sourceServer;
    private readonly List<ServerRole> _sourceRoles = new List<ServerRole>();

    protected override void BeginProcessing()
    {
        // PS: try { Connect-DbaInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential -MinimumVersion 11 }
        //     catch { Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $Source; return }
        _sourceServer = Connect(Source, SourceSqlCredential, false);
        if (_sourceServer is null)
            return;

        // PS: $sourceRoles = $sourceServer.Roles | Where-Object { $PSItem.IsFixedRole -eq $false -and $PSItem.Name -ne "public" }
        foreach (ServerRole role in _sourceServer.Roles)
        {
            if (!role.IsFixedRole && !LanguagePrimitives.Equals(role.Name, "public", true, CultureInfo.InvariantCulture))
                _sourceRoles.Add(role);
        }
    }

    protected override void ProcessRecord()
    {
        // PS: if (Test-FunctionInterrupt) { return }
        if (Interrupted || _sourceServer is null)
            return;

        foreach (DbaInstanceParameter destinstance in Destination)
        {
            CancellationToken.ThrowIfCancellationRequested();
            Server? destServer = Connect(destinstance, DestinationSqlCredential, true);
            if (destServer is null)
                continue;

            ServerRoleCollection destRoles = destServer.Roles;

            foreach (ServerRole currentRole in _sourceRoles)
            {
                CancellationToken.ThrowIfCancellationRequested();
                string roleName = currentRole.Name;
                // PS: [DbaDateTime](Get-Date), taken when the status object is built, before the filters.
                DateTime timestamp = DateTime.Now;

                // PS: if ($ServerRole -and ($roleName -notin $ServerRole)) { continue }
                if (LanguagePrimitives.IsTrue(ServerRole) && !ContainsValue(ServerRole, roleName))
                    continue;

                // PS: if ($ExcludeServerRole -and ($roleName -in $ExcludeServerRole)) { continue }
                if (LanguagePrimitives.IsTrue(ExcludeServerRole) && ContainsValue(ExcludeServerRole, roleName))
                    continue;

                // PS: if ($destRoles.Name -contains $roleName)
                if (ContainsValue(destRoles.Cast<ServerRole>().Select(role => (object?)role.Name), roleName))
                {
                    if (!Force)
                    {
                        if (Approve(destinstance, string.Format("Server role {0} exists at destination. Use -Force to drop and migrate.", roleName)))
                        {
                            Emit(destServer, roleName, timestamp, "Skipped", "Already exists on destination");
                            WriteMessage(MessageLevel.Verbose, string.Format("Server role {0} exists at destination. Use -Force to drop and migrate.", roleName));
                        }
                        continue;
                    }
                    if (Approve(destinstance, string.Format("Dropping server role {0} and recreating", roleName)))
                    {
                        try
                        {
                            WriteMessage(MessageLevel.Verbose, string.Format("Dropping server role {0}", roleName));
                            DropExisting(destServer, roleName);
                        }
                        catch (PipelineStoppedException) { throw; }
                        catch (Exception ex)
                        {
                            Emit(destServer, roleName, timestamp, "Failed", ex.Message);
                            WriteMessage(MessageLevel.Verbose, string.Format("Issue dropping server role {0} on {1} | {2}", roleName, destinstance, ex.Message));
                            continue;
                        }
                    }
                }

                if (Approve(destinstance, string.Format("Creating server role {0}", roleName)))
                {
                    try
                    {
                        WriteMessage(MessageLevel.Verbose, string.Format("Copying server role {0}", roleName));
                        // PS: $sql = $currentRole.Script() | Out-String: every scripted line followed by a newline.
                        StringCollection script = Call(() => currentRole.Script(), "Script", 0);
                        StringBuilder text = new StringBuilder();
                        foreach (string? line in script)
                            text.Append(line).Append(Environment.NewLine);
                        string sql = text.ToString();
                        WriteMessage(MessageLevel.Debug, sql);
                        Query(destServer, sql);
                        Call(() => destServer.Roles.Refresh(), "Refresh", 0);

                        foreach (string permSql in ReadGrantStatements(roleName))
                        {
                            try
                            {
                                WriteMessage(MessageLevel.Debug, string.Format("Granting permission: {0}", permSql));
                                Query(destServer, permSql);
                            }
                            catch (PipelineStoppedException) { throw; }
                            catch (Exception ex)
                            {
                                WriteMessage(MessageLevel.Warning, string.Format("Could not grant permission for role {0} on {1} | {2}", roleName, destinstance, ex.Message));
                            }
                        }

                        StringCollection members = Call(() => currentRole.EnumMemberNames(), "EnumMemberNames", 0);
                        foreach (string? member in members)
                        {
                            // PS: if ($destServer.Logins.Name -contains $member)
                            if (ContainsValue(destServer.Logins.Cast<Login>().Select(login => (object?)login.Name), member))
                            {
                                try
                                {
                                    WriteMessage(MessageLevel.Verbose, string.Format("Adding login {0} to role {1}", member, roleName));
                                    ServerRole? created = destServer.Roles[roleName];
                                    if (created is null)
                                        throw new RuntimeException("You cannot call a method on a null-valued expression.");
                                    Call(() => created.AddMember(member!), "AddMember", 1);
                                }
                                catch (PipelineStoppedException) { throw; }
                                catch (Exception ex)
                                {
                                    WriteMessage(MessageLevel.Warning, string.Format("Could not add member {0} to role {1} on {2} | {3}", member, roleName, destinstance, ex.Message));
                                }
                            }
                            else
                            {
                                WriteMessage(MessageLevel.Verbose, string.Format("Login {0} does not exist on destination, skipping membership", member));
                            }
                        }

                        Emit(destServer, roleName, timestamp, "Successful", null);
                    }
                    catch (PipelineStoppedException) { throw; }
                    catch (Exception ex)
                    {
                        Emit(destServer, roleName, timestamp, "Failed", ex.Message);
                        WriteMessage(MessageLevel.Verbose, string.Format("Issue creating server role {0} on {1} | {2}", roleName, destinstance, ex.Message));
                    }
                }
            }
        }
    }

    // PS: $destServer.Roles[$roleName].Drop(); $destServer.Roles.Refresh()
    // SMO's ServerRole.Drop() removes the role's members itself, so a destination role that has members is dropped and
    // recreated as -Force documents; members the source role lacks are not members of the recreated role (item probes
    // serverrole-stage-proof-20261117 and serverrole-pin-force-20261117, pin and port alike).
    private static void DropExisting(Server destServer, string roleName)
    {
        ServerRole? existing = destServer.Roles[roleName];
        if (existing is null)
            throw new RuntimeException("You cannot call a method on a null-valued expression.");
        Call(() => existing.Drop(), "Drop", 0);
        Call(() => destServer.Roles.Refresh(), "Refresh", 0);
    }

    // PS: Get-DbaPermission -SqlInstance $sourceServer -IncludeServerLevel | Where-Object Grantee -eq $roleName, then
    //     each row's GrantStatement when it is not empty.
    // Correction server-scope-permissions: the pinned call also returned every database's permission rows, whose Grantee is
    // the database principal's name, and replayed those of any database principal named like the role on the destination
    // in the connection's database. Only the server permissions granted to the server role are replayed.
    private List<string> ReadGrantStatements(string roleName)
    {
        List<string> statements = new List<string>();
        DataSet data = _sourceServer!.ConnectionContext.ExecuteWithResults(RolePermissionSql);
        if (data.Tables.Count == 0)
            return statements;
        foreach (DataRow row in data.Tables[0].Rows)
        {
            if (!LanguagePrimitives.Equals(row["Grantee"], roleName, true, CultureInfo.InvariantCulture))
                continue;
            if (row["GrantStatement"] is string statement && statement.Length > 0)
                statements.Add(statement);
        }
        return statements;
    }

    // PS: Connect-DbaInstance -SqlInstance <instance> -SqlCredential <credential> -MinimumVersion 11 (:122, :136), whose
    // failure the pinned catch hands to Stop-Function -Message "Failure" -Category ConnectionError (-Continue for a destination).
    private Server? Connect(DbaInstanceParameter instance, PSCredential? credential, bool continueLoop)
    {
        const string connectCommand = "Connect-DbaInstance";
        WriteAttributedMessage(connectCommand, MessageLevel.Debug, "Starting process block");
        Server server;
        try
        {
            server = ConnectionService.GetServer(ConnectRequest(instance, credential));
        }
        catch (PipelineStoppedException) { throw; }
        catch (Exception ex)
        {
            StopFunction("Failure", target: instance, category: ErrorCategory.ConnectionError, continueLoop: continueLoop,
                errorRecord: new ErrorRecord(ex, "dbatools_" + CommandName, ErrorCategory.ConnectionError, instance));
            return null;
        }
        SetActiveConnection(server.ConnectionContext);
        WriteAttributedMessage(connectCommand, MessageLevel.Debug, "We are finished with this instance");
        return server;
    }

    private SmoConnectionRequest ConnectRequest(DbaInstanceParameter instance, PSCredential? credential)
    {
        HashSet<string> bound = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "SqlInstance", "SqlCredential", "MinimumVersion", "AzureUnsupported" };
        return new SmoConnectionRequest
        {
            Instance = instance,
            SqlCredential = credential,
            MinimumVersion = 11,
            // Correction azure-unsupported: Azure SQL Database has no user-defined server roles, so both ends refuse it
            // as Connect-DbaInstance -AzureUnsupported does.
            AzureUnsupported = true,
            BoundParameters = bound,
            MessageCallback = (level, message) => WriteAttributedMessage("Connect-DbaInstance", level, message)
        };
    }

    // PS: if ($Force) { $ConfirmPreference = "none" } in begin, so -Force answers every ShouldProcess without a prompt.
    private bool Approve(DbaInstanceParameter target, string action)
    {
        return Force ? NativeConfirmation.WithConfirmationSuppressed(SessionState, () => ShouldProcess(target.ToString(), action))
            : ShouldProcess(target.ToString(), action);
    }

    // PS: $name -in $values, and $values -contains $name: each value is the left operand of a case-insensitive -eq.
    private static bool ContainsValue(IEnumerable<object?>? values, string? name)
    {
        return values is not null && values.Any(value => value is not null && LanguagePrimitives.Equals(value, name, true, CultureInfo.InvariantCulture));
    }

    // A .NET method called from PowerShell fails as MethodInvocationException around the original exception; a fault the
    // engine already raised as a RuntimeException (the null-call above) passes unchanged.
    private static T Call<T>(Func<T> call, string method, int arguments)
    {
        try { return call(); }
        catch (Exception ex) when (ex is not RuntimeException)
        {
            throw Invocation(method, arguments, ex.Message, ex);
        }
    }

    private static void Call(Action call, string method, int arguments)
    {
        Call<bool>(() => { call(); return true; }, method, arguments);
    }

    private static MethodInvocationException Invocation(string method, int arguments, string message, Exception inner)
    {
        return new MethodInvocationException(string.Format(CultureInfo.InvariantCulture,
            "Exception calling \"{0}\" with \"{1}\" argument(s): \"{2}\"", method, arguments, message), inner);
    }

    // PS: $null = $destServer.Query($sql). The Server.Query script method (xml/dbatools.Types.ps1xml) runs
    // ConnectionContext.ExecuteWithResults and on failure throws the messages of the exception chain, concatenated
    // (an empty text halts as ScriptHalted); the call site then sees a MethodInvocationException around it.
    private static void Query(Server server, string query)
    {
        Exception? failure = null;
        try { server.ConnectionContext.ExecuteWithResults(query); }
        catch (Exception ex) when (ex is not PipelineStoppedException) { failure = ex; }
        if (failure is null)
            return;
        StringBuilder chain = new StringBuilder();
        for (Exception? link = failure; link is not null; link = link.InnerException)
            chain.Append(link.Message);
        string text = chain.Length > 0 ? chain.ToString() : "ScriptHalted";
        throw Invocation("Query", 1, text, new RuntimeException(text));
    }

    // PS: [PSCustomObject]@{ ... } | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
    private void Emit(Server destServer, string name, DateTime timestamp, string status, string? notes)
    {
        PSObject result = new PSObject();
        result.Properties.Add(new PSNoteProperty("SourceServer", _sourceServer!.Name));
        result.Properties.Add(new PSNoteProperty("DestinationServer", destServer.Name));
        result.Properties.Add(new PSNoteProperty("Type", "Server Role"));
        result.Properties.Add(new PSNoteProperty("Name", name));
        result.Properties.Add(new PSNoteProperty("Status", status));
        result.Properties.Add(new PSNoteProperty("Notes", notes));
        result.Properties.Add(new PSNoteProperty("DateTime", new DbaDateTime(timestamp)));
        OutputHelper.InsertTypeName(result, "MigrationObject");
        OutputHelper.SetDefaultDisplayPropertySet(result, "DateTime", "SourceServer", "DestinationServer", "Name", "Type", "Status", "Notes");
        WriteObject(result);
    }
}
