#nullable enable

using System;
using System.Collections.Generic;
using System.Globalization;
using System.Management.Automation;
using System.Text.RegularExpressions;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.RegisteredServers;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

/// <summary>Copies Central Management Server groups and registered server instances between SQL Server instances.</summary>
[Cmdlet(VerbsCommon.Copy, "DbaRegServer", DefaultParameterSetName = "Default", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
public sealed class CopyDbaRegServerCommand : DbaBaseCmdlet
{
    /// <summary>Source SQL Server instance containing the CMS to copy from.</summary>
    [Parameter(Mandatory = true, Position = 0)]
    public DbaInstanceParameter Source { get; set; } = null!;

    /// <summary>Credential for the source instance.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SourceSqlCredential { get; set; }

    /// <summary>Destination SQL Server instance(s) for the copied CMS content.</summary>
    [Parameter(Mandatory = true, Position = 2)]
    public DbaInstanceParameter[] Destination { get; set; } = null!;

    /// <summary>Credential for the destination instances.</summary>
    [Parameter(Position = 3)]
    public PSCredential? DestinationSqlCredential { get; set; }

    /// <summary>Top-level CMS group name(s) to copy; all when omitted.</summary>
    [Parameter(Position = 4)]
    [Alias("CMSGroup")]
    [PsStringArrayCast]
    public string[]? Group { get; set; }

    /// <summary>Replaces source server name references with the destination server name.</summary>
    [Parameter]
    public SwitchParameter SwitchServerName { get; set; }

    /// <summary>Drops and recreates existing groups and registrations at the destination.</summary>
    [Parameter]
    public SwitchParameter Force { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // The pinned helper Invoke-ParseServerGroup writes its messages under its own name.
    private const string HelperName = "Invoke-ParseServerGroup";
    private const string RootGroupName = "DatabaseEngineServerGroup";

    private Server? _sourceServer;
    private RegisteredServersStore? _fromCmStore;
    private Server? _destServer;
    private RegisteredServersStore? _toCmStore;

    protected override void BeginProcessing()
    {
        _sourceServer = Connect(Source, SourceSqlCredential, false);
        if (_sourceServer is null)
            return;
        _fromCmStore = OpenStore(_sourceServer);
    }

    protected override void ProcessRecord()
    {
        if (Interrupted || _sourceServer is null)
            return;

        foreach (DbaInstanceParameter destinstance in Destination)
        {
            CancellationToken.ThrowIfCancellationRequested();
            _destServer = Connect(destinstance, DestinationSqlCredential, true);
            if (_destServer is null)
                continue;
            _toCmStore = OpenStore(_destServer);
            if (_fromCmStore is null || _toCmStore is null)
                continue;

            ServerGroup? sourceRoot = RootGroup(_fromCmStore, out Exception? sourceFault);
            List<ServerGroup> stores = new();
            if (LanguagePrimitives.IsTrue(Group))
            {
                foreach (string groupName in Group!)
                {
                    // PS: $stores += $fromCmStore.DatabaseEngineServerGroup.ServerGroups[$groupName] indexes null for each
                    // name when the root group cannot be read, and the pin goes on to the next name.
                    if (sourceRoot is null)
                    {
                        ReportFault(NullArrayFault());
                        continue;
                    }

                    ServerGroup? sourceGroup = GroupNamed(sourceRoot, groupName);
                    // Upstream correction (wrong data): the pinned function added $null for a group the source does not
                    // have, then reported it as an existing destination group (or, with -Force, dropped the destination
                    // root group). Such a name is skipped with a warning.
                    if (sourceGroup is null)
                    {
                        WriteMessage(MessageLevel.Warning, String.Format(CultureInfo.InvariantCulture,
                            "Group {0} does not exist on {1}", groupName, _sourceServer.Name), target: groupName);
                        continue;
                    }
                    stores.Add(sourceGroup);
                }
            }
            else if (sourceRoot is not null)
            {
                stores.Add(sourceRoot);
            }
            else
            {
                // Upstream correction (wrong data): the pinned getter reads as null, so without -Group the whole copy silently does nothing.
                ReportFault(GetterFault(RootGroupName, sourceFault!));
            }

            if (stores.Count == 0)
                continue;

            // PS: an unreadable destination root group is a null -destinationgroup, which the helper takes as it is.
            ServerGroup? destinationRoot = RootGroup(_toCmStore, out _);
            foreach (ServerGroup store in stores)
            {
                CancellationToken.ThrowIfCancellationRequested();
                ParseServerGroup(store, destinationRoot, destinstance.ToString(), null);
            }
        }
    }

    // PS: Invoke-ParseServerGroup. destinstance and groupName follow the pinned helper's dynamic scoping: the helper
    // reads the caller's values until it assigns its own (groupName in the destination group block, destinstance in
    // the registered server loop), and a nested call sees the values of the call that made it.
    private void ParseServerGroup(ServerGroup sourceGroup, ServerGroup? destinationGroup, string destinstance, string? groupName)
    {
        if (destinationGroup is not null && PsString.Eq(destinationGroup.Name, RootGroupName) && !PsString.Eq(sourceGroup.Name, RootGroupName))
        {
            ServerGroup currentServerGroup = destinationGroup;
            groupName = sourceGroup.Name;
            destinationGroup = GroupNamed(destinationGroup, groupName);

            PSObject copyDestinationGroupStatus = Status(groupName, "CMS Destination Group");

            if (destinationGroup is not null)
            {
                if (!Force)
                {
                    if (Confirm(destinstance, String.Format(CultureInfo.InvariantCulture, "Checking to see if {0} exists", groupName)))
                    {
                        Emit(copyDestinationGroupStatus, "Skipped", "Already exists on destination");
                        WriteAttributedMessage(HelperName, MessageLevel.Verbose, String.Format(CultureInfo.InvariantCulture,
                            "Destination group {0} exists at destination. Use -Force to drop and migrate.", groupName));
                    }
                    return;
                }
                if (Confirm(destinstance, "Dropping group " + groupName))
                {
                    try
                    {
                        WriteAttributedMessage(HelperName, MessageLevel.Verbose, "Dropping group " + groupName);
                        destinationGroup.Drop();
                    }
                    catch (Exception failure) when (failure is not PipelineStoppedException)
                    {
                        string notes = MethodFault("Drop", 0, failure);
                        Emit(copyDestinationGroupStatus, "Failed", notes);
                        WriteAttributedMessage(HelperName, MessageLevel.Verbose, String.Format(CultureInfo.InvariantCulture,
                            "Issue dropping group {0} on {1} | {2}", groupName, destinstance, notes));
                        return;
                    }
                }
            }

            if (Confirm(destinstance, "Creating group " + groupName))
            {
                try
                {
                    WriteAttributedMessage(HelperName, MessageLevel.Verbose, "Creating group " + sourceGroup.Name);
                    destinationGroup = NewGroup(currentServerGroup, sourceGroup.Name);
                    destinationGroup.Create();
                    Emit(copyDestinationGroupStatus, "Successful", null);
                }
                catch (CallFault fault)
                {
                    Emit(copyDestinationGroupStatus, "Failed", fault.Message);
                    WriteAttributedMessage(HelperName, MessageLevel.Verbose, String.Format(CultureInfo.InvariantCulture,
                        "Issue creating group {0} on {1} | {2}", groupName, destinstance, fault.Message));
                    return;
                }
                catch (Exception failure) when (failure is not PipelineStoppedException)
                {
                    string notes = MethodFault("Create", 0, failure);
                    Emit(copyDestinationGroupStatus, "Failed", notes);
                    WriteAttributedMessage(HelperName, MessageLevel.Verbose, String.Format(CultureInfo.InvariantCulture,
                        "Issue creating group {0} on {1} | {2}", groupName, destinstance, notes));
                    return;
                }
            }
        }

        // Add Servers
        foreach (RegisteredServer instance in Servers(sourceGroup))
        {
            CancellationToken.ThrowIfCancellationRequested();
            destinstance = _destServer!.Name;
            CopyInstance(instance, destinationGroup, destinstance, groupName);
        }

        // Add Groups
        foreach (ServerGroup fromSubGroup in SubGroups(sourceGroup))
        {
            CancellationToken.ThrowIfCancellationRequested();
            string fromSubGroupName = fromSubGroup.Name;
            ServerGroup? toSubGroup = null;
            PSObject copyGroupStatus = Status(fromSubGroupName, "CMS Group");
            if (Confirm(destinstance, "Copying group " + fromSubGroupName))
            {
                // PS: $destinationGroup.ServerGroups[$fromSubGroupName] indexes the null destination of an unreadable root group.
                if (destinationGroup is null)
                    ReportFault(NullArrayFault());
                else
                    toSubGroup = GroupNamed(destinationGroup, fromSubGroupName);
            }

            if (toSubGroup is not null)
            {
                if (!Force)
                {
                    string exists = String.Format(CultureInfo.InvariantCulture,
                        "Subgroup {0} exists at destination. Use -Force to drop and migrate.", fromSubGroupName);
                    if (Confirm(destinstance, exists))
                    {
                        Emit(copyGroupStatus, "Skipped", "Already exists on destination");
                        WriteAttributedMessage(HelperName, MessageLevel.Verbose, exists);
                    }
                    continue;
                }

                if (Confirm(destinstance, String.Format(CultureInfo.InvariantCulture, "Dropping subgroup {0} recreating", fromSubGroupName)))
                {
                    try
                    {
                        WriteAttributedMessage(HelperName, MessageLevel.Verbose, "Dropping subgroup " + fromSubGroupName);
                        toSubGroup.Drop();
                    }
                    catch (Exception failure) when (failure is not PipelineStoppedException)
                    {
                        string notes = MethodFault("Drop", 0, failure);
                        Emit(copyGroupStatus, "Failed", notes);
                        WriteAttributedMessage(HelperName, MessageLevel.Verbose, String.Format(CultureInfo.InvariantCulture,
                            "Issue dropping group {0} on {1} | {2}", fromSubGroupName, destinstance, notes));
                        continue;
                    }
                }
            }

            if (Confirm(destinstance, "Creating group " + fromSubGroupName))
            {
                try
                {
                    WriteAttributedMessage(HelperName, MessageLevel.Verbose, "Creating group " + fromSubGroupName);
                    toSubGroup = NewGroup(destinationGroup, fromSubGroupName);
                    toSubGroup.Create();
                    Emit(copyGroupStatus, "Successful", null);
                }
                catch (CallFault fault)
                {
                    Emit(copyGroupStatus, "Failed", fault.Message);
                    WriteAttributedMessage(HelperName, MessageLevel.Verbose, String.Format(CultureInfo.InvariantCulture,
                        "Issue creating group {0} to {1} | {2}", fromSubGroupName, destinstance, fault.Message));
                    continue;
                }
                catch (Exception failure) when (failure is not PipelineStoppedException)
                {
                    string notes = MethodFault("Create", 0, failure);
                    Emit(copyGroupStatus, "Failed", notes);
                    WriteAttributedMessage(HelperName, MessageLevel.Verbose, String.Format(CultureInfo.InvariantCulture,
                        "Issue creating group {0} to {1} | {2}", fromSubGroupName, destinstance, notes));
                    continue;
                }
            }

            ParseServerGroup(fromSubGroup, toSubGroup, destinstance, groupName);
        }
    }

    private void CopyInstance(RegisteredServer instance, ServerGroup? destinationGroup, string destinstance, string? groupName)
    {
        string instanceName = instance.Name;
        string serverName = instance.ServerName;
        PSObject copyInstanceStatus = Status(instanceName, "CMS Instance");
        string toName = _toCmStore!.DomainInstanceName;
        string fromName = _fromCmStore!.DomainInstanceName;

        if (PsString.Eq(serverName?.ToLowerInvariant(), toName?.ToLowerInvariant()))
        {
            if (SwitchServerName)
            {
                serverName = fromName;
                instanceName = fromName;
                WriteAttributedMessage(HelperName, MessageLevel.Verbose, String.Format(CultureInfo.InvariantCulture,
                    "SwitchServerName was used and new CMS equals current server name. {0} changed to {1}.", toName?.ToLowerInvariant(), serverName));
            }
            else
            {
                string prohibited = serverName + " is Central Management Server. Add prohibited. Skipping.";
                if (Confirm(destinstance, prohibited))
                {
                    Emit(copyInstanceStatus, "Skipped", null);
                    WriteAttributedMessage(HelperName, MessageLevel.Verbose, prohibited);
                }
                return;
            }
        }

        if (destinationGroup is not null && ContainsServer(destinationGroup, instanceName))
        {
            if (!Force)
            {
                if (Confirm(destinstance, String.Format(CultureInfo.InvariantCulture, "Checking to see if {0} in {1} exists", instanceName, groupName)))
                {
                    Emit(copyInstanceStatus, "Skipped", "Already exists on destination");
                    WriteAttributedMessage(HelperName, MessageLevel.Verbose, String.Format(CultureInfo.InvariantCulture,
                        "Instance {0} exists in group {1} at destination. Use -Force to drop and migrate.", instanceName, groupName));
                }
                return;
            }

            if (Confirm(destinstance, String.Format(CultureInfo.InvariantCulture, "Dropping instance {0} from {1} and recreating", instanceName, groupName)))
            {
                try
                {
                    WriteAttributedMessage(HelperName, MessageLevel.Verbose, String.Format(CultureInfo.InvariantCulture,
                        "Dropping instance {0} from {1}", instance, groupName));
                    RegisteredServer? existing = destinationGroup.RegisteredServers[instanceName];
                    if (existing is null)
                        throw new CallFault("You cannot call a method on a null-valued expression.");
                    existing.Drop();
                }
                catch (Exception failure) when (failure is not PipelineStoppedException)
                {
                    string notes = failure is CallFault ? failure.Message : MethodFault("Drop", 0, failure);
                    Emit(copyInstanceStatus, "Failed", notes);
                    WriteAttributedMessage(HelperName, MessageLevel.Verbose, String.Format(CultureInfo.InvariantCulture,
                        "Issue dropping instance {0} from {1} and recreating on {2} | {3}", instanceName, groupName, destinstance, notes));
                    return;
                }
            }
        }

        if (!Confirm(destinstance, "Copying " + instanceName))
            return;

        try
        {
            RegisteredServer newServer = NewServer(destinationGroup, instanceName);
            SetServerName(newServer, serverName);
            newServer.Description = instance.Description;

            if (!PsString.Eq(serverName, fromName))
            {
                newServer.SecureConnectionString = instance.SecureConnectionString;
                if (instance.ConnectionString is not null)
                    newServer.ConnectionString = instance.ConnectionString;
            }

            newServer.Create();
            Emit(copyInstanceStatus, "Successful", null);
            WriteAttributedMessage(HelperName, MessageLevel.Verbose, String.Format(CultureInfo.InvariantCulture,
                "Added Server {0} as {1} to {2}", serverName, instanceName, destinationGroup?.Name));
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            string notes = failure is CallFault ? failure.Message : MethodFault("Create", 0, failure);
            Emit(copyInstanceStatus, "Failed", notes);
            // PS: $_.Exception -match "same name" reads the whole exception text, inner exceptions included.
            if (Regex.IsMatch(failure.ToString(), "same name", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant))
                WriteAttributedMessage(HelperName, MessageLevel.Verbose, "Could not add Switched Server instance name on " + instanceName);
            else
                WriteAttributedMessage(HelperName, MessageLevel.Verbose, String.Format(CultureInfo.InvariantCulture,
                    "Failed to add {0} on {1}", serverName, instanceName));
        }
    }

    // PS: $group.ServerGroups[$name]. An indexer that fails reads as $null there, with no record, and the pin goes on as for a
    // group that is not there (evidence/pin-regserver-faults-20261101.txt).
    private static ServerGroup? GroupNamed(ServerGroup group, string name)
    {
        try
        {
            return group.ServerGroups[name];
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            return null;
        }
    }

    // PS: $destinationGroup.RegisteredServers.Name -contains $instanceName (case-insensitive). The member access reads the whole
    // collection before -contains runs, so a read that fails is the if statement's fault: the condition counts as false and the
    // registration goes on to its copy. A getter that fails reads as $null there, with no record. Measured on the pin: a denied
    // group with no registrations gives no record, and one holding registrations gives one for two copies, from the same
    // collection object this method reads (evidence/pin-regserver-contains-20261102.txt).
    private bool ContainsServer(ServerGroup group, string name)
    {
        IEnumerable<RegisteredServer> collection;
        try
        {
            collection = group.RegisteredServers;
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            return false;
        }

        IEnumerator<RegisteredServer> enumerator;
        try
        {
            enumerator = collection.GetEnumerator();
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            ReportFault(EnumeratorFault(failure));
            return false;
        }

        using (enumerator)
        {
            bool found = false;
            try
            {
                while (enumerator.MoveNext())
                    found |= PsString.Eq(enumerator.Current.Name, name);
            }
            catch (Exception failure) when (failure is not PipelineStoppedException)
            {
                ReportFault(BadEnumerationFault(failure, enumerator));
                return false;
            }
            return found;
        }
    }

    // PS: foreach ($instance in $sourceGroup.RegisteredServers) and foreach ($fromSubGroup in $sourceGroup.ServerGroups).
    private IEnumerable<RegisteredServer> Servers(ServerGroup? group)
    {
        return Members<RegisteredServer>(group, "RegisteredServers", static source => source.RegisteredServers);
    }

    private IEnumerable<ServerGroup> SubGroups(ServerGroup? group)
    {
        return Members<ServerGroup>(group, "ServerGroups", static source => source.ServerGroups);
    }

    // A missing group yields nothing, as foreach over $null does. SFC loads the collection from msdb in GetEnumerator
    // (EnsureCollectionInitialized), so a denied or lost read there is the pinned foreach statement's fault. The members
    // stream as foreach gives them: the loop body runs for those read before a fault, and the record follows their output.
    private IEnumerable<T> Members<T>(ServerGroup? group, string property, Func<ServerGroup, IEnumerable<T>> read)
    {
        if (group is null)
            yield break;

        IEnumerable<T>? collection = null;
        try
        {
            collection = read(group);
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            // Upstream correction (wrong data): the pinned getter reads as null, so the loop silently copies nothing from this group.
            ReportFault(GetterFault(property, failure));
        }
        if (collection is null)
            yield break;

        IEnumerator<T>? enumerator = null;
        try
        {
            enumerator = collection.GetEnumerator();
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            ReportFault(EnumeratorFault(failure));
        }
        if (enumerator is null)
            yield break;

        using (enumerator)
        {
            while (true)
            {
                bool more = false;
                T current = default!;
                try
                {
                    more = enumerator.MoveNext();
                    if (more)
                        current = enumerator.Current;
                }
                catch (Exception failure) when (failure is not PipelineStoppedException)
                {
                    more = false;
                    ReportFault(MoveNextFault(failure));
                }
                if (!more)
                    yield break;
                yield return current;
            }
        }
    }

    // A pinned statement's fault outside any try of the function: a plain call writes it and goes on with the next statement.
    // The corrected getters report the same way, where the pin drops the fault.
    private void ReportFault(ErrorRecord record)
    {
        if (EnableException.ToBool())
        {
            // caller-try: terminate -- -EnableException asks for the stop
            ThrowTerminatingError(record); // style-ok: cs-raw-streams pinned statement fault outside Stop-Function
        }

        // caller-try: continue -- a plain call of the pin writes this record and goes on with its next statement, here the next group, name or destination
        WriteError(record);
    }

    // PS: $newServer.ServerName = $serverName, outside the pinned try. The parentless server of a null destination refuses
    // it, and the pin goes on to Create(), whose missing parent is the Failed row.
    private void SetServerName(RegisteredServer server, string? serverName)
    {
        try
        {
            server.ServerName = serverName;
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            SetValueInvocationException fault = new(String.Format(CultureInfo.InvariantCulture,
                "Exception setting \"ServerName\": \"{0}\"", failure.Message), failure);
            ReportFault(new ErrorRecord(fault, "ExceptionWhenSetting", ErrorCategory.NotSpecified, null));
        }
    }

    // The engine's record for a foreach whose GetEnumerator fails (evidence/pin-regserver-cms-20261101.txt).
    private static ErrorRecord EnumeratorFault(Exception failure)
    {
        ExtendedTypeSystemException fault = new(String.Format(CultureInfo.InvariantCulture,
            "The following exception occurred while trying to enumerate the collection: \"{0}\".", failure.Message), failure);
        return new ErrorRecord(fault, "ExceptionInGetEnumerator", ErrorCategory.NotSpecified, null);
    }

    // The engine's record for a foreach whose MoveNext fails: the exception itself (evidence/pin-regserver-faults-20261101.txt).
    private static ErrorRecord MoveNextFault(Exception failure)
    {
        return new ErrorRecord(failure, failure.GetType().FullName, ErrorCategory.OperationStopped, null);
    }

    // The engine's record for a member access whose MoveNext fails (evidence/pin-regserver-faults-20261101.txt).
    private static ErrorRecord BadEnumerationFault(Exception failure, object enumerator)
    {
        RuntimeException fault = new(String.Format(CultureInfo.InvariantCulture,
            "An error occurred while enumerating through a collection: {0}.", failure.Message), failure);
        return new ErrorRecord(fault, "BadEnumeration", ErrorCategory.InvalidOperation, enumerator);
    }

    // The engine's record for indexing null.
    private static ErrorRecord NullArrayFault()
    {
        return new ErrorRecord(new RuntimeException("Cannot index into a null array."), "NullArray", ErrorCategory.InvalidOperation, null);
    }

    // The engine's adapter record for a failing property getter (Adapter.BasePropertyGet), which the pin's member binder drops.
    private static ErrorRecord GetterFault(string property, Exception failure)
    {
        GetValueInvocationException fault = new(String.Format(CultureInfo.InvariantCulture,
            "Exception getting \"{0}\": \"{1}\"", property, failure.Message), failure);
        return new ErrorRecord(fault, "CatchFromBaseAdapterGetValue", ErrorCategory.NotSpecified, null);
    }

    // PS: New-Object Microsoft.SqlServer.Management.RegisteredServers.ServerGroup($parent, $name). New-Object reports a
    // failing constructor as a method fault of ".ctor".
    private static ServerGroup NewGroup(ServerGroup? parent, string? name)
    {
        try
        {
            return new ServerGroup(parent, name);
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            throw new CallFault(MethodFault(".ctor", 2, failure));
        }
    }

    // PS: New-Object Microsoft.SqlServer.Management.RegisteredServers.RegisteredServer($destinationGroup, $instanceName).
    private static RegisteredServer NewServer(ServerGroup? parent, string name)
    {
        try
        {
            return new RegisteredServer(parent, name);
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            throw new CallFault(MethodFault(".ctor", 2, failure));
        }
    }

    // PS: Connect-DbaInstance -SqlInstance $instance -SqlCredential $credential -MinimumVersion 10 in a try whose catch
    // runs Stop-Function -Message "Failure" -Category ConnectionError (-Continue for a destination).
    // Upstream correction (wrong data): Central Management Servers keep their groups in msdb, which Azure SQL Database
    // does not have, so both connects refuse it as Connect-DbaInstance -AzureUnsupported does.
    private Server? Connect(DbaInstanceParameter instance, PSCredential? credential, bool continueLoop)
    {
        WriteAttributedMessage("Connect-DbaInstance", MessageLevel.Debug, "Starting process block");
        try
        {
            Server server = ConnectionService.GetServer(new SmoConnectionRequest
            {
                Instance = instance,
                SqlCredential = credential,
                MinimumVersion = 10,
                AzureUnsupported = true,
                BoundParameters = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "SqlInstance", "SqlCredential" },
                MessageCallback = (level, message) => WriteAttributedMessage("Connect-DbaInstance", level, message)
            });
            SetActiveConnection(server.ConnectionContext);
            WriteAttributedMessage("Connect-DbaInstance", MessageLevel.Debug, "We are finished with this instance");
            return server;
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            StopFunction("Failure", target: instance,
                errorRecord: new ErrorRecord(failure, "dbatools_Copy-DbaRegServer", ErrorCategory.ConnectionError, instance),
                category: ErrorCategory.ConnectionError, continueLoop: continueLoop);
            return null;
        }
    }

    // PS: Get-DbaRegServerStore -SqlInstance $server, which builds the store on the connection and, when that fails,
    // warns "Cannot access Central Management Server on <instance>" and returns nothing.
    private RegisteredServersStore? OpenStore(Server server)
    {
        try
        {
            return new RegisteredServersStore(server.ConnectionContext);
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            WriteAttributedMessage("Get-DbaRegServerStore", MessageLevel.Warning, String.Format(CultureInfo.InvariantCulture,
                "Cannot access Central Management Server on {0} | {1}", server.Name, MethodFault(".ctor", 1, failure)), target: server.Name);
            return null;
        }
    }

    // PS: $store.DatabaseEngineServerGroup. The member binder turns a failing getter into $null, with no error, whatever
    // the caller's try (evidence/pin-regserver-cms-20261101.txt).
    private static ServerGroup? RootGroup(RegisteredServersStore store, out Exception? fault)
    {
        fault = null;
        try
        {
            return store.DatabaseEngineServerGroup;
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            fault = failure;
            return null;
        }
    }

    // -Force sets $ConfirmPreference to 'none' for the whole function in the pinned begin block.
    private bool Confirm(string target, string action)
    {
        if (!Force)
            return ShouldProcess(target, action);
        object? previousPreference = SessionState.PSVariable.GetValue("ConfirmPreference");
        try
        {
            SessionState.PSVariable.Set("ConfirmPreference", ConfirmImpact.None);
            return ShouldProcess(target, action);
        }
        finally
        {
            SessionState.PSVariable.Set("ConfirmPreference", previousPreference);
        }
    }

    // The message PowerShell gives a failed .NET method call: 'Exception calling "X" with "N" argument(s): "..."'.
    private static string MethodFault(string method, int arguments, Exception failure)
    {
        return String.Format(CultureInfo.InvariantCulture, "Exception calling \"{0}\" with \"{1}\" argument(s): \"{2}\"",
            method, arguments, failure.Message);
    }

    private PSObject Status(string? name, string type)
    {
        PSObject result = new();
        result.Properties.Add(new PSNoteProperty("SourceServer", _sourceServer!.Name));
        result.Properties.Add(new PSNoteProperty("DestinationServer", _destServer!.Name));
        result.Properties.Add(new PSNoteProperty("Name", name));
        result.Properties.Add(new PSNoteProperty("Type", type));
        result.Properties.Add(new PSNoteProperty("Status", null));
        result.Properties.Add(new PSNoteProperty("Notes", null));
        result.Properties.Add(new PSNoteProperty("DateTime", new DbaDateTime(DateTime.Now)));
        return result;
    }

    // Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
    private void Emit(PSObject result, string status, string? notes)
    {
        result.Properties["Status"].Value = status;
        result.Properties["Notes"].Value = notes;
        OutputHelper.SetDefaultDisplayPropertySet(result, "DateTime", "SourceServer", "DestinationServer", "Name", "Type", "Status", "Notes");
        OutputHelper.InsertTypeName(result, "MigrationObject");
        WriteObject(result);
    }

    // A failure whose text is already what the pinned catch block reads as $_.Exception.Message.
    private sealed class CallFault : Exception
    {
        public CallFault(string message)
            : base(message)
        {
        }
    }
}
