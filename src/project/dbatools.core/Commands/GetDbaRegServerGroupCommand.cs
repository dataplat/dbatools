#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.RegisteredServers;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

// Port of public/Get-DbaRegServerGroup.ps1 at refs/pins/dbatools-2026-10-22, with the nested Get-DbaRegServerStore (per
// instance with -EnableException inside the pin's try, and for the local file store) read through that command's shared
// code, the private Get-RegServerGroupReverseParse and Disconnect-RegServer in C#, and -ExcludeGroup's recursive call to
// this command run as the same lookup on a store of the parent server.
/// <summary>Retrieves server group objects from SQL Server Central Management Server (CMS) for organized server management.</summary>
/// <para>
/// Returns server group objects from Central Management Server, which are organizational containers that help DBAs manage multiple SQL Server instances in a hierarchical structure. Server groups allow you to categorize registered servers by environment, function, or any logical grouping that makes sense for your infrastructure.
/// </para>
/// <para>
/// This function is essential for inventory management and automated administration across multiple SQL Server instances. Use it to discover existing server groups before adding new registered servers, or to build dynamic server lists for bulk operations based on your organizational structure.
/// </para>
/// <para>
/// The function supports targeting specific groups by name or path (including nested subgroups), excluding certain groups from results, or filtering by group ID. You can work with both local CMS stores and remote Central Management Server instances.
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaRegServerGroup -SqlInstance sqlserver2014a
/// </code>
/// <para>
/// Gets the top level groups from the CMS on sqlserver2014a, using Windows Credentials.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaRegServerGroup -SqlInstance sqlserver2014a -SqlCredential $credential
/// </code>
/// <para>
/// Gets the top level groups from the CMS on sqlserver2014a, using alternative credentials to authenticate to the server.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaRegServerGroup -SqlInstance sqlserver2014a -Group HR, Accounting
/// </code>
/// <para>
/// Gets the HR and Accounting groups from the CMS on sqlserver2014a.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaRegServerGroup -SqlInstance sqlserver2014a -Group HR\Development
/// </code>
/// <para>
/// Returns the sub-group Development of the HR group from the CMS on sqlserver2014a.
/// </para>
/// </example>
/// <list type="alertSet">
/// <item>
/// <term />
/// <description>
/// <para>
/// Tags: RegisteredServer, CMS
/// Author: Tony Wilhelm (@tonywsql)
/// </para>
/// <para>
/// Website: https://dbatools.io
/// Copyright: (c) 2018 by dbatools, licensed under MIT
/// License: MIT https://opensource.org/licenses/MIT
/// </para>
/// </description>
/// </item>
/// </list>
/// <seealso href="https://dbatools.io/Get-DbaRegServerGroup" />
[Cmdlet(VerbsCommon.Get, "DbaRegServerGroup")]
public sealed class GetDbaRegServerGroupCommand : DbaInstanceCmdlet
{
    /// <para>
    /// The target SQL Server instance or instances.
    /// </para>
    [Parameter(Position = 0, ValueFromPipeline = true)]
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
    /// Specifies one or more server group names to retrieve from Central Management Server. Supports hierarchical paths using backslash notation (e.g., 'Production\WebServers').
    /// Use this when you need specific organizational groups rather than all groups, or when working with nested subgroups within your CMS structure.
    /// </para>
    [Parameter(Position = 2)]
    public object[]? Group { get; set; }

    /// <para>
    /// Specifies one or more server group names to exclude from the results. Accepts the same hierarchical path format as the Group parameter.
    /// Use this when you want all groups except certain ones, such as excluding test environments from production operations or removing deprecated groups from inventory reports.
    /// </para>
    [Parameter(Position = 3)]
    public object[]? ExcludeGroup { get; set; }

    /// <para>
    /// Retrieves server groups by their numeric identifier. Note that Id 1 always represents the root DatabaseEngineServerGroup, and this parameter only works for groups that contain registered servers.
    /// Use this when you need to target groups programmatically using their internal CMS identifiers, typically in automated scripts that reference groups by ID rather than name.
    /// </para>
    [Parameter(Position = 4)]
    public int[]? Id { get; set; }

    /// <para>
    /// By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
    /// This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
    /// Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.
    /// </para>
    [Parameter]
    public override SwitchParameter EnableException { get; set; }

    private const string StoreCommandName = "Get-DbaRegServerStore";
    private const string RootGroupName = "DatabaseEngineServerGroup";

    // The store's members that Add-Member -Force copies onto each group. An instance store has OutputHelper's triple from its
    // server; the local file store has none, so each reads $null there.
    private static readonly string[] InstanceColumns = { "ComputerName", "InstanceName", "SqlInstance" };

    private static readonly string[] InstanceView = { "ComputerName", "InstanceName", "SqlInstance", "Name", "DisplayName", "Description", "ServerGroups", "RegisteredServers" };
    private static readonly string[] LocalView = { "Name", "DisplayName", "Description", "ServerGroups", "RegisteredServers" };

    protected override void ProcessRecord()
    {
        // PS: begin { $serverstores = $groups = @() }, never reset. Correction accumulated-results: the pin keeps both from one
        // piped instance to the next and $groups from one store to the next, so a later store repeats the earlier groups
        // relabelled with its own instance's columns; here each record reads only its own stores, and each store starts
        // with no groups.
        List<RegServerStore> serverStores = new();
        foreach (DbaInstanceParameter? instance in SqlInstance ?? Array.Empty<DbaInstanceParameter>())
        {
            // PS: try { $serverstores += Get-DbaRegServerStore -SqlInstance $instance -SqlCredential $SqlCredential -EnableException }
            //     catch { Stop-Function -Message "Cannot access Central Management Server '$instance'" -ErrorRecord $_ -Continue }
            ErrorRecord? nestedStop = OpenInstanceStore(instance, out RegServerStore? store);
            if (nestedStop is not null)
            {
                StopFunction(String.Format(CultureInfo.InvariantCulture, "Cannot access Central Management Server '{0}'", instance),
                    errorRecord: nestedStop, continueLoop: true);
                continue;
            }

            serverStores.Add(store!);
        }

        // PS: if (-not $SqlInstance) { $serverstores += Get-DbaRegServerStore }: the value's truthiness, so a null or empty
        // -SqlInstance reads the local file store.
        if (!LanguagePrimitives.IsTrue(SqlInstance))
        {
            RegServerStore? local = OpenLocalStore();
            if (local is not null)
                serverStores.Add(local);
        }

        foreach (RegServerStore serverStore in serverStores)
        {
            // Correction cms-read-failure: for a login that cannot read the Central Management Server tables in msdb, reading
            // the store's root group throws, which the pin's PowerShell read hides as $null, so the pin returns no groups for
            // that instance and says nothing. Here the instance is reported as one this command cannot access, and the next
            // store is read.
            if (serverStore.Instance is not null && !CanReadGroups(serverStore))
                continue;

            List<object?> groups;
            if (LanguagePrimitives.IsTrue(Group))
            {
                groups = new List<object?>();
                LookUpGroups(serverStore.Store, Group!, groups);
            }
            else
            {
                WriteMessage(MessageLevel.Verbose, "Added all root server groups");

                // PS: $groups = $serverstore.DatabaseEngineServerGroup.ServerGroups. For a login that cannot see the Central
                // Management Server groups in msdb the root group reads $null, so this is $null and the store has no groups
                // (evidence/pin-group-read-fault-ao-20261112.txt).
                ServerGroup? root = RootGroup(serverStore.Store);
                groups = root is null ? new List<object?>() : Elements(root.ServerGroups);
            }

            if (LanguagePrimitives.IsTrue(ExcludeGroup))
            {
                // PS: $excluded = Get-DbaRegServerGroup -SqlInstance $serverstore.ParentServer -SqlCredential $SqlCredential -Group $ExcludeGroup
                List<object?> excluded = LookUpExcluded(serverStore);
                WriteMessage(MessageLevel.Verbose, "Excluding " + JoinValues(ExcludeGroup));

                // PS: $groups | Where-Object { $_.Urn.Value -notin $excluded.Urn.Value }
                List<object?> excludedUrns = new();
                foreach (object? item in excluded)
                    excludedUrns.Add(UrnValue(item));
                List<object?> kept = new();
                foreach (object? item in groups)
                {
                    if (!ContainsValue(excludedUrns, UrnValue(item)))
                        kept.Add(item);
                }
                groups = kept;
            }

            if (LanguagePrimitives.IsTrue(Id))
            {
                WriteMessage(MessageLevel.Verbose, String.Format(CultureInfo.InvariantCulture, "Filtering for id {0}. Id 1 = default.", JoinValues(Id)));
                groups = FilterById(serverStore.Store);
            }

            // PS: Disconnect-RegServer -Server $serverstore
            DisconnectStore(serverStore);

            foreach (object? groupObject in groups)
            {
                if (groupObject is null)
                    continue;
                WriteObject(Decorate(groupObject, serverStore));
            }
        }
    }

    // PS: -Id: if ($Id -eq 1) the root, else the parent group of each descendant registered server whose Id is in $Id.
    // Correction id-filter: the pin's ($Id -eq 1) is true whenever 1 is among the Ids, so it returns the root alone and drops
    // the other Ids, and its parent list holds a group once per registered server in it. Here 1 gives the root, the other
    // Ids their groups after it, and each group once, in the order the pin finds them.
    private List<object?> FilterById(RegisteredServersStore store)
    {
        List<object?> matches = new();
        ServerGroup? root = RootGroup(store);
        if (root is null)
        {
            // PS: with a $null root group, ($Id -eq 1) gives $groups = $null, and any other -Id calls
            // $null.GetDescendantRegisteredServers(): the statement's InvokeMethodOnNull record, and no groups.
            if (!ContainsValue(Id, 1))
                SurfaceFault(new ErrorRecord(new RuntimeException("You cannot call a method on a null-valued expression."),
                    "InvokeMethodOnNull", ErrorCategory.InvalidOperation, null));
            return matches;
        }

        if (ContainsValue(Id, 1))
            matches.Add(root);

        foreach (RegisteredServer registered in root.GetDescendantRegisteredServers())
        {
            ServerGroup? parent = registered.Parent;
            if (parent is not null && ContainsValue(Id, parent.ID) && !ContainsGroup(matches, parent))
                matches.Add(parent);
        }
        return matches;
    }

    // The same group: the same object, or the same Urn (the root and a parent read back from a registered server).
    private static bool ContainsGroup(List<object?> groups, ServerGroup group)
    {
        string? urn = group.Urn?.Value;
        foreach (object? item in groups)
        {
            if (ReferenceEquals(item, group) || (urn is not null && String.Equals(UrnValue(item) as string, urn, StringComparison.Ordinal)))
                return true;
        }
        return false;
    }

    // PS: foreach ($currentgroup in $Group) { ... $groups += ... }: the groups named by value, path or ServerGroup object.
    private void LookUpGroups(RegisteredServersStore store, object[] names, List<object?> groups)
    {
        foreach (object? currentGroup in names)
        {
            WriteMessage(MessageLevel.Verbose, "Processing " + ValueText(currentGroup));
            object? value = currentGroup is PSObject wrapped ? wrapped.BaseObject : currentGroup;

            // PS: if ($currentgroup -is [ServerGroup]) { $currentgroup = Get-RegServerGroupReverseParse -object $currentgroup }
            string text = value is ServerGroup serverGroup ? ReverseParse(serverGroup) : ValueText(value);

            // PS, after the loop: if ($Group -eq 'DatabaseEngineServerGroup') { $groups = $serverstore.DatabaseEngineServerGroup }.
            // Correction root-group-dropped: that replaces every other group named with the root alone, and never matches the
            // root's ServerGroup object. Here the root's name, or the root object, gives the root in its place in the list.
            if (String.Equals(text, RootGroupName, StringComparison.OrdinalIgnoreCase))
            {
                WriteMessage(MessageLevel.Verbose, "Added root group");
                ServerGroup? rootGroup = RootGroup(store);
                if (rootGroup is null)
                    RecordNullIndex(); // the pin's lookup of the name in the loop, before the root statement
                else
                    groups.Add(rootGroup);
                continue;
            }

            // PS: if ($currentgroup -match 'DatabaseEngineServerGroup\\') { $currentgroup = $currentgroup.Replace('DatabaseEngineServerGroup\', '') }
            if (text.IndexOf(RootGroupName + "\\", StringComparison.OrdinalIgnoreCase) >= 0)
                text = text.Replace(RootGroupName + "\\", String.Empty);

            if (text.IndexOf('\\') >= 0)
            {
                // PS: walk $serverstore.DatabaseEngineServerGroup.ServerGroups[$split[$i]] for each part of the path.
                string[] split = text.Split('\\');
                ServerGroup? groupObject = RootGroup(store);
                foreach (string part in split)
                {
                    if (groupObject is not null)
                    {
                        groupObject = groupObject.ServerGroups[part];
                        WriteMessage(MessageLevel.Verbose, "Parsed " + groupObject?.Name);
                    }
                }

                if (groupObject is not null)
                    groups.Add(groupObject);
            }
            else
            {
                ServerGroup? lookupRoot = RootGroup(store);
                if (lookupRoot is null)
                {
                    RecordNullIndex();
                    continue;
                }

                ServerGroup? thisGroup;
                try
                {
                    thisGroup = lookupRoot.ServerGroups[text];
                }
                catch (Exception failure) when (failure is not PipelineStoppedException)
                {
                    // PS: catch { $null = 1 }: the pin drops a lookup that throws and goes on with the next value.
                    WriteMessage(MessageLevel.Debug, "Lookup of " + text + " failed: " + failure.Message);
                    continue;
                }

                if (thisGroup is not null)
                {
                    WriteMessage(MessageLevel.Verbose, "Added " + thisGroup.Name);
                    groups.Add(thisGroup);
                }
            }
        }
    }

    // PS: Get-DbaRegServerGroup -SqlInstance $serverstore.ParentServer -SqlCredential $SqlCredential -Group $ExcludeGroup, without
    // -EnableException: the same lookup on a new store of the parent server, or of the local file store when there is none.
    private List<object?> LookUpExcluded(RegServerStore serverStore)
    {
        List<object?> excluded = new();
        RegServerStore? nested;
        if (serverStore.ParentServer is null)
        {
            nested = OpenLocalStore();
        }
        else
        {
            DbaInstanceParameter parent = new(serverStore.ParentServer);
            ErrorRecord? nestedStop = OpenInstanceStore(parent, out nested);
            if (nestedStop is not null)
            {
                // The recursive call has no -EnableException: its Stop-Function -Continue warns under its name and goes on.
                WarnNestedStopFunction("Get-DbaRegServerGroup", String.Format(CultureInfo.InvariantCulture, "Cannot access Central Management Server '{0}'", parent),
                    errorRecord: nestedStop);
                return excluded;
            }
        }

        if (nested is null)
            return excluded;

        LookUpGroups(nested.Store, ExcludeGroup!, excluded);
        DisconnectStore(nested);
        return excluded;
    }

    // The nested Get-DbaRegServerStore -SqlInstance $instance -SqlCredential $SqlCredential -EnableException: its connect
    // (-IsNewConnectionReference; refuses Azure SQL Database as its correction azure-unsupported does) and its
    // RegisteredServersStore. A failure is its Stop-Function under -EnableException, logged without display and thrown for
    // the caller's catch: the record is returned and nothing is thrown here.
    private ErrorRecord? OpenInstanceStore(DbaInstanceParameter? instance, out RegServerStore? serverStore)
    {
        serverStore = null;
        Server server;
        bool isNewConnection;
        WriteAttributedMessage("Connect-DbaInstance", MessageLevel.Debug, "Starting process block");
        try
        {
            // Correction azure-unsupported: a Central Management Server keeps its groups in msdb, which Azure SQL Database does
            // not have; the nested store refuses it as Connect-DbaInstance -AzureUnsupported does (its own correction).
            server = ResolveConnection(instance!, out isNewConnection, azureUnsupported: true);
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            // PS (Get-DbaRegServerStore): catch { Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue }
            ErrorRecord record = new(failure, "dbatools_" + StoreCommandName, ErrorCategory.ConnectionError, instance);
            string? line = ConnectFailureLine(failure, record, instance!, "Failure");
            return CaughtNestedStopFunction(StoreCommandName, line ?? "Failure", instance, record, ErrorCategory.ConnectionError, line is not null);
        }

        RegisteredServersStore store;
        try
        {
            // PS (Get-DbaRegServerStore): New-Object Microsoft.SqlServer.Management.RegisteredServers.RegisteredServersStore($server.ConnectionContext)
            store = new RegisteredServersStore(server.ConnectionContext);
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            // PS (Get-DbaRegServerStore): catch { Stop-Function -Message "Cannot access Central Management Server on $instance"
            //     -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue }
            return CaughtNestedStopFunction(StoreCommandName,
                String.Format(CultureInfo.InvariantCulture, "Cannot access Central Management Server on {0}", instance), instance,
                GetDbaRegServerStoreCommand.ConstructorFaultRecord(failure, instance), ErrorCategory.ConnectionError);
        }

        // PS (Get-DbaRegServerStore): Add-Member ComputerName, InstanceName, SqlInstance, ParentServer, IsNewConnection
        PSObject columns = new();
        OutputHelper.AddInstanceProperties(columns, server);
        object?[] values = new object?[InstanceColumns.Length];
        for (int n = 0; n < InstanceColumns.Length; n++)
            values[n] = columns.Properties[InstanceColumns[n]]?.Value;
        serverStore = new RegServerStore(store, server, isNewConnection, values, instance);
        return null;
    }

    // The nested Get-DbaRegServerStore with no -SqlInstance: the local file store, read by that command's shared reader; its
    // statement faults surface here.
    private RegServerStore? OpenLocalStore()
    {
        object? local = GetDbaRegServerStoreCommand.ReadLocalStore(this, SurfaceFault);
        return local is RegisteredServersStore store ? new RegServerStore(store, null, false, new object?[InstanceColumns.Length]) : null;
    }

    // PS: Disconnect-RegServer: closes the store's connection only when the store opened it (#10572).
    private static void DisconnectStore(RegServerStore serverStore)
    {
        if (serverStore.IsNewConnection && serverStore.Store.ServerConnection is not null)
            serverStore.Store.ServerConnection.Disconnect();
    }

    // PS: Add-Member -Force ComputerName, InstanceName, SqlInstance, ParentServer from the store, then Select-DefaultView with
    // the instance columns when ComputerName is set, else without them.
    private static PSObject Decorate(object groupObject, RegServerStore serverStore)
    {
        PSObject wrapped = PSObject.AsPSObject(groupObject);
        for (int n = 0; n < InstanceColumns.Length; n++)
            SetNote(wrapped, InstanceColumns[n], serverStore.Columns[n]);
        SetNote(wrapped, "ParentServer", serverStore.ParentServer);
        OutputHelper.SetDefaultDisplayPropertySet(wrapped, LanguagePrimitives.IsTrue(serverStore.Columns[0]) ? InstanceView : LocalView);
        return wrapped;
    }

    private static void SetNote(PSObject target, string name, object? value)
    {
        target.Properties.Remove(name);
        target.Properties.Add(new PSNoteProperty(name, value));
    }

    // PS: Get-RegServerGroupReverseParse: the group's path below DatabaseEngineServerGroup, parents first.
    private static string ReverseParse(ServerGroup group)
    {
        if (String.Equals(group.Name, RootGroupName, StringComparison.OrdinalIgnoreCase))
            return group.Name;

        List<string> names = new();
        object? current = group;
        do
        {
            string name = PropertyValue(current, "Name") as string ?? String.Empty;
            names.Add(name.Split('\\')[0]);
            current = PropertyValue(current, "Parent");
        }
        while (current is not null && !String.Equals(PropertyValue(current, "Name") as string, RootGroupName, StringComparison.OrdinalIgnoreCase));

        names.Reverse();
        return String.Join("\\", names);
    }

    private static object? PropertyValue(object? item, string name)
    {
        return item is null ? null : PSObject.AsPSObject(item).Properties[name]?.Value;
    }

    // PS: $_.Urn.Value
    private static object? UrnValue(object? item)
    {
        return item is ServerGroup group ? group.Urn?.Value : PropertyValue(PropertyValue(item, "Urn"), "Value");
    }

    private static List<object?> Elements(IEnumerable collection)
    {
        List<object?> items = new();
        foreach (object? item in collection)
            items.Add(item);
        return items;
    }

    // PS: -eq / -in against an array: any element equal, case-insensitively.
    private static bool ContainsValue(IEnumerable? values, object? value)
    {
        if (values is null)
            return false;
        foreach (object? element in values)
        {
            if (LanguagePrimitives.Equals(element, value, true))
                return true;
        }
        return false;
    }

    // PS: "$value" for a message: $null is empty.
    private static string ValueText(object? value)
    {
        return value is null ? String.Empty : PSObject.AsPSObject(value).ToString();
    }

    // PS: "$array" joins with a space ($OFS).
    private static string JoinValues(IEnumerable? values)
    {
        List<string> texts = new();
        if (values is not null)
        {
            foreach (object? value in values)
                texts.Add(ValueText(value));
        }
        return String.Join(" ", texts);
    }

    // Correction cms-read-failure: the read the pin hides, reported as this command's own "Cannot access Central Management
    // Server" Stop-Function -Continue (a warning, or under -EnableException the stop), after the store's connection is closed
    // as Disconnect-RegServer closes it.
    private bool CanReadGroups(RegServerStore serverStore)
    {
        try
        {
            _ = serverStore.Store.DatabaseEngineServerGroup;
            return true;
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            DisconnectStore(serverStore);
            StopFunction(String.Format(CultureInfo.InvariantCulture, "Cannot access Central Management Server '{0}'", serverStore.Instance),
                target: serverStore.Instance, exception: failure, continueLoop: true);
            return false;
        }
    }

    // PS: $serverstore.DatabaseEngineServerGroup. PowerShell member access hides an exception the getter throws and gives
    // $null, recording nothing, inside a try or not and in strict mode too: for a login that cannot read the Central
    // Management Server tables in msdb the getter throws ExecutionFailureException (SELECT permission denied on
    // sysmanagement_shared_server_groups) and the pin reads $null (evidence/pin-root-getter-20261112.txt, both editions).
    private static ServerGroup? RootGroup(RegisteredServersStore store)
    {
        try
        {
            return store.DatabaseEngineServerGroup;
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            return null;
        }
    }

    // PS: try { $serverstore.DatabaseEngineServerGroup.ServerGroups[$currentgroup] } catch { $null = 1 } with a $null root
    // group: indexing $null fails inside the pin's own try, so nothing is shown and the caught record lands in $Error.
    private void RecordNullIndex()
    {
        InnerCommand.InsertGlobalError(this, new ErrorRecord(new RuntimeException("Cannot index into a null array."),
            "NullArray", ErrorCategory.InvalidOperation, null));
    }

    // A statement of the pin (or of its nested Get-DbaRegServerStore) outside any try: a plain call writes the record and goes on, a
    // caller's try catches it, and -EnableException stops here ("Operator decision: keep going unless -EnableException",
    // point 3).
    private void SurfaceFault(ErrorRecord fault)
    {
        if (EnableException.ToBool())
        {
            // caller-try: terminate -- -EnableException asks for the stop
            ThrowTerminatingError(fault); // style-ok: cs-raw-streams a statement fault outside Stop-Function, as in the pin
        }

        StatementFault.Surface(this, fault);
    }

    // One store as the nested Get-DbaRegServerStore returns it, with the members this command reads back.
    private sealed class RegServerStore
    {
        internal RegServerStore(RegisteredServersStore store, Server? parentServer, bool isNewConnection, object?[] columns,
            DbaInstanceParameter? instance = null)
        {
            Instance = instance;
            Store = store;
            ParentServer = parentServer;
            IsNewConnection = isNewConnection;
            Columns = columns;
        }

        // The -SqlInstance value an instance store was opened for; null for the local file store.
        internal DbaInstanceParameter? Instance { get; }

        internal RegisteredServersStore Store { get; }

        internal Server? ParentServer { get; }

        internal bool IsNewConnection { get; }

        internal object?[] Columns { get; }
    }
}
