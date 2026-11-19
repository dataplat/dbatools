#nullable enable

using System;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;
using Microsoft.SqlServer.Replication;

namespace Dataplat.Dbatools.Commands;

// Port of public/Get-DbaReplDistributor.ps1. Its nested Get-DbaReplServer call is the shared native replication
// connection (NativeReplicationServer), with that command's failure handling kept under its name.

/// <summary>Retrieves replication distributor configuration and status information from SQL Server instances.</summary>
/// <para>Connects to SQL Server instances and retrieves detailed information about their replication distributor configuration, including distributor status, distribution database details, and publisher relationships. This is essential for DBAs managing replication topologies who need to quickly identify which servers act as distributors, where the distribution database is located, and whether remote publishers are configured. The function returns comprehensive distributor properties that help with replication troubleshooting, topology documentation, and configuration audits.</para>
/// <example><code>PS C:\&gt; Get-DbaReplDistributor -SqlInstance sql2008, sqlserver2012</code>
/// <para>Retrieve distributor information for servers sql2008 and sqlserver2012.</para></example>
/// <example><code>PS C:\&gt; Connect-DbaInstance -SqlInstance mssql1 | Get-DbaReplDistributor</code>
/// <para>Pipe a SQL Server instance to Get-DbaReplDistributor to retrieve distributor information.</para></example>
/// <list type="alertSet"><item><term></term><description>
/// <para>Tags: Replication Author: William Durkin (@sql_williamd)</para>
/// <para>Website: https://dbatools.io Copyright: (c) 2018 by dbatools, licensed under MIT License: MIT https://opensource.org/licenses/MIT</para>
/// </description></item><item><term>OUTPUTS</term><description>
/// <para>Microsoft.SqlServer.Replication.ReplicationServer</para>
/// <para>Returns one ReplicationServer object per SQL Server instance with replication configuration and status information.</para>
/// <para>Default display properties: - ComputerName: The computer name of the SQL Server instance - InstanceName: The SQL Server instance name - SqlInstance: The full SQL Server instance name (computer\instance) - IsPublisher: Boolean indicating if the instance is configured as a replication publisher - IsDistributor: Boolean indicating if the instance is configured as a replication distributor - DistributionServer: The name of the server hosting the distribution database (null if not a distributor) - DistributionDatabase: The name of the distribution database (null if not a distributor) - DistributorInstalled: Boolean indicating if distributor components are installed on the instance - DistributorAvailable: Boolean indicating if the distributor is currently available and functional - HasRemotePublisher: Boolean indicating if the distributor has remote publishers configured</para>
/// <para>Additional properties available from the ReplicationServer object: - ReplicationDatabases: Collection of databases enabled for replication (not necessarily actively replicated) - DistributionDatabaseAvailable: Boolean indicating if the distribution database is accessible - HardwareBoundary: Indicates hardware boundary for replication - PublisherList: Collection of publishers using this distributor</para>
/// <para>Use Select-Object * to access all available properties from the ReplicationServer object.</para>
/// </description></item></list>
/// <seealso href="https://dbatools.io/Get-DbaReplDistributor" />
[Cmdlet(VerbsCommon.Get, "DbaReplDistributor")]
[OutputType(typeof(ReplicationServer))]
public sealed class GetDbaReplDistributorCommand : DbaInstanceCmdlet
{
    /// <para>The target SQL Server instance or instances to check for replication distributor configuration. Use this to identify which servers in your environment are configured as distributors, where the distribution database is located, and whether they support remote publishers.</para>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public override DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <para>Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).</para>
    /// <para>Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.</para>
    /// <para>For MFA support, please use Connect-DbaInstance.</para>
    [Parameter(Position = 1)]
    public override PSCredential? SqlCredential { get; set; }

    /// <para>By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message. This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting. Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.</para>
    [Parameter]
    public override SwitchParameter EnableException { get; set; }

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            WriteMessage(MessageLevel.Verbose, String.Format(CultureInfo.InvariantCulture, "Attempting to retrieve distributor information from {0}", instance));

            // PS: try { $distributor = Get-DbaReplServer -SqlInstance $instance -SqlCredential $SqlCredential -EnableException:$EnableException }
            //     catch { Stop-Function -Message "Error occurred getting information about $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue }
            PSObject? distributor = null;
            try
            {
                // Upstream correction azure-unsupported: Azure SQL Database can only be a push subscriber and has no
                // distributor to read, so the connection refuses it as Connect-DbaInstance -AzureUnsupported does.
                Server server = NativeReplicationServer.Connect(instance, SqlCredential, azureUnsupported: true);
                SetActiveConnection(server.ConnectionContext);
                distributor = NativeReplicationServer.Wrap(server);
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch (Exception exception)
            {
                // PS (Get-DbaReplServer): Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
                ErrorRecord caught = ConnectFailureRecord(instance, exception);
                if (EnableException.ToBool())
                {
                    // Get-DbaReplServer throws under the forwarded EnableException; this command's catch receives the
                    // thrown record as $_ and its own Stop-Function -Continue terminates under EnableException.
                    ErrorRecord thrown = CaughtNestedStopFunction("Get-DbaReplServer", "Failure", target: instance, errorRecord: caught,
                        category: ErrorCategory.ConnectionError);
                    StopFunction(String.Format(CultureInfo.InvariantCulture, "Error occurred getting information about {0}", instance),
                        target: instance, errorRecord: thrown, category: ErrorCategory.ConnectionError, continueLoop: true);
                    continue;
                }

                // Without EnableException Get-DbaReplServer warns, continues its own loop and returns nothing, so this
                // command goes on with a null $distributor.
                StopAttributedFunction("Get-DbaReplServer", "Failure", target: instance, errorRecord: caught,
                    category: ErrorCategory.ConnectionError, continueLoop: true, interruptCallerScope: false);
            }

            // PS: Write-Message -Level Verbose -Message "Getting publisher for $server" - $server is not defined in this
            // function's scope, so the message ends after "for ".
            WriteMessage(MessageLevel.Verbose, "Getting publisher for ");

            // PS: Select-DefaultView -InputObject $distributor -Property ... returns nothing for a null input.
            if (distributor is null)
                continue;

            OutputHelper.SetDefaultDisplayPropertySet(distributor, "ComputerName", "InstanceName", "SqlInstance", "IsPublisher", "IsDistributor", "DistributionServer", "DistributionDatabase", "DistributorInstalled", "DistributorAvailable", "HasRemotePublisher");
            WriteObject(distributor);
        }
    }

    // The record Get-DbaReplServer's catch receives as $_. Its Connect-DbaInstance forces its own EnableException on, so
    // a connection failure or refusal is that command's Stop-Function throw (warning logged without display, record in
    // $error); any other failure is the exception itself.
    private ErrorRecord ConnectFailureRecord(DbaInstanceParameter instance, Exception failure)
    {
        if (failure is not ConnectionResolutionException resolution)
            return new ErrorRecord(failure, "dbatools_Get-DbaReplServer", ErrorCategory.ConnectionError, instance);

        if (resolution.Kind == ConnectionResolutionFailure.ConnectFailure)
        {
            // PS: Stop-Function -Target $instance -Message "Failure" -Category ConnectionError -ErrorRecord $connectionError -Continue
            ErrorRecord connectionError = new(resolution.InnerException ?? resolution, "dbatools_Connect-DbaInstance", ErrorCategory.NotSpecified, instance);
            return CaughtNestedStopFunction("Connect-DbaInstance", "Failure", target: instance, errorRecord: connectionError,
                category: ErrorCategory.ConnectionError);
        }

        // PS: Stop-Function -Target $instance -Message "Azure SQL Database not supported" -Continue, and the other refusals
        return CaughtNestedStopFunction("Connect-DbaInstance", resolution.Message, target: instance);
    }
}
