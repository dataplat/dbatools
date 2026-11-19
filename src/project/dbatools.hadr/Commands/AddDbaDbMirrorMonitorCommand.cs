#nullable enable

using System;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

/// <summary>Creates a database mirroring monitor job that periodically updates the mirroring status for every mirrored database on the server instance.</summary>
[Cmdlet(VerbsCommon.Add, "DbaDbMirrorMonitor", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Low)]
public sealed class AddDbaDbMirrorMonitorCommand : DbaInstanceCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public override DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Login to the target instances using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public override PSCredential? SqlCredential { get; set; }

    protected override void ProcessRecord()
    {
        if (Interrupted)
            return;

        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            Server? server = ConnectInstance(instance, minimumVersion: 9, azureUnsupported: true);
            if (server is null || !ShouldProcess(instance.ToString(), "add mirror monitoring"))
                continue;
            try
            {
                server.ConnectionContext.ExecuteNonQuery("EXEC msdb.dbo.sp_dbmmonitoraddmonitoring");
                PSObject output = new();
                OutputHelper.AddInstanceProperties(output, server);
                output.Properties.Add(new PSNoteProperty("MonitorStatus", "Added"));
                WriteObject(output);
            }
            catch (PipelineStoppedException) { throw; }
            catch (Exception exception)
            {
                // Server.Query concatenates its SQL exception chain before the source catch sees it.
                string message = string.Empty;
                for (Exception? error = exception; error is not null; error = error.InnerException)
                    message += error.Message;
                MethodInvocationException queryError = new(string.Format(
                    "Exception calling \"Query\" with \"1\" argument(s): \"{0}\"", message), new RuntimeException(message));
                StopFunction("Failure", errorRecord: new ErrorRecord(queryError, "ScriptMethodRuntimeException", ErrorCategory.NotSpecified, null), continueLoop: true);
            }
        }
    }
}
