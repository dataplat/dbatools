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
/// Enables one or more trace flags globally on SQL Server instances
/// </summary>
/// <para>
/// Activates trace flags at the global level using DBCC TRACEON, affecting all connections and sessions on the target SQL Server instances.
/// Commonly used for troubleshooting performance issues, enabling specific SQL Server behaviors, or applying recommended trace flags for your environment.
/// Changes take effect immediately but are lost after a SQL Server restart - use Set-DbaStartupParameter to make trace flags persistent across restarts.
/// The function automatically checks for already-enabled trace flags to prevent duplicate operations.
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Enable-DbaTraceFlag -SqlInstance sql2016 -TraceFlag 3226
/// </code>
/// <para>
/// Enable the trace flag 3226 on SQL Server instance sql2016
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Enable-DbaTraceFlag -SqlInstance sql2016 -TraceFlag 1117, 1118
/// </code>
/// <para>
/// Enable multiple trace flags on SQL Server instance sql2016
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
/// <seealso href="https://dbatools.io/Enable-DbaTraceFlag" />
[Cmdlet(VerbsLifecycle.Enable, "DbaTraceFlag", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Low)]
public sealed class EnableDbaTraceFlagCommand : DbaInstanceCmdlet
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
    /// Specifies one or more trace flag numbers to enable globally across all sessions on the SQL Server instance.
    /// Use specific trace flag numbers like 3226 (suppress backup log messages), 1117/1118 (tempdb optimization), or 4199 (query optimizer fixes).
    /// Multiple trace flags can be specified as an array to enable several flags in a single operation.
    /// </para>
    [Parameter(Mandatory = true, Position = 2)]
    public int[]? TraceFlag { get; set; }

    /// <para>
    /// By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
    /// This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
    /// Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.
    /// </para>
    [Parameter]
    public override SwitchParameter EnableException { get; set; }

    protected override void ProcessRecord()
    {
        if (Interrupted || SqlInstance is null)
            return;

        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            Server? server = ConnectInstance(instance, azureUnsupported: true);
            if (server is null)
                continue;

            HashSet<int> running = new();
            try
            {
                using DataTable flags = server.EnumActiveGlobalTraceFlags();
                foreach (DataRow flag in flags.Rows)
                    running.Add(Convert.ToInt32(flag["TraceFlag"], CultureInfo.InvariantCulture));
                if (flags.Rows.Count == 0)
                    WriteAttributedMessage("Get-DbaTraceFlag", MessageLevel.Verbose, "No global trace flags enabled");
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch (Exception ex)
            {
                ErrorRecord record = new(MethodFault("EnumActiveGlobalTraceFlags", ex), ex.GetType().Name, ErrorCategory.NotSpecified, null);
                if (EnableException)
                {
                    // caller-try: terminate -- -EnableException stops at the failed active-flag read.
                    ThrowTerminatingError(record); // style-ok: cs-raw-streams preserve the method fault requested by the caller
                }
                StatementFault.Surface(this, record);
                // active-flag-read-guard: skip this server. A Failed result from TRACEON would describe a call we did not make.
                continue;
            }

            foreach (int flag in TraceFlag ?? Array.Empty<int>())
            {
                PSObject output = new();
                output.Properties.Add(new PSNoteProperty("SourceServer", SmoServerExtensions.GetComputerName(server)));
                output.Properties.Add(new PSNoteProperty("InstanceName", server.ServiceName)); // style-ok: cs-output-props pinned output uses SourceServer and has no default display set
                output.Properties.Add(new PSNoteProperty("SqlInstance", SmoServerExtensions.GetDomainInstanceName(server))); // style-ok: cs-output-props pinned output uses SourceServer and has no default display set
                output.Properties.Add(new PSNoteProperty("TraceFlag", flag));
                output.Properties.Add(new PSNoteProperty("Status", null));
                output.Properties.Add(new PSNoteProperty("Notes", null));
                output.Properties.Add(new PSNoteProperty("DateTime", new DbaDateTime(DateTime.Now)));

                if (running.Contains(flag))
                {
                    output.Properties["Status"].Value = "Skipped";
                    output.Properties["Notes"].Value = "The Trace flag is already running.";
                    WriteObject(output);
                    WriteMessage(MessageLevel.Warning, String.Format("The Trace flag [{0}] is already running globally.", flag));
                    continue;
                }
                if (!ShouldProcess(instance.ToString(), String.Format("Enabling flag '{0}'", flag)))
                    continue;

                try
                {
                    string query = String.Format(CultureInfo.InvariantCulture, "DBCC TRACEON({0}, -1)", flag);
                    try
                    {
                        using DataSet ignored = server.ConnectionContext.ExecuteWithResults(query);
                    }
                    catch (PipelineStoppedException)
                    {
                        throw;
                    }
                    catch (Exception ex)
                    {
                        throw NativeServerQuery.QueryMethodException(ex);
                    }
                    try
                    {
                        server.Refresh();
                    }
                    catch (PipelineStoppedException)
                    {
                        throw;
                    }
                    catch (Exception ex)
                    {
                        throw MethodFault("Refresh", ex);
                    }
                }
                catch (PipelineStoppedException)
                {
                    throw;
                }
                catch (Exception ex)
                {
                    output.Properties["Status"].Value = "Failed";
                    output.Properties["Notes"].Value = ex.Message;
                    WriteObject(output);
                    StopFunction("Failure", target: server,
                        errorRecord: new ErrorRecord(ex, ex.GetType().Name, ErrorCategory.NotSpecified, null), continueLoop: true);
                    continue;
                }
                output.Properties["Status"].Value = "Successful";
                WriteObject(output);
            }
        }
    }

    private static MethodInvocationException MethodFault(string method, Exception failure)
    {
        return new MethodInvocationException(String.Format(CultureInfo.InvariantCulture,
            "Exception calling \"{0}\" with \"0\" argument(s): \"{1}\"", method, failure.Message), failure);
    }
}
