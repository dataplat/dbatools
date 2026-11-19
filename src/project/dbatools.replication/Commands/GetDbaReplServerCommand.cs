#nullable enable

using System;
using System.Management.Automation;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Parameter;
using Microsoft.SqlServer.Management.Smo;
using Microsoft.SqlServer.Replication;

namespace Dataplat.Dbatools.Commands;

// Port of public/Get-DbaReplServer.ps1. Its Connect-DbaInstance call and the decorated ReplicationServer are the shared native
// replication connection (NativeReplicationServer); the begin block's Add-ReplicationLibrary is the compile-time RMO reference.

/// <summary>
/// Retrieves replication configuration and server role information from SQL Server instances
/// </summary>
/// <para>
/// Returns a ReplicationServer object that shows whether each SQL Server instance is configured as a distributor, publisher, or both in the replication topology. This helps DBAs quickly identify server roles and distribution database configurations when troubleshooting replication issues or documenting replication environments. The function reveals which databases are enabled for replication, though these may not necessarily be actively replicated.
/// </para>
/// <para>
/// Note: The ReplicationDatabases property gets the databases enabled for replication in the connected instance of Microsoft SQL Server/.
/// Not necessarily the databases that are actually replicated.
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaReplServer -SqlInstance sql2016
/// </code>
/// <para>
/// Gets the replication server object for sql2016 using Windows authentication
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaReplServer -SqlInstance sql2016 -SqlCredential repadmin
/// </code>
/// <para>
/// Gets the replication server object for sql2016 using SQL authentication
/// </para>
/// </example>
/// <list type="alertSet">
/// <item>
/// <term />
/// <description>
/// <para>
/// Tags: Replication
/// Author: Chrissy LeMaire (@cl), netnerds.net
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
/// Microsoft.SqlServer.Replication.ReplicationServer
/// </para>
/// <para>
/// Returns one ReplicationServer object per SQL Server instance, providing information about the instance's role in the replication topology.
/// </para>
/// <para>
/// Default display properties (via Select-DefaultView):
/// - ComputerName: The computer name of the SQL Server instance
/// - InstanceName: The SQL Server instance name
/// - SqlInstance: The full SQL Server instance name (computer\instance)
/// - IsDistributor: Boolean indicating if the instance is configured as a Distributor
/// - IsPublisher: Boolean indicating if the instance is configured as a Publisher
/// - DistributionServer: The name of the Distributor server (if configured)
/// - DistributionDatabase: The name of the distribution database (if configured)
/// </para>
/// <para>
/// Additional properties available (from SMO ReplicationServer object):
/// - DistributorInstalled: Boolean indicating if a Distributor is installed
/// - DistributorAvailable: Boolean indicating if the Distributor is accessible
/// - WorkingDirectory: The Publisher's working directory location
/// - DistributionDatabases: Collection of configured distribution databases
/// - DistributionPublishers: Collection of Publishers using this Distributor
/// - ReplicationDatabases: Collection of databases enabled for replication
/// - RegisteredSubscribers: Collection of registered Subscriber instances
/// - AgentCheckupInterval: The Distribution Agent checkup frequency setting
/// - ConnectionContext: The SQL Server connection context object
/// </para>
/// <para>
/// All properties from the base SMO ReplicationServer object are accessible using Select-Object *.
/// </para>
/// </description>
/// </item>
/// </list>
/// <seealso href="https://dbatools.io/Get-DbaReplServer" />
[Cmdlet(VerbsCommon.Get, "DbaReplServer")]
[OutputType(typeof(ReplicationServer))]
public sealed class GetDbaReplServerCommand : DbaInstanceCmdlet
{
    /// <para>
    /// The target SQL Server instance or instances
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
        // PS: if (Test-FunctionInterrupt) { return }
        if (Interrupted)
            return;

        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            // PS: try { $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            //           $replServer = New-Object Microsoft.SqlServer.Replication.ReplicationServer
            //           $replServer.ConnectionContext = $Server.ConnectionContext
            //           $replServer | Add-Member ComputerName, InstanceName, SqlInstance -Force
            //           Select-DefaultView -InputObject $replServer -Property ComputerName, InstanceName, SqlInstance, IsDistributor, ... }
            //     catch { Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue }
            PSObject wrapped;
            try
            {
                // Upstream correction azure-unsupported: Azure SQL Database can only be a push subscriber and replication is
                // managed from SQL Server, so the connection refuses it as Connect-DbaInstance -AzureUnsupported does.
                Server server = NativeReplicationServer.Connect(instance, SqlCredential, azureUnsupported: true);
                SetActiveConnection(server.ConnectionContext);
                wrapped = NativeReplicationServer.Wrap(server);
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch (Exception exception)
            {
                // $_ is the record Connect-DbaInstance threw (it forces its own EnableException on), or the failure itself.
                ErrorRecord caught = NativeReplicationServer.NestedConnectFailure(instance, exception, CaughtNestedStopFunction)
                    ?? new ErrorRecord(exception, exception.GetType().Name, ErrorCategory.NotSpecified, null);
                StopFunction("Failure", target: instance, errorRecord: caught, category: ErrorCategory.ConnectionError, continueLoop: true);
                continue;
            }

            WriteObject(wrapped);
        }
    }
}
