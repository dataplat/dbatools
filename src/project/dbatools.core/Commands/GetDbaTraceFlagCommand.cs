#nullable enable

using System;
using System.Data;
using System.Management.Automation;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Retrieves active global trace flags from SQL Server instances.
/// Port of public/Get-DbaTraceFlag.ps1; surface pinned by migration/baselines/Get-DbaTraceFlag.json.
/// </summary>
[Cmdlet(VerbsCommon.Get, "DbaTraceFlag")]
[OutputType(typeof(PSObject))]
public sealed class GetDbaTraceFlagCommand : DbaInstanceCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public override DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public override PSCredential? SqlCredential { get; set; }

    /// <summary>Filters results to only the specified trace flag numbers.</summary>
    [Parameter(Position = 2)]
    public int[]? TraceFlag { get; set; }

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

            DataTable tflags = server.EnumActiveGlobalTraceFlags();

            if (tflags.Rows.Count == 0)
            {
                WriteMessage(MessageLevel.Verbose, "No global trace flags enabled");
                continue;
            }

            foreach (DataRow tflag in tflags.Rows)
            {
                // PS: if ($TraceFlag) { $tflags = $tflags | Where-Object TraceFlag -In $TraceFlag }
                if (FilterHelper.IsActive(TraceFlag))
                {
                    int flagNumber = Convert.ToInt32(tflag["TraceFlag"]);
                    bool matched = false;
                    foreach (int wanted in TraceFlag!)
                    {
                        if (wanted == flagNumber)
                        {
                            matched = true;
                            break;
                        }
                    }
                    if (!matched)
                    {
                        continue;
                    }
                }

                PSObject result = new();
                OutputHelper.AddInstanceProperties(result, server);
                result.Properties.Add(new PSNoteProperty("TraceFlag", tflag["TraceFlag"]));
                result.Properties.Add(new PSNoteProperty("Global", tflag["Global"]));
                result.Properties.Add(new PSNoteProperty("Session", tflag["Session"]));
                result.Properties.Add(new PSNoteProperty("Status", tflag["Status"]));

                // PS: Select-DefaultView -ExcludeProperty 'Session'
                OutputHelper.SetDefaultDisplayPropertySetExcluding(result, new[] { "Session" });

                WriteObject(result);
            }
        }
    }
}
