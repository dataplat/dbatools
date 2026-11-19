#nullable enable

using System;
using System.Data;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Retrieves SQL Server Agent error log entries for troubleshooting and monitoring
/// </summary>
/// <para>
/// Retrieves SQL Server Agent error log entries from the target instance, providing detailed information about agent service activity, job failures, and system events. This function accesses the agent's historical error logs (numbered 0-9, where 0 is the current log) so you don't have to manually navigate through SQL Server Management Studio or query system views. Essential for troubleshooting job failures, monitoring agent service health, and compliance auditing of automated processes.
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaAgentLog -SqlInstance sql01\sharepoint
/// </code>
/// <para>
/// Returns the entire error log for the SQL Agent on sql01\sharepoint
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaAgentLog -SqlInstance sql01\sharepoint -LogNumber 3, 6
/// </code>
/// <para>
/// Returns log numbers 3 and 6 for the SQL Agent on sql01\sharepoint
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; $servers = "sql2014","sql2016", "sqlcluster\sharepoint"
/// PS C:\&gt; $servers | Get-DbaAgentLog -LogNumber 0
/// </code>
/// <para>
/// Returns the most recent SQL Agent error logs for "sql2014","sql2016" and "sqlcluster\sharepoint"
/// </para>
/// </example>
/// <list type="alertSet">
/// <item>
/// <term />
/// <description>
/// <para>
/// Tags: Agent
/// Author: Chrissy LeMaire (@cl), netnerds.net
/// </para>
/// <para>
/// Website: https://dbatools.io
/// Copyright: (c) 2018 by dbatools, licensed under MIT
/// License: MIT https://opensource.org/licenses/MIT
/// </para>
/// </description>
/// </item>
/// </list>
/// <seealso href="https://dbatools.io/Get-DbaAgentLog" />
[Cmdlet(VerbsCommon.Get, "DbaAgentLog")]
[OutputType(typeof(DataRow))]
public sealed class GetDbaAgentLogCommand : DbaInstanceCmdlet
{
    /// <para>
    /// The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.
    /// </para>
    [Parameter(ValueFromPipeline = true, Position = 0)]
    [PsDbaInstanceArrayCast]
    public override DbaInstanceParameter[] SqlInstance { get; set; } = Array.Empty<DbaInstanceParameter>();

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
    /// Specifies which numbered agent error log files to retrieve (0-9). Log 0 contains the most recent entries, while higher numbers contain older historical logs that get cycled as new logs are created.
    /// Use this when you need to examine historical agent activity or troubleshoot issues that occurred days or weeks ago, rather than just current entries.
    /// </para>
    [Parameter(Position = 2)]
    [PsAgentLogIntArrayCast]
    [ValidateRange(0, 9)]
    public int[]? LogNumber { get; set; }

    /// <para>
    /// By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
    /// This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
    /// Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.
    /// </para>
    [Parameter]
    public override SwitchParameter EnableException { get; set; }

    protected override void ProcessRecord()
    {
        if (Interrupted)
            return;

        foreach (DbaInstanceParameter instance in SqlInstance ?? Array.Empty<DbaInstanceParameter>())
        {
            if (Interrupted)
                return;
            Server? server = ConnectInstance(instance, azureUnsupported: true);
            if (server is null)
                continue;

            if (LanguagePrimitives.IsTrue(LogNumber))
            {
                foreach (int number in LogNumber!)
                    WriteLog(server, number);
            }
            else
                WriteLog(server, null);
        }
    }

    private void WriteLog(Server server, int? number)
    {
        try
        {
            DataTable entries = number.HasValue
                ? server.JobServer.ReadErrorLog(number.Value)
                : server.JobServer.ReadErrorLog();
            foreach (DataRow entry in entries.Rows)
            {
                WriteMessage(MessageLevel.Verbose, String.Format("Processing {0}", entry));
                PSObject output = PSObject.AsPSObject(entry);
                foreach (string name in new[] { "ComputerName", "InstanceName", "SqlInstance" })
                    output.Properties.Remove(name);
                OutputHelper.AddInstanceProperties(output, server);
                OutputHelper.SetDefaultDisplayPropertySet(output,
                    "ComputerName", "InstanceName", "SqlInstance", "LogDate", "ProcessInfo", "Text");
                WriteObject(output);
            }
        }
        catch (Exception ex) when (ex is not PipelineStoppedException)
        {
            // The pinned catch supplies a plain message, not the underlying SMO error record.
            StopFunction("Could not read from SQL Server Agent", target: server, continueLoop: true);
        }
    }
}

/// <summary>Reproduces the advanced function's typed Int32 array conversion before validation.</summary>
internal sealed class PsAgentLogIntArrayCastAttribute : ArgumentTransformationAttribute
{
    public override object? Transform(EngineIntrinsics engineIntrinsics, object? inputData)
    {
        if (inputData is null)
            return null;
        try
        {
            return LanguagePrimitives.ConvertTo(inputData, typeof(int[]), CultureInfo.InvariantCulture);
        }
        catch (PSInvalidCastException ex)
        {
            throw new ArgumentTransformationMetadataException(ex.Message, ex);
        }
    }
}
