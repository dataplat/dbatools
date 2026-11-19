#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Collections.Specialized;
using System.Data;
using System.Globalization;
using System.Management.Automation;
using System.Text;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;
using SmoLogin = Microsoft.SqlServer.Management.Smo.Login;
using SmoServerRole = Microsoft.SqlServer.Management.Smo.ServerRole;

namespace Dataplat.Dbatools.Commands;

// Port of public/Get-DbaServerRoleMember.ps1 at refs/pins/dbatools-2026-10-22. Connect-DbaInstance's steps are the shared
// ResolveConnection, and its failure reaches the pinned catch as the record Connect-DbaInstance throws (as in Get-DbaServerRole).
// The pin's nested Get-DbaLogin -SqlInstance $server -Login $Login -EnableException is absorbed as GatherLogins: the part of
// Get-DbaLogin that call runs (its Connect-DbaInstance of the same Server, its -Login filter, its login-time read and the
// decoration it leaves on each SMO login), whose first fault reaches the pinned catch as $_.

/// <summary>
/// Retrieves server-level role memberships for security auditing and compliance reporting.
/// </summary>
/// <para>
/// Returns detailed information about which logins are members of server-level roles like sysadmin, dbcreator, and securityadmin. Essential for security audits, compliance reviews, and troubleshooting permission issues. Shows both the role assignments and provides access to the underlying SMO objects for further analysis. Supports filtering by specific roles or logins to focus on particular security concerns.
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaServerRoleMember -SqlInstance localhost
/// </code>
/// <para>
/// Returns all members of all server roles on the local default SQL Server instance
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaServerRoleMember -SqlInstance localhost, sql2016
/// </code>
/// <para>
/// Returns all members of all server roles on the local and sql2016 SQL Server instances
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; $servers = Get-Content C:\servers.txt
/// PS C:\&gt; $servers | Get-DbaServerRoleMember
/// </code>
/// <para>
/// Returns all members of all server roles for every server in C:\servers.txt
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaServerRoleMember -SqlInstance localhost -ServerRole 'sysadmin', 'dbcreator'
/// </code>
/// <para>
/// Returns all members of the sysadmin or dbcreator roles on localhost.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaServerRoleMember -SqlInstance localhost -ExcludeServerRole 'sysadmin'
/// </code>
/// <para>
/// Returns all members of server-level roles other than sysadmin.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaServerRoleMember -SqlInstance sql2017a -ExcludeFixedRole
/// </code>
/// <para>
/// Returns all members of server-level role(s) that are not fixed roles on sql2017a instance.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaServerRoleMember -SqlInstance localhost -Login 'MyFriendlyDeveloper'
/// </code>
/// <para>
/// Returns all server-level role(s) for the MyFriendlyDeveloper login on localhost.
/// </para>
/// </example>
/// <list type="alertSet">
/// <item>
/// <term />
/// <description>
/// <para>
/// Tags: Role, Login
/// Author: Klaas Vandenberghe (@PowerDBAKlaas)
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
/// PSCustomObject
/// </para>
/// <para>
/// Returns one object per login that is a member of server-level roles on the specified SQL Server instance(s). For example, if the sysadmin role has three member logins and the dbcreator role has two member logins, four objects are returned total (one for each unique role-login combination when filtering by -Login parameter, or multiple objects per member if they belong to multiple roles).
/// </para>
/// <para>
/// Properties:
/// - ComputerName: The name of the computer hosting the SQL Server instance
/// - InstanceName: The SQL Server instance name
/// - SqlInstance: The full SQL Server instance name (computer\instance format)
/// - Role: The name of the server role (sysadmin, dbcreator, securityadmin, or custom role name)
/// - Name: The login name that is a member of the role
/// - SmoRole: The SMO ServerRole object representing the role - allows access to all ServerRole properties and methods for further analysis
/// - SmoLogin: The SMO Login object representing the login - allows access to all Login properties and methods for further analysis
/// </para>
/// <para>
/// Output quantity note:
/// When a login is a member of multiple roles, one object is returned per role-login combination. For example, if 'sa' is a member of both sysadmin and securityadmin roles, two objects are returned - one for each role membership.
/// </para>
/// </description>
/// </item>
/// </list>
/// <seealso href="https://dbatools.io/Get-DbaServerRoleMember" />
[Cmdlet(VerbsCommon.Get, "DbaServerRoleMember")]
[OutputType(typeof(PSCustomObject))]
public sealed class GetDbaServerRoleMemberCommand : DbaInstanceCmdlet
{
    // The nested Get-DbaLogin's begin-block query and its Select-DefaultView.
    private const string LoginTimeSql = "SELECT login_name, MAX(login_time) AS login_time FROM sys.dm_exec_sessions GROUP BY login_name";

    private static readonly string[] LoginView =
        { "ComputerName", "InstanceName", "SqlInstance", "Name", "LoginType", "CreateDate", "LastLogin", "HasAccess", "IsLocked", "IsDisabled", "MustChangePassword" };

    /// <para>
    /// The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.
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
    [Alias("Credential")]
    public override PSCredential? SqlCredential { get; set; }

    /// <para>
    /// Specifies which server roles to check for membership. Accepts role names like 'sysadmin', 'dbcreator', 'securityadmin', or custom server roles.
    /// Use this when you need to focus your audit on specific high-privilege roles or investigate particular security concerns.
    /// </para>
    [Parameter(Position = 2)]
    [PsStringArrayCast]
    public string[]? ServerRole { get; set; }

    /// <para>
    /// Excludes specified server roles from the membership report. Useful when you want to see all role memberships except certain roles.
    /// Commonly used to exclude low-privilege roles like 'public' when focusing on elevated permissions during security reviews.
    /// </para>
    [Parameter(Position = 3)]
    [PsStringArrayCast]
    public string[]? ExcludeServerRole { get; set; }

    /// <para>
    /// Filters results to show only server role memberships for specific logins. Accepts login names including Windows accounts, SQL logins, and service accounts.
    /// Use this when investigating permissions for particular users or troubleshooting access issues for specific accounts.
    /// </para>
    [Parameter(Position = 4)]
    public object[]? Login { get; set; }

    /// <para>
    /// Excludes built-in server roles like sysadmin, securityadmin, and dbcreator, showing only custom server roles created by your organization.
    /// Only available on SQL Server 2017 and later which supports user-defined server roles. Use this to audit custom role assignments in environments with specialized security models.
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

    // PS: $logins lives in the process block's one function scope, so a Get-DbaLogin call that fails keeps the logins an earlier
    // instance or pipeline record read; the pin then filters by them. Every row that filter yields is a role member the current
    // instance itself reports (its EnumMemberNames and its own Logins), so the pin's state is kept as it is.
    private List<SmoLogin>? _logins;

    protected override void ProcessRecord()
    {
        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            if (Interrupted)
                return;

            // PS: try { $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential }
            //     catch { Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue }
            // Correction azure-refusal: Azure SQL Database is refused as Connect-DbaInstance -AzureUnsupported refuses it. SMO
            // lists its server roles through a database connection but fails in EnumMemberNames on every role (Get-DbaServerRole's
            // native run 20261112T2240540292487Z, every leg), and the nested Get-DbaLogin refuses it; role membership there must be
            // read in the virtual master with sys.sql_logins joined (Microsoft Learn, sys.server_role_members).
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
                StopFunction("Failure", target: instance, errorRecord: CaughtConnectFailure("Connect-DbaInstance", instance, exception),
                    category: ErrorCategory.ConnectionError, continueLoop: true);
                continue;
            }

            // PS: $roles = $server.Roles, read when a filter or the foreach enumerates it.
            IEnumerable roles = server.Roles;

            if (TestBound(nameof(Login)))
            {
                // PS: try { $logins = Get-DbaLogin -SqlInstance $server -Login $Login -EnableException }
                //     catch { Stop-Function -Message "Issue gathering login details" -ErrorRecord $_ -Target $instance }
                try
                {
                    _logins = GatherLogins(server);
                }
                catch (CaughtFault fault)
                {
                    // No -Continue and no return: the pin warns and goes on with $logins as it was. Nothing in the pin reads the
                    // stop flag this Stop-Function sets, so it stops nothing here either.
                    StopFunction("Issue gathering login details", target: instance, errorRecord: fault.Record, interruptCallerScope: false);
                }

                WriteMessage(MessageLevel.Verbose, "Filtering by logins: " + JoinText(_logins));

                // PS: foreach ($l in $logins) { $loginRoles += $l.ListMembers() }; a fault leaves $loginRoles as it was.
                List<string> loginRoles = new();
                foreach (SmoLogin login in _logins ?? new List<SmoLogin>())
                {
                    StringCollection? memberOf = InvokeRead("ListMembers", login.ListMembers);
                    if (memberOf is null)
                        continue;
                    foreach (string? roleName in memberOf)
                        loginRoles.Add(roleName!);
                }

                // PS: $loginRoles | Select-Object -Unique, which compares case-sensitively and keeps the first of each.
                List<string> uniqueRoles = new();
                foreach (string roleName in loginRoles)
                {
                    if (!uniqueRoles.Contains(roleName))
                        uniqueRoles.Add(roleName);
                }
                WriteMessage(MessageLevel.Verbose, "Filtering by roles: " + String.Join(", ", uniqueRoles));

                // PS: $roles = $roles | Where-Object { $_.Name -in $loginRoles }
                string[] loginRoleNames = uniqueRoles.ToArray();
                roles = Filter(roles, role => IsIn(role.Name, loginRoleNames));
            }

            // PS: if (Test-Bound -ParameterName 'ServerRole') { $roles = $roles | Where-Object { $_.Name -in $ServerRole } }
            if (TestBound(nameof(ServerRole)))
                roles = Filter(roles, role => IsIn(role.Name, ServerRole));

            // PS: if (Test-Bound -ParameterName 'ExcludeServerRole') { $roles = $roles | Where-Object { $_.Name -notin $ExcludeServerRole } }
            if (TestBound(nameof(ExcludeServerRole)))
                roles = Filter(roles, role => !IsIn(role.Name, ExcludeServerRole));

            // PS: if (Test-Bound -ParameterName 'ExcludeFixedRole') { $roles = $roles | Where-Object { $_.IsFixedRole -eq $false } }
            if (TestBound(nameof(ExcludeFixedRole)))
                roles = Filter(roles, IsNotFixedRole);

            // PS: foreach ($role in $roles): a read that faults ends the statement, and the instance with it.
            List<SmoServerRole>? kept = Enumerate(roles);
            if (kept is null)
                continue;

            foreach (SmoServerRole role in kept)
                WriteMembers(server, instance, role);
        }
    }

    private void WriteMembers(Server server, DbaInstanceParameter instance, SmoServerRole role)
    {
        WriteMessage(MessageLevel.Verbose, String.Format(CultureInfo.InvariantCulture, "Getting Server Role Members for {0} on {1}", role, instance));

        // PS: $members = $role.EnumMemberNames(), outside any try. Correction stale-member-list: after a fault the pin keeps
        // $members from before, the list of the role read earlier (of this or an earlier instance), and reports those members as
        // this role's; here the role whose members cannot be read has no rows.
        List<string> members = new();
        StringCollection? names = InvokeRead("EnumMemberNames", role.EnumMemberNames);
        if (names is not null)
        {
            foreach (string? name in names)
                members.Add(name!);
        }
        WriteMessage(MessageLevel.Verbose, String.Format(CultureInfo.InvariantCulture, "{0} members: {1}", role, String.Join(", ", members)));

        if (TestBound(nameof(Login)))
        {
            // PS: $logins.Name, then $members = $members | Where-Object { $_ -in $logins.Name }
            List<string> loginNames = new();
            foreach (SmoLogin login in _logins ?? new List<SmoLogin>())
                loginNames.Add(login.Name);
            WriteMessage(MessageLevel.Verbose, "Only returning results for " + String.Join(", ", loginNames));
            string[] wanted = loginNames.ToArray();
            members = members.FindAll(member => IsIn(member, wanted));
        }

        foreach (string member in members)
        {
            // PS: $loginList = $server.Logins | Where-Object { $_.Name -eq $member }. Correction stale-login-list: after a faulted
            // read the pin keeps $loginList from before, the login of an earlier instance or member, and reports it as this
            // member's row; here the member whose login cannot be read has no row.
            List<SmoLogin>? found = FindLogins(server, member);
            if (found is null || found.Count == 0)
                continue;

            // PS: [PSCustomObject]@{ ComputerName; InstanceName; SqlInstance; Role; Name = $loginList.Name; SmoRole; SmoLogin = $loginList }
            PSObject output = new();
            OutputHelper.AddInstanceProperties(output, server);
            output.Properties.Add(new PSNoteProperty("Role", role.Name));
            if (found.Count == 1)
            {
                output.Properties.Add(new PSNoteProperty("Name", found[0].Name));
                output.Properties.Add(new PSNoteProperty("SmoRole", role));
                output.Properties.Add(new PSNoteProperty("SmoLogin", found[0]));
            }
            else
            {
                // PS: several logins whose names -eq treats as one (a case-sensitive collation) are an object[] each.
                object[] loginNames = new object[found.Count];
                object[] loginObjects = new object[found.Count];
                for (int n = 0; n < found.Count; n++)
                {
                    loginNames[n] = found[n].Name;
                    loginObjects[n] = found[n];
                }
                output.Properties.Add(new PSNoteProperty("Name", loginNames));
                output.Properties.Add(new PSNoteProperty("SmoRole", role));
                output.Properties.Add(new PSNoteProperty("SmoLogin", loginObjects));
            }
            WriteObject(output);
        }
    }

    private List<SmoLogin>? FindLogins(Server server, string member)
    {
        List<SmoLogin>? logins = Enumerate<SmoLogin>(server.Logins);
        return logins?.FindAll(login => LanguagePrimitives.Equals(login.Name, member, true, CultureInfo.InvariantCulture));
    }

    // The absorbed Get-DbaLogin -SqlInstance $server -Login $Login -EnableException. Its first fault leaves it; the caller's try
    // catches it as $_.
    private List<SmoLogin>? GatherLogins(Server server)
    {
        // PS (Get-DbaLogin): try { $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -AzureUnsupported }
        //     catch { Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue }
        // $instance is the Server itself and $SqlCredential is not given; under -EnableException that Stop-Function throws.
        DbaInstanceParameter loginInstance = new(server);
        Server loginServer;
        WriteAttributedMessage("Connect-DbaInstance", MessageLevel.Debug, "Starting process block");
        try
        {
            loginServer = ConnectionService.GetServer(new SmoConnectionRequest
            {
                Instance = loginInstance,
                SqlCredential = null,
                AzureUnsupported = true,
                BoundParameters = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "SqlInstance", "SqlCredential", "AzureUnsupported" },
                MessageCallback = (level, message) => WriteAttributedMessage("Connect-DbaInstance", level, message)
            });
            WriteAttributedMessage("Connect-DbaInstance", MessageLevel.Debug, "We are finished with this instance");
        }
        catch (PipelineStoppedException)
        {
            throw;
        }
        catch (Exception exception)
        {
            ErrorRecord connectRecord = CaughtConnectFailure("Connect-DbaInstance", loginInstance, exception);
            throw new CaughtFault(CaughtNestedStopFunction("Get-DbaLogin", "Failure", loginInstance, connectRecord, ErrorCategory.ConnectionError));
        }

        // PS: $serverLogins = $server.Logins; if ($Login) { $serverLogins = $serverLogins | Where-Object Name -in $Login }, with
        // Login bound to Get-DbaLogin's [string[]].
        string[]? names = Login is null ? null : LanguagePrimitives.ConvertTo<string[]>(Login);
        IEnumerable serverLogins = loginServer.Logins;
        if (FilterHelper.IsActive(names))
            serverLogins = EnumerateOrThrow<SmoLogin>(serverLogins).FindAll(login => IsIn(login.Name, names));

        // PS: if ($server.VersionMajor -gt 9) { $loginTimes = $server.ConnectionContext.ExecuteWithResults($loginTimeSql).Tables[0] },
        // which every supported instance is.
        WriteAttributedMessage("Get-DbaLogin", MessageLevel.Verbose, "Getting last login times");
        DataTable loginTimes;
        try
        {
            loginTimes = loginServer.ConnectionContext.ExecuteWithResults(LoginTimeSql).Tables[0];
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            throw new CaughtFault(MethodFaultRecord("ExecuteWithResults", 1, failure));
        }

        // PS: foreach ($serverLogin in $serverLogins) { Add-Member -Force ...; Select-DefaultView ... }
        List<SmoLogin> selected = EnumerateOrThrow<SmoLogin>(serverLogins);
        foreach (SmoLogin login in selected)
        {
            WriteAttributedMessage("Get-DbaLogin", MessageLevel.Verbose, String.Format(CultureInfo.InvariantCulture, "Processing {0} on {1}", login, loginInstance));
            DecorateLogin(loginServer, login, loginTimes);
        }

        // PS: $logins = Get-DbaLogin ...: no output assigns $null.
        return selected.Count == 0 ? null : selected;
    }

    // PS (Get-DbaLogin): the Add-Member -Force notes on the SMO login, then Select-DefaultView. They stay on the login object, so
    // the SmoLogin of this command's rows carries them, as in the pin.
    private static void DecorateLogin(Server server, SmoLogin login, DataTable loginTimes)
    {
        PSObject decorated = PSObject.AsPSObject(login);
        SetNote(decorated, "ComputerName", SmoServerExtensions.GetComputerName(server));
        SetNote(decorated, "InstanceName", server.ServiceName);
        SetNote(decorated, "SqlInstance", SmoServerExtensions.GetDomainInstanceName(server));
        SetNote(decorated, "LastLogin", LastLogin(loginTimes, login.Name));

        // PS: '0x' then '{0:X2}' -f each byte of $serverLogin.Sid.
        StringBuilder sid = new("0x");
        byte[]? sidBytes = login.Sid;
        if (sidBytes is not null)
        {
            foreach (byte element in sidBytes)
                sid.Append(element.ToString("X2", CultureInfo.InvariantCulture));
        }
        SetNote(decorated, "SidString", sid.ToString());
        OutputHelper.SetDefaultDisplayPropertySet(decorated, LoginView);
    }

    // PS: $loginTimes | Where-Object { $_.login_name -eq $serverLogin.name } | Select-Object -ExpandProperty login_time: nothing,
    // one time, or every matching time as an array.
    private static object? LastLogin(DataTable loginTimes, string name)
    {
        List<object> times = new();
        foreach (DataRow row in loginTimes.Rows)
        {
            if (LanguagePrimitives.Equals(row["login_name"], name, true, CultureInfo.InvariantCulture))
                times.Add(row["login_time"]);
        }
        if (times.Count == 0)
            return null;
        return times.Count == 1 ? times[0] : times.ToArray();
    }

    private static void SetNote(PSObject target, string name, object? value)
    {
        target.Properties.Remove(name);
        target.Properties.Add(new PSNoteProperty(name, value));
    }

    // $_ in a pinned catch around a dbatools command that connects: Connect-DbaInstance forces its own EnableException on, so a
    // failed connection or a refusal is its Stop-Function throw. Any other failure is the fault itself.
    private ErrorRecord CaughtConnectFailure(string functionName, DbaInstanceParameter instance, Exception failure)
    {
        if (failure is not ConnectionResolutionException resolution)
            return new ErrorRecord(failure, failure.GetType().Name, ErrorCategory.NotSpecified, null);

        if (resolution.Kind == ConnectionResolutionFailure.ConnectFailure)
        {
            // PS: Stop-Function -Target $instance -Message "Failure" -Category ConnectionError -ErrorRecord $connectionError -Continue
            ErrorRecord connectionError = new(resolution.InnerException ?? resolution, "dbatools_Connect-DbaInstance", ErrorCategory.NotSpecified, instance);
            return CaughtNestedStopFunction(functionName, "Failure", instance, connectionError, ErrorCategory.ConnectionError);
        }

        // PS: Stop-Function -Target $instance -Message "Azure SQL Database not supported" -Continue, and the other refusals
        return CaughtNestedStopFunction(functionName, resolution.Message, instance);
    }

    // A Where-Object over $roles. A read of the SMO collection that faults is the engine's statement fault and leaves $roles as it
    // was, so the next step reads the collection again. The port then applies every filter the caller asked for to the roles it
    // returns, so a later read that works never returns roles a filter left out.
    private IEnumerable Filter(IEnumerable source, Predicate<SmoServerRole> keep)
    {
        List<SmoServerRole>? rows = Enumerate(source);
        if (rows is null)
            return new FaultedRoles(source, keep);
        return rows.FindAll(keep);
    }

    private List<SmoServerRole>? Enumerate(IEnumerable source)
    {
        if (source is FaultedRoles faulted)
        {
            List<SmoServerRole>? again = Enumerate(faulted.Source);
            return again?.FindAll(faulted.Keep);
        }
        return Enumerate<SmoServerRole>(source);
    }

    // SMO loads a collection when it is first enumerated; a read that faults is written as the engine writes it.
    private List<T>? Enumerate<T>(IEnumerable collection)
    {
        try
        {
            return EnumerateOrThrow<T>(collection);
        }
        catch (CaughtFault fault)
        {
            SurfaceFault(fault.Record);
            return null;
        }
    }

    // The engine's record for a collection read that faults: ExceptionInGetEnumerator when the failure carries a record,
    // otherwise the record a failing MoveNext gives (BadEnumeration, InvalidOperation, the enumerator as target).
    private static List<T> EnumerateOrThrow<T>(IEnumerable collection)
    {
        List<T> rows = new();
        IEnumerator? enumerator = null;
        try
        {
            enumerator = LanguagePrimitives.GetEnumerator(collection);
            while (enumerator is not null && enumerator.MoveNext())
                rows.Add((T)enumerator.Current);
            return rows;
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            if (failure is IContainsErrorRecord container && container.ErrorRecord is not null)
                throw new CaughtFault(new ErrorRecord(container.ErrorRecord, failure));
            RuntimeException enumeration = new(String.Format(CultureInfo.InvariantCulture,
                "An error occurred while enumerating through a collection: {0}.", failure.Message), failure);
            throw new CaughtFault(new ErrorRecord(enumeration, "BadEnumeration", ErrorCategory.InvalidOperation, enumerator));
        }
    }

    // A .NET method the pin calls outside any try; a fault is written as the engine writes it and reads as null.
    private StringCollection? InvokeRead(string method, Func<StringCollection> read)
    {
        try
        {
            return read();
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            SurfaceFault(MethodFaultRecord(method, 0, failure));
            return null;
        }
    }

    // The engine's record for a .NET method that throws.
    private static ErrorRecord MethodFaultRecord(string method, int arguments, Exception failure)
    {
        if (failure is IContainsErrorRecord container && container.ErrorRecord is not null)
            return new ErrorRecord(container.ErrorRecord, failure);
        MethodInvocationException invocation = new(String.Format(CultureInfo.InvariantCulture,
            "Exception calling \"{0}\" with \"{1}\" argument(s): \"{2}\"", method, arguments, failure.Message), failure);
        return new ErrorRecord(invocation, failure.GetType().Name, ErrorCategory.NotSpecified, null);
    }

    // A statement fault in the pin's body, which has no try around it: a plain call writes it and goes on, a caller's try
    // catches it, -EnableException stops here.
    private void SurfaceFault(ErrorRecord fault)
    {
        if (EnableException.ToBool())
        {
            // caller-try: terminate -- -EnableException asks for the stop
            ThrowTerminatingError(fault); // style-ok: cs-raw-streams a statement fault of the pin's body, outside Stop-Function, as in the pin
        }

        StatementFault.Surface(this, fault);
    }

    // PS: Where-Object { $_.IsFixedRole -eq $false }. A role whose property read throws is left out.
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

    // PS: -in / -notin compare each listed value with -eq: case-insensitive, and nothing matches a $null list.
    private static bool IsIn(string? value, string[]? list)
    {
        return list is not null && Array.Exists(list, item => LanguagePrimitives.Equals(value, item, true, CultureInfo.InvariantCulture));
    }

    // PS: "$($logins -join ', ')": each login as its text.
    private static string JoinText(List<SmoLogin>? logins)
    {
        if (logins is null)
            return String.Empty;
        List<string> texts = new();
        foreach (SmoLogin login in logins)
            texts.Add(login.ToString());
        return String.Join(", ", texts);
    }

    // The roles a Where-Object left as they were after its read faulted: the collection, with the filters asked for so far.
    private sealed class FaultedRoles : IEnumerable
    {
        internal FaultedRoles(IEnumerable source, Predicate<SmoServerRole> keep)
        {
            if (source is FaultedRoles earlier)
            {
                Source = earlier.Source;
                Keep = role => earlier.Keep(role) && keep(role);
            }
            else
            {
                Source = source;
                Keep = keep;
            }
        }

        internal IEnumerable Source { get; }

        internal Predicate<SmoServerRole> Keep { get; }

        public IEnumerator GetEnumerator()
        {
            return Source.GetEnumerator();
        }
    }

    // A fault that leaves the absorbed Get-DbaLogin, or a read, carrying the record the pin's catch sees as $_.
    private sealed class CaughtFault : Exception
    {
        internal CaughtFault(ErrorRecord record)
            : base(record.Exception?.Message, record.Exception)
        {
            Record = record;
        }

        internal ErrorRecord Record { get; }
    }
}
