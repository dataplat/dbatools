#nullable enable

using System;
using System.Management.Automation;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Microsoft.SqlServer.Management.Smo;
using Microsoft.SqlServer.Replication;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Configures a SQL Server instance as a replication distributor with distribution database
/// </summary>
[Cmdlet(VerbsLifecycle.Enable, "DbaReplDistributor", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
public sealed class EnableDbaReplDistributorCommand : DbaBaseCmdlet
{
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    [Parameter(Position = 2)]
    public string DistributionDatabase { get; set; } = "distribution";

    protected override void ProcessRecord()
    {
        if (SqlInstance is null)
            return;
        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            PSObject? wrapped = null;
            try
            {
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
                // The pinned nested Get-DbaReplServer forwards EnableException; its failure is outside the install catch.
                StopAttributedFunction("Get-DbaReplServer", "Failure", target: instance,
                    errorRecord: new ErrorRecord(exception, "dbatools_Get-DbaReplServer", ErrorCategory.ConnectionError, instance),
                    category: ErrorCategory.ConnectionError, continueLoop: true, interruptCallerScope: false);
            }

            WriteMessage(MessageLevel.Verbose, String.Format("Enabling replication distribution for {0}", instance));
            try
            {
                if (ShouldProcess(instance.ToString(), String.Format("Enabling distributor for {0}", instance)))
                {
                    ReplicationServer? replicationServer = wrapped?.BaseObject as ReplicationServer;
                    DistributionDatabase database = new();
                    database.ConnectionContext = replicationServer?.ConnectionContext;
                    database.Name = DistributionDatabase;
                    if (replicationServer is null)
                        throw new RuntimeException("You cannot call a method on a null-valued expression.");
                    replicationServer.InstallDistributor((string)null!, database);
                    replicationServer.Refresh();
                    WriteObject(wrapped);
                }
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch (Exception exception)
            {
                StopFunction("Unable to enable replication distributor", target: instance,
                    errorRecord: new ErrorRecord(exception, exception.GetType().Name, ErrorCategory.NotSpecified, instance),
                    continueLoop: true);
                continue;
            }
        }
    }
}
