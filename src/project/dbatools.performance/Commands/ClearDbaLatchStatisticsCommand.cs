#nullable enable

using System.Management.Automation;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Resets SQL Server latch statistics counters to establish a fresh performance baseline
/// </summary>
[Cmdlet(VerbsCommon.Clear, "DbaLatchStatistics", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High)]
public sealed class ClearDbaLatchStatisticsCommand : DbaInstanceCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public override DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public override PSCredential? SqlCredential { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    protected override void ProcessRecord()
    {
        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            CancellationToken.ThrowIfCancellationRequested();
            WriteMessage(MessageLevel.Verbose, "Attempting to connect to " + PsText(instance));
            Server? server = ConnectInstance(instance, minimumVersion: 9);
            if (server is null)
                continue;

            if (ShouldProcess(PsText(instance), "Performing CLEAR of sys.dm_os_latch_stats"))
            {
                WriteObject(NativeStatisticsReset.Execute(server, "DBCC SQLPERF (N'sys.dm_os_latch_stats', CLEAR);"));
            }
        }
    }

    /// <summary>PS string interpolation of a value ("$instance").</summary>
    private static string PsText(object? value)
    {
        if (value is null)
            return "";
        return PSObject.AsPSObject(value).ToString();
    }
}
