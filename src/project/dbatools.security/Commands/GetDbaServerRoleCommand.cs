#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Collections.Specialized;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;
using SmoServerRole = Microsoft.SqlServer.Management.Smo.ServerRole;

namespace Dataplat.Dbatools.Commands;

// Port of public/Get-DbaServerRole.ps1 at refs/pins/dbatools-2026-10-22: Connect-DbaInstance's steps are the shared
// ResolveConnection, and its failure reaches the pinned catch as the record Connect-DbaInstance throws (as in
// Get-DbaReplServer); the Where-Object filters and the decoration run over SMO's ServerRole objects as the pin's do.

/// <summary>
/// Retrieves server-level security roles and their members from SQL Server instances.
/// </summary>
/// <para>
/// Retrieves all server-level security roles from SQL Server instances, including role members, creation dates, and ownership details. This function helps DBAs audit server-level permissions, identify role membership for compliance reporting, and distinguish between built-in fixed roles (like sysadmin, serveradmin) and custom user-defined roles. Supports filtering to specific roles or excluding fixed roles to focus on custom security configurations.
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaServerRole -SqlInstance sql2016a
/// </code>
/// <para>
/// Outputs list of server-level roles for sql2016a instance.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaServerRole -SqlInstance sql2017a -ExcludeFixedRole
/// </code>
/// <para>
/// Outputs the server-level role(s) that are not fixed roles on sql2017a instance.
/// </para>
/// </example>
/// <list type="alertSet">
/// <item>
/// <term />
/// <description>
/// <para>
/// Tags: Role
/// Author: Shawn Melton (@wsmelton)
/// </para>
/// <para>
/// Website: https://dbatools.io
/// Copyright: (c) 2018 by dbatools, licensed under MIT
/// License: MIT https://opensource.org/licenses/MIT
/// </para>
/// </description>
/// </item>
/// <item>
/// <term>OUTPUTS</term>
/// <description>
/// <para>
/// Microsoft.SqlServer.Management.Smo.ServerRole
/// </para>
/// <para>
/// Returns one ServerRole object per server-level role on the specified SQL Server instance. For example, querying a standard SQL Server instance returns multiple objects - one for each fixed role (sysadmin, serveradmin, dbcreator, etc.) plus any custom user-defined server roles.
/// </para>
/// <para>
/// Default display properties (via Select-DefaultView):
/// - ComputerName: The computer name of the SQL Server instance
/// - InstanceName: The SQL Server instance name
/// - SqlInstance: The full SQL Server instance name (computer\instance)
/// - Role: The name of the server role (same as Name property)
/// - Login: Array of login names that are members of this role
/// - Owner: The principal that owns the server role
/// - IsFixedRole: Boolean indicating if this is a built-in fixed role (sysadmin, serveradmin, etc.) or a custom user-defined role
/// - DateCreated: DateTime when the role was created
/// - DateModified: DateTime when the role was last modified
/// </para>
/// <para>
/// Additional properties available (from SMO ServerRole object):
/// - Name: The name of the server role
/// - Urn: The Uniform Resource Name of the server role object
/// - Properties: Collection of property objects for the role
/// - State: Current state of the SMO object (Existing, Creating, Pending, etc.)
/// </para>
/// <para>
/// All properties from the base SMO ServerRole object are accessible using Select-Object * even though only default properties are displayed without using Select-Object *.
/// </para>
/// </description>
/// </item>
/// </list>
/// <seealso href="https://dbatools.io/Get-DbaServerRole" />
[Cmdlet(VerbsCommon.Get, "DbaServerRole")]
[OutputType(typeof(SmoServerRole))]
public sealed class GetDbaServerRoleCommand : DbaInstanceCmdlet
{
    private static readonly string[] DisplaySet =
        { "ComputerName", "InstanceName", "SqlInstance", "Role", "Login", "Owner", "IsFixedRole", "DateCreated", "DateModified" };

    /// <para>
    /// The target SQL Server instance or instances. Server version must be SQL Server version 2005 or higher.
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
    /// Specifies one or more server-level roles to include in the results. Accepts role names like 'sysadmin', 'dbcreator', or custom role names.
    /// Use this when you need to audit specific roles rather than retrieving all server roles from the instance.
    /// </para>
    [Parameter(Position = 2)]
    [PsStringArrayCast]
    public string[]? ServerRole { get; set; }

    /// <para>
    /// Specifies one or more server-level roles to exclude from the results. Useful for filtering out roles you don't need to audit.
    /// Commonly used to exclude built-in roles like 'public' when focusing on administrative roles with elevated permissions.
    /// </para>
    [Parameter(Position = 3)]
    [PsStringArrayCast]
    public string[]? ExcludeServerRole { get; set; }

    /// <para>
    /// Excludes built-in fixed server roles from the results, showing only custom user-defined server roles.
    /// Use this when auditing custom security configurations or identifying roles created by your organization rather than SQL Server's default roles.
    /// </para>
    [Parameter]
    public SwitchParameter ExcludeFixedRole { get; set; }

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
            if (Interrupted)
                return;

            // PS: try { $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -AzureUnsupported }
            //     catch { Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue }
            // Azure SQL Database stays refused as the pin refuses it: SMO lists its server roles through a database connection,
            // but EnumMemberNames fails there (native run 20261112T2240540292487Z, every leg), and its role membership needs
            // sys.sql_logins joined in the virtual master (Microsoft Learn, sys.server_role_members), which SMO's member read
            // does not do.
            Server server;
            WriteAttributedMessage("Connect-DbaInstance", MessageLevel.Debug, "Starting process block");
            try
            {
                server = ResolveConnection(instance, out _, azureUnsupported: true);
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch (Exception exception)
            {
                StopFunction("Failure", target: instance, errorRecord: CaughtConnectFailure(instance, exception),
                    category: ErrorCategory.ConnectionError, continueLoop: true);
                continue;
            }

            // PS: $serverroles = $server.Roles, then the three Where-Object filters; see ReadRoles.
            List<SmoServerRole>? roles = ReadRoles(server);
            if (roles is null)
                continue;

            // PS: foreach ($role in $serverRoles) { $members = $role.EnumMemberNames(); Add-Member ...; Select-DefaultView ... }
            foreach (SmoServerRole role in roles)
                WriteObject(Decorate(role, ReadMembers(role), server));
        }
    }

    // $_ in the pinned catch: Connect-DbaInstance forces its own EnableException on, so a failed connection or a refusal is its
    // Stop-Function throw; the warning is logged without display and the thrown record lands in $error. Any other failure is
    // the fault itself.
    private ErrorRecord CaughtConnectFailure(DbaInstanceParameter instance, Exception failure)
    {
        if (failure is not ConnectionResolutionException resolution)
            return new ErrorRecord(failure, failure.GetType().Name, ErrorCategory.NotSpecified, null);

        if (resolution.Kind == ConnectionResolutionFailure.ConnectFailure)
        {
            // PS: Stop-Function -Target $instance -Message "Failure" -Category ConnectionError -ErrorRecord $connectionError -Continue
            ErrorRecord connectionError = new(resolution.InnerException ?? resolution, "dbatools_Connect-DbaInstance", ErrorCategory.NotSpecified, instance);
            return CaughtNestedStopFunction("Connect-DbaInstance", "Failure", instance, connectionError, ErrorCategory.ConnectionError);
        }

        // PS: Stop-Function -Target $instance -Message "Azure SQL Database not supported" -Continue, and the other refusals
        return CaughtNestedStopFunction("Connect-DbaInstance", resolution.Message, instance);
    }

    // The pin reads $server.Roles outside any try, once in each active Where-Object and once more in its foreach. A read that
    // faults is the engine's statement fault: a plain call writes the record and goes on, a caller's try catches it,
    // -EnableException stops here. A Where-Object whose read faults leaves $serverRoles as it was, so the next read is of the
    // same collection; SMO reads it again and faults again (pin probe serverrole-pin-20261112: one record per read), and the
    // foreach's fault ends the instance.
    private List<SmoServerRole>? ReadRoles(Server server)
    {
        // PS: $serverroles = $server.Roles
        IEnumerable source = server.Roles;
        // PS: if ($ServerRole) { $serverRoles = $serverRoles | Where-Object Name -In $ServerRole }
        if (FilterHelper.IsActive(ServerRole))
            source = Filter(source, IsListed);
        // PS: if ($ExcludeServerRole) { $serverRoles = $serverRoles | Where-Object Name -NotIn $ExcludeServerRole }
        if (FilterHelper.IsActive(ExcludeServerRole))
            source = Filter(source, IsNotExcluded);
        // PS: if ($ExcludeFixedRole) { $serverRoles = $serverRoles | Where-Object IsFixedRole -eq $false }
        if (ExcludeFixedRole)
            source = Filter(source, IsNotFixedRole);

        // PS: foreach ($role in $serverRoles)
        List<SmoServerRole>? roles = Enumerate(source);
        if (roles is null)
            return null;

        // After a faulted Where-Object the pin would go on with the unfiltered roles if this read worked; every filter the
        // caller asked for applies to the roles returned. On roles already filtered this changes nothing.
        return roles.FindAll(IsKept);
    }

    private IEnumerable Filter(IEnumerable source, Predicate<SmoServerRole> keep)
    {
        List<SmoServerRole>? rows = Enumerate(source);
        if (rows is null)
            return source;
        return rows.FindAll(keep);
    }

    private bool IsKept(SmoServerRole role)
    {
        return (!FilterHelper.IsActive(ServerRole) || IsListed(role)) &&
            (!FilterHelper.IsActive(ExcludeServerRole) || IsNotExcluded(role)) &&
            (!ExcludeFixedRole || IsNotFixedRole(role));
    }

    // PS: Name -In $ServerRole and Name -NotIn $ExcludeServerRole compare case-insensitively, each listed value converted to
    // the role name's type (string).
    private bool IsListed(SmoServerRole role)
    {
        return Array.Exists(ServerRole!, name => LanguagePrimitives.Equals(role.Name, name, true, CultureInfo.InvariantCulture));
    }

    private bool IsNotExcluded(SmoServerRole role)
    {
        return !Array.Exists(ExcludeServerRole!, name => LanguagePrimitives.Equals(role.Name, name, true, CultureInfo.InvariantCulture));
    }

    // PS: Where-Object IsFixedRole -eq $false. Where-Object reads a property that throws as $null, and $null -eq $false is
    // false, so such a role is left out.
    private static bool IsNotFixedRole(SmoServerRole role)
    {
        try
        {
            return !role.IsFixedRole;
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            return false;
        }
    }

    // SMO loads the collection when it is first enumerated. The engine's record when the failure carries one
    // (ExceptionInGetEnumerator); otherwise the record a failing MoveNext gives (BadEnumeration, InvalidOperation, the
    // enumerator as target).
    private List<SmoServerRole>? Enumerate(IEnumerable collection)
    {
        List<SmoServerRole> rows = new();
        IEnumerator? enumerator = null;
        ErrorRecord fault;
        try
        {
            enumerator = LanguagePrimitives.GetEnumerator(collection);
            while (enumerator is not null && enumerator.MoveNext())
                rows.Add((SmoServerRole)enumerator.Current);
            return rows;
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            if (failure is IContainsErrorRecord container && container.ErrorRecord is not null)
            {
                fault = new ErrorRecord(container.ErrorRecord, failure);
            }
            else
            {
                RuntimeException enumeration = new(string.Format(CultureInfo.InvariantCulture,
                    "An error occurred while enumerating through a collection: {0}.", failure.Message), failure);
                fault = new ErrorRecord(enumeration, "BadEnumeration", ErrorCategory.InvalidOperation, enumerator);
            }
        }

        SurfaceFault(fault);
        return null;
    }

    // PS: $members = $role.EnumMemberNames(), outside any try. A fault is the engine's record for a .NET method that throws;
    // a plain call writes it and goes on with the role. The pin then attaches whatever $members held before (an earlier role's
    // members, or $null); the port attaches $null, so no role carries another role's members.
    private StringCollection? ReadMembers(SmoServerRole role)
    {
        ErrorRecord fault;
        try
        {
            return role.EnumMemberNames();
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            if (failure is IContainsErrorRecord container && container.ErrorRecord is not null)
            {
                fault = new ErrorRecord(container.ErrorRecord, failure);
            }
            else
            {
                MethodInvocationException invocation = new(string.Format(CultureInfo.InvariantCulture,
                    "Exception calling \"EnumMemberNames\" with \"0\" argument(s): \"{0}\"", failure.Message), failure);
                fault = new ErrorRecord(invocation, failure.GetType().Name, ErrorCategory.NotSpecified, null);
            }
        }

        SurfaceFault(fault);
        return null;
    }

    // A read in the pin's body, which has no try around it: a plain call writes it and goes on, a caller's try catches it,
    // -EnableException stops here.
    private void SurfaceFault(ErrorRecord fault)
    {
        if (EnableException.ToBool())
        {
            // caller-try: terminate -- -EnableException asks for the stop
            ThrowTerminatingError(fault); // style-ok: cs-raw-streams a read's statement fault, outside Stop-Function, as in the pin
        }

        StatementFault.Surface(this, fault);
    }

    // PS: Add-Member -Force of Login, ComputerName, InstanceName, SqlInstance, Role and ServerRole, then Select-DefaultView.
    // -Force replaces the notes an earlier call left on the same SMO object. Login keeps EnumMemberNames' StringCollection,
    // an empty one included.
    private static PSObject Decorate(SmoServerRole role, StringCollection? members, Server server)
    {
        PSObject output = PSObject.AsPSObject(role);
        foreach (string name in new[] { "Login", "ComputerName", "InstanceName", "SqlInstance", "Role", "ServerRole" })
            output.Properties.Remove(name);
        output.Properties.Add(new PSNoteProperty("Login", members));
        OutputHelper.AddInstanceProperties(output, server);
        output.Properties.Add(new PSNoteProperty("Role", role.Name));
        output.Properties.Add(new PSNoteProperty("ServerRole", role.Name));
        OutputHelper.SetDefaultDisplayPropertySet(output, DisplaySet);
        return output;
    }
}
