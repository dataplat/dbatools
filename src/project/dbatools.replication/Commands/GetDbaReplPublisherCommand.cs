#nullable enable

using System;
using System.Collections;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;
using Microsoft.SqlServer.Replication;

namespace Dataplat.Dbatools.Commands;

// Port of public/Get-DbaReplPublisher.ps1. Its Connect-DbaInstance and nested Get-DbaReplServer calls are the shared native
// replication connection (NativeReplicationServer), with Get-DbaReplServer's failure handling kept under its name.

/// <summary>
/// Retrieves SQL Server replication publisher configuration and status from distribution servers.
/// </summary>
/// <para>
/// Retrieves detailed information about SQL Server replication publishers configured on distribution servers. This function connects to instances acting as distributors and returns publisher details including status, working directory, distribution database, and publication counts. Use this to audit replication topology, troubleshoot publisher connectivity issues, or verify publisher configurations across your replication environment.
/// </para>
/// <para>
/// All properties from the base SMO DistributionPublisher object are accessible using Select-Object * even though only default properties are displayed by default.
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaReplPublisher -SqlInstance mssql1
/// </code>
/// <para>
/// Gets publisher for the mssql1 instance.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Connect-DbaInstance -SqlInstance mssql1 |  Get-DbaReplPublisher
/// </code>
/// <para>
/// Pipes a SQL Server object to get publisher information for the mssql1 instance.
/// </para>
/// </example>
/// <list type="alertSet">
/// <item>
/// <term />
/// <description>
/// <para>
/// Tags: repl, Replication
/// Author: Mikey Bronowski (@MikeyBronowski), bronowski.it
/// </para>
/// <para>
/// Website: https://dbatools.io
/// Copyright: (c) 2022 by dbatools, licensed under MIT
/// License: MIT https://opensource.org/licenses/MIT
/// </para>
/// </description>
/// </item>
/// <item>
/// <term>OUTPUTS</term>
/// <description>
/// <para>
/// Microsoft.SqlServer.Replication.DistributionPublisher
/// </para>
/// <para>
/// Returns one DistributionPublisher object for each Publisher configured on the distribution server instance. If no publishers are configured, nothing is returned.
/// </para>
/// <para>
/// Default display properties (via Select-DefaultView):
/// - ComputerName: The computer name of the SQL Server instance
/// - InstanceName: The SQL Server instance name
/// - SqlInstance: The full SQL Server instance name (computer\instance)
/// - Status: The current status of the Publisher (e.g., Healthy, Unhealthy)
/// - WorkingDirectory: Directory path where publication data and schema files are stored
/// - DistributionDatabase: The name of the distribution database used for this Publisher
/// - DistributionPublications: Number of transactional publications at the Publisher
/// - PublisherType: The type of Publisher (e.g., MSSQLSERVER for SQL Server, or third-party identifier)
/// - Name: The instance name of the Publisher
/// </para>
/// <para>
/// Additional properties available (from SMO DistributionPublisher object):
/// - PublisherSecurity: Security context for replication agents connecting to the Publisher
/// - RegisteredSubscribers: Collection of Subscribers registered for this Publisher's publications
/// - TransPublications: Collection of transactional publications at the Publisher
/// - ThirdParty: Boolean indicating if this is a non-SQL Server Publisher
/// - TrustedDistributorConnection: Boolean indicating if the distributor connection is trusted
/// - HeterogeneousLogReaderAgentExists: Boolean indicating if a Log Reader Agent job exists
/// - ConnectionContext: The connection context to the SQL Server instance
/// - IsExistingObject: Boolean indicating if the object exists on the server
/// </para>
/// </description>
/// </item>
/// </list>
/// <seealso href="https://dbatools.io/Get-DbaReplPublisher" />
[Cmdlet(VerbsCommon.Get, "DbaReplPublisher")]
[OutputType(typeof(DistributionPublisher))]
public sealed class GetDbaReplPublisherCommand : DbaInstanceCmdlet
{
    /// <para>
    /// The target SQL Server instance or instances.
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
            // PS: try { $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            //           $replServer = Get-DbaReplServer -SqlInstance $server -EnableException:$EnableException }
            //     catch { Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $server -Continue }
            Server server;
            Server? connected = null;
            ReplicationServer? replicationServer;
            try
            {
                // Upstream correction azure-unsupported: Azure SQL Database can only be a push subscriber and has no publishers
                // to read, so the connection refuses it as Connect-DbaInstance -AzureUnsupported does.
                server = NativeReplicationServer.Connect(instance, SqlCredential, azureUnsupported: true);
                connected = server;
                SetActiveConnection(server.ConnectionContext);
                replicationServer = NestedReplicationServer(server);
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch (Exception exception)
            {
                ErrorRecord caught = exception is NestedStopException nested
                    ? nested.Record
                    : NativeReplicationServer.NestedConnectFailure(instance, exception, CaughtNestedStopFunction)
                        ?? new ErrorRecord(exception, exception.GetType().Name, ErrorCategory.NotSpecified, null);
                // Upstream correction failure-target: the pin's $server still holds the previous instance's server (or nothing)
                // when this instance's connection fails; the record names this instance instead, and the connected server
                // when the connection succeeded and Get-DbaReplServer failed.
                StopFunction("Failure", target: (object?)connected ?? instance, errorRecord: caught, category: ErrorCategory.ConnectionError, continueLoop: true);
                continue;
            }

            // PS: Write-Message -Level Verbose -Message "Getting publisher for $server" - the SMO server expands to its bracketed name.
            WriteMessage(MessageLevel.Verbose, "Getting publisher for " + server);

            // PS: without EnableException a failed Get-DbaReplServer returns nothing; $null.DistributionPublishers is $null and
            // Select-DefaultView returns nothing for it.
            if (replicationServer is null)
                continue;

            // PS: try { $publisher = $replServer.DistributionPublishers } catch { Stop-Function -Message "Unable to get publisher for" -ErrorRecord $_ -Target $server -Continue }
            DistributionPublisherCollection publishers;
            try
            {
                publishers = replicationServer.DistributionPublishers;
            }
            catch (Exception failure) when (failure is not PipelineStoppedException)
            {
                // A failing getter reaches the pinned catch as the adapter's GetValueInvocationException.
                GetValueInvocationException fault = new(String.Format(CultureInfo.InvariantCulture,
                    "Exception getting \"DistributionPublishers\": \"{0}\"", failure.Message), failure);
                StopFunction("Unable to get publisher for", target: server,
                    errorRecord: new ErrorRecord(fault, "CatchFromBaseAdapterGetValue", ErrorCategory.NotSpecified, null), continueLoop: true);
                continue;
            }

            // PS: if ($publisher) { $publisher | Add-Member ComputerName, InstanceName, SqlInstance -Force }, then
            // Select-DefaultView -InputObject $publisher, which decorates and emits each publisher of the collection; for a
            // $null collection it emits nothing.
            if (publishers is null)
                continue;
            string? computerName = SmoServerExtensions.GetComputerName(server);
            string instanceName = server.ServiceName;
            string? sqlInstance = SmoServerExtensions.GetDomainInstanceName(server);
            foreach (object? item in (IEnumerable)publishers)
            {
                if (item is null)
                    continue;
                PSObject wrapped = PSObject.AsPSObject(item);
                ReplaceNoteProperty(wrapped, "ComputerName", computerName);
                ReplaceNoteProperty(wrapped, "InstanceName", instanceName);
                ReplaceNoteProperty(wrapped, "SqlInstance", sqlInstance);
                OutputHelper.SetDefaultDisplayPropertySet(wrapped,
                    "ComputerName", "InstanceName", "SqlInstance", "Status", "WorkingDirectory",
                    "DistributionDatabase", "DistributionPublications", "PublisherType", "Name");
                WriteObject(wrapped);
            }
        }
    }

    // PS: Get-DbaReplServer -SqlInstance $server -EnableException:$EnableException. It reuses the connected server and builds the
    // decorated ReplicationServer; its own catch is Stop-Function -Message "Failure" -Category ConnectionError -Target $instance
    // -Continue. Without EnableException that warns under its name and returns nothing; with it, the thrown record reaches this
    // command's catch as $_.
    private ReplicationServer? NestedReplicationServer(Server server)
    {
        try
        {
            return (ReplicationServer)NativeReplicationServer.Wrap(server).BaseObject;
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            DbaInstanceParameter nestedInstance = new((object)server);
            ErrorRecord record = new(failure, "dbatools_Get-DbaReplServer", ErrorCategory.NotSpecified, nestedInstance);
            if (EnableException.ToBool())
                throw new NestedStopException(CaughtNestedStopFunction("Get-DbaReplServer", "Failure", target: nestedInstance,
                    errorRecord: record, category: ErrorCategory.ConnectionError));
            StopAttributedFunction("Get-DbaReplServer", "Failure", target: nestedInstance, errorRecord: record,
                category: ErrorCategory.ConnectionError, continueLoop: true, interruptCallerScope: false);
            return null;
        }
    }

    private static void ReplaceNoteProperty(PSObject wrapped, string name, object? value)
    {
        PSPropertyInfo? existing = wrapped.Properties[name];
        if (existing is PSNoteProperty)
            wrapped.Properties.Remove(name);
        wrapped.Properties.Add(new PSNoteProperty(name, value));
    }

    // Carries the record a nested Stop-Function threw under EnableException to this command's catch.
    private sealed class NestedStopException : Exception
    {
        internal NestedStopException(ErrorRecord record)
            : base(record.Exception.Message, record.Exception)
        {
            Record = record;
        }

        internal ErrorRecord Record { get; }
    }
}
