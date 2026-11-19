#nullable enable

using System.Management.Automation;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Retrieves SQL Server max memory configuration and compares it to total physical server memory.
/// Port of public/Get-DbaMaxMemory.ps1; surface pinned by migration/baselines/Get-DbaMaxMemory.json.
/// </summary>
[Cmdlet(VerbsCommon.Get, "DbaMaxMemory")]
[OutputType(typeof(PSObject))]
public sealed class GetDbaMaxMemoryCommand : DbaInstanceCmdlet
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
        if (Interrupted)
        {
            return;
        }

        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            // PS: try { Connect-DbaInstance } catch { Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue }
            Server? server = ConnectInstance(instance, "Failure");
            if (server is null)
            {
                continue;
            }

            int totalMemory = server.PhysicalMemory;

            // Some servers under-report by 1.
            if ((totalMemory % 1024) != 0)
            {
                totalMemory = totalMemory + 1;
            }

            PSObject result = new();
            OutputHelper.AddInstanceProperties(result, server);
            result.Properties.Add(new PSNoteProperty("Total", totalMemory));
            result.Properties.Add(new PSNoteProperty("MaxValue", server.Configuration.MaxServerMemory.ConfigValue));
            // This will allowing piping a non-connected object
            result.Properties.Add(new PSNoteProperty("Server", server));

            // PS: Select-DefaultView -Property ComputerName, InstanceName, SqlInstance, Total, MaxValue
            OutputHelper.SetDefaultDisplayPropertySet(result,
                "ComputerName", "InstanceName", "SqlInstance", "Total", "MaxValue");

            WriteObject(result);
        }
    }
}
