#nullable enable

using System.Management.Automation;
using Dataplat.Dbatools.Parameter;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Resets SQL Server wait statistics to establish a clean monitoring baseline
/// </summary>
/// <para type="description">
/// Clears all accumulated wait statistics from sys.dm_os_wait_stats by executing DBCC SQLPERF (N'sys.dm_os_wait_stats', CLEAR). This is essential for performance troubleshooting when you need to establish a new baseline for wait analysis. DBAs commonly clear wait stats after resolving performance issues, during maintenance windows, or when beginning focused monitoring periods to isolate specific workload patterns without historical noise.
/// </para>
/// <example>
/// <code>PS C:\&gt; Clear-DbaWaitStatistics -SqlInstance sql2008, sqlserver2012</code>
/// <para>After confirmation, clears wait stats on servers sql2008 and sqlserver2012</para>
/// </example>
/// <example>
/// <code>PS C:\&gt; Clear-DbaWaitStatistics -SqlInstance sql2008, sqlserver2012 -Confirm:$false</code>
/// <para>Clears wait stats on servers sql2008 and sqlserver2012, without prompting</para>
/// </example>
/// <relatedLink><uri>https://dbatools.io/Clear-DbaWaitStatistics</uri></relatedLink>
[Cmdlet(VerbsCommon.Clear, "DbaWaitStatistics", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High)]
public sealed class ClearDbaWaitStatisticsCommand : DbaInstanceCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public override DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <para>Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).</para>
    /// <para>Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.</para>
    /// <para>For MFA support, please use Connect-DbaInstance.</para>
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
            CancellationToken.ThrowIfCancellationRequested();
            Server? server = ConnectInstance(instance, minimumVersion: 9);
            if (server is null) continue;

            if (ShouldProcess(instance.ToString(), "Performing CLEAR of sys.dm_os_wait_stats"))
                WriteObject(NativeStatisticsReset.Execute(server, "DBCC SQLPERF (N'sys.dm_os_wait_stats', CLEAR);"));
        }
    }
}
