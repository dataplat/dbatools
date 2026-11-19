#nullable enable

using System;
using System.Collections.Generic;
using System.Data;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Disables globally running trace flags on SQL Server instances
/// </summary>
/// <para>
/// Turns off trace flags that are currently enabled globally across SQL Server instances using DBCC TRACEOFF.
/// Useful when you need to disable diagnostic trace flags that were enabled for troubleshooting or testing without requiring a restart.
/// Only affects flags currently running in memory - does not modify startup parameters or persistent trace flag settings.
/// Use Set-DbaStartupParameter to manage trace flags that persist after restarts.
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Disable-DbaTraceFlag -SqlInstance sql2016 -TraceFlag 3226
/// </code>
/// <para>
/// Disable the globally running trace flag 3226 on SQL Server instance sql2016
/// </para>
/// </example>
/// <list type="alertSet">
/// <item>
/// <term />
/// <description>
/// <para>
/// Tags: Diagnostic, TraceFlag, DBCC
/// Author: Garry Bargsley (@gbargsley), blog.garrybargsley.com
/// </para>
/// <para>
/// Website: https://dbatools.io
/// Copyright: (c) 2018 by dbatools, licensed under MIT
/// License: MIT https://opensource.org/licenses/MIT
/// </para>
/// </description>
/// </item>
/// </list>
/// <seealso href="https://dbatools.io/Disable-DbaTraceFlag" />
[Cmdlet(VerbsLifecycle.Disable, "DbaTraceFlag", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Low)]
public sealed class DisableDbaTraceFlagCommand : DbaInstanceCmdlet
{
    /// <para>
    /// The target SQL Server instance or instances.
    /// </para>
    [Parameter(Mandatory = true, Position = 0, ValueFromPipeline = true)]
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
    /// Specifies the trace flag numbers to disable globally across all sessions on the SQL Server instance.
    /// Only trace flags that are currently running will be disabled - flags not currently active are skipped with a warning.
    /// Supports multiple trace flag numbers to disable several flags in a single operation.
    /// </para>
    [Parameter(Mandatory = true, Position = 2)]
    public int[] TraceFlag { get; set; } = null!;

    /// <para>
    /// By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
    /// This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
    /// Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.
    /// </para>
    [Parameter]
    public override SwitchParameter EnableException { get; set; }

    protected override void ProcessRecord()
    {
        if (Interrupted) return;
        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            Server? server = ConnectInstance(instance, "Failure", azureUnsupported: true);
            if (server is null) continue;

            DataTable active = server.EnumActiveGlobalTraceFlags();
            HashSet<int> flags = new();
            foreach (DataRow row in active.Rows)
                flags.Add(Convert.ToInt32(row["TraceFlag"], CultureInfo.InvariantCulture));
            if (flags.Count == 0)
                WriteAttributedMessage("Get-DbaTraceFlag", MessageLevel.Verbose, "No global trace flags enabled");

            // The pin takes one snapshot per instance, retaining request order and duplicate flags.
            foreach (int flag in TraceFlag)
            {
                PSObject result = new();
                result.Properties.Add(new PSNoteProperty("SourceServer", SmoServerExtensions.GetComputerName(server)));
                OutputHelper.AddInstanceProperties(result, server);
                result.Properties.Remove("ComputerName");
                result.Properties.Add(new PSNoteProperty("TraceFlag", flag));
                result.Properties.Add(new PSNoteProperty("Status", null));
                result.Properties.Add(new PSNoteProperty("Notes", null));
                result.Properties.Add(new PSNoteProperty("DateTime", new DbaDateTime(DateTime.Now)));

                if (!flags.Contains(flag))
                {
                    result.Properties["Status"].Value = "Skipped";
                    result.Properties["Notes"].Value = "Trace Flag is not running.";
                    WriteObject(result);
                    WriteMessage(MessageLevel.Warning, String.Format(CultureInfo.CurrentCulture,
                        "Trace Flag {0} is not currently running on {1}", flag, instance));
                    continue;
                }
                if (!ShouldProcess(instance.ToString(), String.Format(CultureInfo.CurrentCulture, "Disabling flag '{0}'", flag)))
                    continue;

                try
                {
                    // Only a bound Int32 enters this DBCC grammar; DBCC does not accept a parameter here.
                    string query = String.Format(CultureInfo.InvariantCulture, "DBCC TRACEOFF ({0}, -1)", flag);
                    server.ConnectionContext.ExecuteWithResults(query);
                }
                catch (Exception ex)
                {
                    // Server.Query concatenates its native exception chain, then the script-method call wraps it.
                    string detail = String.Empty;
                    for (Exception? failure = ex; failure is not null; failure = failure.InnerException)
                        detail += failure.Message;
                    MethodInvocationException call = new(String.Format(CultureInfo.CurrentCulture,
                        "Exception calling \"Query\" with \"1\" argument(s): \"{0}\"", detail), new RuntimeException(detail, ex));
                    ErrorRecord record = new(call, "ScriptMethodRuntimeException", ErrorCategory.NotSpecified, null);
                    result.Properties["Status"].Value = "Failed";
                    result.Properties["Notes"].Value = call.Message;
                    WriteObject(result);
                    StopFunction("Failure", errorRecord: record, target: server, continueLoop: true);
                    continue;
                }
                result.Properties["Status"].Value = "Successful";
                WriteObject(result);
            }
        }
    }
}
