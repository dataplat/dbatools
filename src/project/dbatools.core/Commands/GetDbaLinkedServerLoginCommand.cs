#nullable enable

using System;
using System.Collections.Generic;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Common;
using Microsoft.SqlServer.Management.Smo;
using SmoLinkedServer = Microsoft.SqlServer.Management.Smo.LinkedServer;

namespace Dataplat.Dbatools.Commands;

// Port of public/Get-DbaLinkedServerLogin.ps1 at refs/pins/dbatools-2026-10-22: the login mappings of the linked servers read
// through the nested Connect-DbaInstance and Get-DbaLinkedServer, or of the servers and linked servers piped in, each the SMO
// object decorated with its instance.
/// <summary>Retrieves linked server login mappings and authentication configurations from SQL Server instances.</summary>
/// <para>
/// Retrieves the login mappings configured for linked servers, showing how local SQL Server logins are mapped to remote server credentials. This function returns details about each login mapping including the local login name, remote user account, and whether impersonation is enabled. Use this to audit linked server security configurations, troubleshoot authentication issues between servers, or document cross-server login relationships for compliance purposes.
/// </para>
/// <example>
/// <code>
/// PS C:\&gt;Get-DbaLinkedServerLogin -SqlInstance sql01 -LinkedServer linkedServer1 -LocalLogin login1
/// </code>
/// <para>
/// Gets the linked server login "login1" from the linked server "linkedServer1" on sql01.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt;Get-DbaLinkedServerLogin -SqlInstance sql01 -LinkedServer linkedServer1 -ExcludeLocalLogin login2
/// </code>
/// <para>
/// Gets the linked server login(s) from the linked server "linkedServer1" on sql01 and excludes the login2 linked server login.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt;(Get-DbaLinkedServer -SqlInstance sql01 -LinkedServer linkedServer1) | Get-DbaLinkedServerLogin -LocalLogin login1
/// </code>
/// <para>
/// Gets the linked server login "login1" from the linked server "linkedServer1" on sql01 using a pipeline with the linked server passed in.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt;(Connect-DbaInstance -SqlInstance sql01) | Get-DbaLinkedServerLogin -LinkedServer linkedServer1 -LocalLogin login1
/// </code>
/// <para>
/// Gets the linked server login "login1" from the linked server "linkedServer1" on sql01 using a pipeline with the instance passed in.
/// </para>
/// </example>
/// <list type="alertSet">
/// <item>
/// <term />
/// <description>
/// <para>
/// Tags: LinkedServer, Login
/// Author: Adam Lancaster, github.com/lancasteradam
/// </para>
/// <para>
/// dbatools PowerShell module (https://dbatools.io)
/// Copyright: (c) 2021 by dbatools, licensed under MIT
/// License: MIT https://opensource.org/licenses/MIT
/// </para>
/// </description>
/// </item>
/// </list>
/// <seealso href="https://dbatools.io/Get-DbaLinkedServerLogin" />
[Cmdlet(VerbsCommon.Get, "DbaLinkedServerLogin", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Low)]
[OutputType(typeof(LinkedServerLogin))]
public sealed class GetDbaLinkedServerLoginCommand : DbaBaseCmdlet
{
    // PS: the nested commands whose messages the pin shows under their own names.
    private const string ConnectRunner = "Connect-DbaInstance";
    private const string LinkedServerReader = "Get-DbaLinkedServer";

    // PS: the members the loop adds with Add-Member -Force.
    private static readonly string[] AddedMembers = { "ComputerName", "InstanceName", "SqlInstance" };

    // PS: the members the nested Get-DbaLinkedServer adds to each linked server with Add-Member -Force and Select-DefaultView.
    private static readonly string[] LinkedServerMembers = { "ComputerName", "InstanceName", "SqlInstance", "Impersonate", "RemoteUser", "RemoteServer", "Publisher" };

    /// <para>
    /// The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function
    /// to be executed against multiple SQL Server instances.
    /// </para>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

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
    public PSCredential? SqlCredential { get; set; }

    /// <para>
    /// Specifies the name(s) of the linked server(s) to retrieve login mappings from. Required when using SqlInstance parameter.
    /// Use this to focus on specific linked servers when you have multiple configured on the instance.
    /// </para>
    [Parameter(Position = 2)]
    public string[]? LinkedServer { get; set; }

    /// <para>
    /// Filters results to only include specific local SQL Server login names that have mappings configured for the linked server.
    /// Useful when auditing a specific user's access or troubleshooting authentication for particular accounts.
    /// </para>
    [Parameter(Position = 3)]
    public string[]? LocalLogin { get; set; }

    /// <para>
    /// Excludes specific local SQL Server login names from the results, showing all other configured login mappings.
    /// Use this to hide system accounts or service accounts when focusing on user login mappings.
    /// </para>
    [Parameter(Position = 4)]
    public string[]? ExcludeLocalLogin { get; set; }

    /// <para>
    /// Accepts piped input from Connect-DbaInstance or Get-DbaLinkedServer commands to work with existing connection objects.
    /// When piping from Get-DbaLinkedServer, the LinkedServer parameter becomes optional since the linked server context is already established.
    /// </para>
    [Parameter(ValueFromPipeline = true, Position = 5)]
    public object[]? InputObject { get; set; }

    // Overridden only to carry the pinned .PARAMETER EnableException help; same bare [Parameter] as the base.
    /// <para>
    /// By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
    /// This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
    /// Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.
    /// </para>
    [Parameter]
    public override SwitchParameter EnableException { get; set; }

    // The pinned body calls no ShouldProcess and none of its nested commands supports it, so -WhatIf and -Confirm change nothing.
    /// <summary>Writes the login mappings of each linked server read or piped in.</summary>
    protected override void ProcessRecord()
    {
        // PS: $InputObject += ..., on the record's bound value.
        List<object?> inputs = new();
        if (InputObject is not null)
            inputs.AddRange(InputObject);

        foreach (DbaInstanceParameter instance in SqlInstance ?? Array.Empty<DbaInstanceParameter>())
        {
            // PS: if (Test-Bound -Not -ParameterName LinkedServer) { Stop-Function -Message "LinkedServer is required" -Continue }
            if (!TestBound(nameof(LinkedServer)))
            {
                StopFunction("LinkedServer is required", continueLoop: true);
                continue;
            }

            // PS: $InputObject += Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential | Get-DbaLinkedServer -LinkedServer $LinkedServer
            Server? server = Connect(instance);
            if (server is null)
                continue;
            List<SmoLinkedServer>? read = ReadLinkedServers(new DbaInstanceParameter((object)server));
            if (read is not null)
                inputs.AddRange(read);
        }

        foreach (object? obj in inputs)
        {
            // Correction stale-linked-server: the pin's $ls lives in the function's scope, so an object that is neither a Server
            // nor a LinkedServer listed the logins of the linked server the object before it left there, or of whatever $ls the
            // module or global scope held (pin probe 6e0a67ed). Each object reads only its own linked servers.
            List<SmoLinkedServer>? ls = null;
            object? item = obj is PSObject wrapped ? wrapped.BaseObject : obj;
            if (item is Server piped)
            {
                if (!TestBound(nameof(LinkedServer)))
                {
                    StopFunction("LinkedServer is required", continueLoop: true);
                    continue;
                }

                DbaInstanceParameter pipedInstance = new((object)piped);
                if (piped.DatabaseEngineType == DatabaseEngineType.SqlAzureDatabase)
                {
                    RefuseAzure(pipedInstance, new ConnectionResolutionException(ConnectionResolutionFailure.AzureUnsupported, "Azure SQL Database not supported", null));
                    continue;
                }

                // PS: $ls = Get-DbaLinkedServer -SqlInstance $obj -LinkedServer $LinkedServer
                ls = ReadLinkedServers(pipedInstance);
            }
            else if (item is SmoLinkedServer linked)
            {
                ls = new List<SmoLinkedServer> { linked };
            }

            if (ls is null || ls.Count == 0)
                continue;

            // PS: $ls.parent.ComputerName, .ServiceName and .DomainInstanceName by member enumeration: one linked server gives its
            // instance's value, more give an array with one value for each.
            object? computerName = EnumerateParent(ls, "ComputerName");
            object? instanceName = EnumerateParent(ls, "ServiceName");
            object? sqlInstance = EnumerateParent(ls, "DomainInstanceName");

            // PS: $ls.LinkedServerLogins, then Name -in $LocalLogin and Name -notin $ExcludeLocalLogin when those are true.
            bool include = LanguagePrimitives.IsTrue(LocalLogin);
            bool exclude = LanguagePrimitives.IsTrue(ExcludeLocalLogin);
            List<LinkedServerLogin> selected = new();
            foreach (SmoLinkedServer each in ls)
            {
                foreach (LinkedServerLogin login in each.LinkedServerLogins)
                {
                    if (include && !ContainsName(LocalLogin!, login.Name))
                        continue;
                    if (exclude && ContainsName(ExcludeLocalLogin!, login.Name))
                        continue;
                    selected.Add(login);
                }
            }

            foreach (LinkedServerLogin login in selected)
                WriteObject(Decorate(login, computerName, instanceName, sqlInstance));
        }
    }

    // PS: Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential, called with no try. Connect-DbaInstance sets
    // its own -EnableException unless -DisableException is passed, so its Stop-Function throws out of this command whatever this
    // command's -EnableException: a caller's try catches the record (pin probe 6e0a67ed), and outside any try the throw ends the
    // caller's script (pin probe eb1989e7, both editions). Keep-going rule: the plain call stops where the pin's stops, so the
    // port ends the command with that record, plain or under -EnableException, before any login is written.
    private Server? Connect(DbaInstanceParameter instance)
    {
        SmoConnectionRequest request = new();
        request.Instance = instance;
        request.SqlCredential = SqlCredential;
        // Correction azure-unsupported: the engine is refused here, before the nested Get-DbaLinkedServer reads anything.
        request.AzureUnsupported = true;
        request.BoundParameters = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { nameof(SqlInstance), nameof(SqlCredential) };
        request.MessageCallback = (level, message) => WriteAttributedMessage(ConnectRunner, level, message);
        WriteAttributedMessage(ConnectRunner, MessageLevel.Debug, "Starting process block");
        try
        {
            Server server = ConnectionService.GetServer(request);
            SetActiveConnection(server.ConnectionContext);
            WriteAttributedMessage(ConnectRunner, MessageLevel.Debug, "We are finished with this instance");
            return server;
        }
        catch (ConnectionResolutionException refusal) when (refusal.Kind == ConnectionResolutionFailure.AzureUnsupported)
        {
            RefuseAzure(instance, refusal);
            return null;
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            ErrorRecord stop;
            if (failure is ConnectionResolutionException resolution && resolution.Kind != ConnectionResolutionFailure.ConnectFailure)
            {
                // PS: the other Stop-Function calls of Connect-DbaInstance, each with its own message and no record.
                stop = NestedConnectStop(instance, resolution.Message, null);
            }
            else
            {
                // PS: Stop-Function -Target $instance -Message "Failure" -Category ConnectionError -ErrorRecord $connectionError -Continue
                Exception reported = failure is ConnectionResolutionException ? failure.InnerException ?? failure : failure;
                stop = NestedConnectStop(instance, "Failure", new ErrorRecord(reported, "dbatools_" + ConnectRunner, ErrorCategory.NotSpecified, instance));
            }

            ThrowTerminatingError(stop); // style-ok: cs-raw-streams the nested Connect-DbaInstance's thrown record, outside this command's Stop-Function, ends the command as in the pin
            return null;
        }
    }

    // Correction azure-unsupported: linked servers do not exist in Azure SQL Database (Microsoft Learn, "Linked servers (Database
    // Engine)"), where the pin's nested Get-DbaLinkedServer reads nothing and says nothing (pin probe 6e0a67ed). The command refuses
    // the engine itself, as the shared connection refusal does (watchman f4ce1876): Stop-Function -Message "Failure" -Category
    // ConnectionError with the refusal's record, then the next instance; it stops there under -EnableException.
    private void RefuseAzure(DbaInstanceParameter instance, ConnectionResolutionException refusal)
    {
        ErrorRecord record = new(refusal, "dbatools_" + MyInvocation.MyCommand.Name, ErrorCategory.ConnectionError, instance);
        StopFunction("Failure", target: instance, errorRecord: record, category: ErrorCategory.ConnectionError, continueLoop: true);
    }

    // PS: Stop-Function inside Connect-DbaInstance under its default -EnableException: the message is logged and not shown (3>$null),
    // and the record it throws is built from the connection's record, "Error connecting to [<instance>]: <message>", or from the
    // message alone.
    private ErrorRecord NestedConnectStop(DbaInstanceParameter instance, string message, ErrorRecord? connectionError)
    {
        MessageService.MessageRequest context = new();
        context.FunctionName = ConnectRunner;
        context.ModuleName = "dbatools";
        object target = MessageService.CollapseTarget(MessageService.ResolveTarget(this, context, instance));

        ErrorRecord record;
        bool overrideText;
        if (connectionError is not null)
        {
            Exception resolved = MessageService.ResolveException(this, context, connectionError.Exception);
            if (resolved != connectionError.Exception)
                connectionError = new ErrorRecord(resolved, connectionError.FullyQualifiedErrorId, connectionError.CategoryInfo.Category, connectionError.TargetObject);
            string text = String.Format("Error connecting to [{0}]: {1}", MaskedTargetText(instance), MessageService.GetErrorMessage(connectionError));
            // PS: if ($record.CategoryInfo.Category) - NotSpecified is falsy, so -Category ConnectionError stands.
            ErrorCategory category = connectionError.CategoryInfo.Category != ErrorCategory.NotSpecified ? connectionError.CategoryInfo.Category : ErrorCategory.ConnectionError;
            record = new ErrorRecord(new Exception(text, connectionError.Exception), "dbatools_" + ConnectRunner, category, target);
            overrideText = false;
        }
        else
        {
            record = new ErrorRecord(new Exception(message), "dbatools_" + ConnectRunner, ErrorCategory.NotSpecified, target);
            overrideText = true;
        }

        MessageService.MessageRequest request = new();
        request.Level = MessageLevel.Warning;
        request.Message = message;
        request.FunctionName = ConnectRunner;
        request.ModuleName = "dbatools";
        request.Target = target;
        request.ErrorRecord = new[] { record };
        request.EnableException = true;
        request.OverrideExceptionMessage = overrideText;
        request.SuppressWarningDisplay = true;
        request.FromStopFunction = true;
        request.File = MyInvocation.ScriptName;
        request.Line = MyInvocation.ScriptLineNumber;
        MessageService.Write(this, request);
        return record;
    }

    // PS: Get-DbaLinkedServer -SqlInstance <server> -LinkedServer $LinkedServer, called without -EnableException: its connection
    // reuses the server, then $server.LinkedServers filtered by Name -in $LinkedServer when that is true, each decorated as it
    // decorates them. A failure warns under its name and gives nothing.
    private List<SmoLinkedServer>? ReadLinkedServers(DbaInstanceParameter instance)
    {
        Server? server = ConnectNested(instance);
        if (server is null)
            return null;

        LinkedServerCollection? linkedServers;
        try
        {
            linkedServers = server.LinkedServers;
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            // PS: $server.LinkedServers as the dot reads it: a fault of the SMO getter gives $null with no error and no message (on
            // Azure SQL Database it throws UnsupportedVersionException: item evidence pin-azure-lsgetter of Get-DbaLinkedServer).
            return null;
        }

        bool include = LanguagePrimitives.IsTrue(LinkedServer);
        List<SmoLinkedServer> selected = new();
        foreach (SmoLinkedServer linked in linkedServers)
        {
            if (include && !ContainsName(LinkedServer!, linked.Name))
                continue;
            DecorateLinkedServer(linked, server);
            selected.Add(linked);
        }
        return selected;
    }

    // PS: Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential inside the nested Get-DbaLinkedServer's try,
    // whose catch is Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue, with no
    // -EnableException passed on: the warning shows under that command's name in the one-line form its port writes.
    private Server? ConnectNested(DbaInstanceParameter instance)
    {
        SmoConnectionRequest request = new();
        request.Instance = instance;
        request.BoundParameters = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { nameof(SqlInstance), nameof(SqlCredential) };
        request.MessageCallback = (level, message) => WriteAttributedMessage(ConnectRunner, level, message);
        WriteAttributedMessage(ConnectRunner, MessageLevel.Debug, "Starting process block");
        try
        {
            Server server = ConnectionService.GetServer(request);
            SetActiveConnection(server.ConnectionContext);
            WriteAttributedMessage(ConnectRunner, MessageLevel.Debug, "We are finished with this instance");
            return server;
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            ErrorRecord record = new(failure, "dbatools_" + LinkedServerReader, ErrorCategory.ConnectionError, instance);
            if (failure is ConnectionResolutionException resolution && resolution.Kind == ConnectionResolutionFailure.ConnectFailure)
            {
                string line = String.Format("Failure | Error connecting to [{0}]: {1}", MaskedTargetText(instance), MessageService.GetErrorMessage(record));
                WarnNestedStopFunction(LinkedServerReader, line, target: instance, errorRecord: record, category: ErrorCategory.ConnectionError, overrideExceptionMessage: true);
                return null;
            }
            WarnNestedStopFunction(LinkedServerReader, "Failure", target: instance, errorRecord: record, category: ErrorCategory.ConnectionError);
            return null;
        }
    }

    // PS: the nested Get-DbaLinkedServer's Add-Member -Force calls and Select-DefaultView, on the SMO linked server itself.
    private static void DecorateLinkedServer(SmoLinkedServer linked, Server server)
    {
        PSObject output = PSObject.AsPSObject(linked);
        object? impersonate = EnumerateLogins(linked, login => login.Impersonate);
        object? remoteUser = EnumerateLogins(linked, login => login.RemoteUser);
        foreach (string member in LinkedServerMembers)
            output.Properties.Remove(member);
        OutputHelper.AddInstanceProperties(output, server);
        output.Properties.Add(new PSNoteProperty("Impersonate", impersonate));
        output.Properties.Add(new PSNoteProperty("RemoteUser", remoteUser));
        OutputHelper.AddAliasProperty(output, "RemoteServer", "DataSource");
        OutputHelper.AddAliasProperty(output, "Publisher", "DistPublisher");
        OutputHelper.SetDefaultDisplayPropertySet(output,
            "ComputerName", "InstanceName", "SqlInstance", "Name", "RemoteServer", "ProductName", "Impersonate", "RemoteUser",
            "Publisher", "Distributor", "DateLastModified");
    }

    // PS: the loop's Add-Member -Force calls and Select-DefaultView, on the SMO login itself.
    private static PSObject Decorate(LinkedServerLogin login, object? computerName, object? instanceName, object? sqlInstance)
    {
        PSObject output = PSObject.AsPSObject(login);
        foreach (string member in AddedMembers)
            output.Properties.Remove(member);
        output.Properties.Add(new PSNoteProperty("ComputerName", computerName)); // style-ok: cs-output-props $ls.parent.ComputerName by member enumeration as the source does, an array for several linked servers; OutputHelper needs one server
        output.Properties.Add(new PSNoteProperty("InstanceName", instanceName)); // style-ok: cs-output-props $ls.parent.ServiceName by member enumeration as the source does; OutputHelper needs one server
        output.Properties.Add(new PSNoteProperty("SqlInstance", sqlInstance)); // style-ok: cs-output-props $ls.parent.DomainInstanceName by member enumeration as the source does; OutputHelper needs one server
        OutputHelper.SetDefaultDisplayPropertySet(output, "ComputerName", "InstanceName", "SqlInstance", "Name", "RemoteUser", "Impersonate");
        return output;
    }

    // PS: $ls.parent.<name>: each linked server's parent read as the dot reads it, one value for one linked server, an array for more.
    private static object? EnumerateParent(List<SmoLinkedServer> linkedServers, string name)
    {
        if (linkedServers.Count == 1)
            return SmoServerExtensions.GetPSProperty(linkedServers[0].Parent, name);
        object?[] values = new object?[linkedServers.Count];
        for (int index = 0; index < linkedServers.Count; index++)
            values[index] = SmoServerExtensions.GetPSProperty(linkedServers[index].Parent, name);
        return values;
    }

    // PS: member-access enumeration of a property over the logins collection: no login gives $null, one gives its value, more give an array.
    private static object? EnumerateLogins(SmoLinkedServer linked, Func<LinkedServerLogin, object?> read)
    {
        List<object?> values = new();
        foreach (LinkedServerLogin login in linked.LinkedServerLogins)
            values.Add(read(login));
        if (values.Count == 0)
            return null;
        if (values.Count == 1)
            return values[0];
        return values.ToArray();
    }

    // PS: $_.Name -in $values: each value is the left operand of -eq, so the name converts to the value's type, ignoring case.
    // The shared NativeDatabaseSelection.ContainsInOperand is internal to dbatools.database, which dbatools.core cannot reach.
    private static bool ContainsName(object[] values, string name) // style-ok: cs-local-contains-name the shared NativeDatabaseSelection helper is internal to dbatools.database
    {
        foreach (object value in values)
        {
            if (LanguagePrimitives.Equals(value, name, true, CultureInfo.InvariantCulture))
                return true;
        }
        return false;
    }
}
