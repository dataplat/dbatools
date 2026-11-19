#nullable enable

using System.Management.Automation;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

// Port of public/Get-DbaErrorLogConfig.ps1 at refs/pins/dbatools-2026-10-22: the connection, and the count, size and path of the error logs
// of each instance. Measured: evidence/pin-errorlogconfig-20261104.txt.
/// <summary>Retrieves SQL Server error log configuration settings including file count, size limits, and storage location</summary>
/// <para>
/// Retrieves current error log configuration from SQL Server instances, showing how many log files are retained, where they're stored, and size limits if configured. This information helps DBAs understand log retention policies and troubleshoot logging issues without connecting to SQL Server Management Studio. Log size information is only available on SQL Server 2012 and later versions.
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaErrorLogConfig -SqlInstance server2017,server2014
/// </code>
/// <para>
/// Returns error log configuration for server2017 and server2014
/// </para>
/// </example>
/// <list type="alertSet">
/// <item>
/// <term />
/// <description>
/// <para>
/// Tags: Instance, ErrorLog, Logging
/// Author: Shawn Melton (@wsmelton), wsmelton.github.io
/// </para>
/// <para>
/// Website: https://dbatools.io
/// Copyright: (c) 2018 by dbatools, licensed under MIT
/// License: MIT https://opensource.org/licenses/MIT
/// </para>
/// </description>
/// </item>
/// </list>
/// <seealso href="https://dbatools.io/Get-DbaErrorLogConfig" />
[Cmdlet(VerbsCommon.Get, "DbaErrorLogConfig")]
public sealed class GetDbaErrorLogConfigCommand : DbaInstanceCmdlet
{
    /// <para>
    /// The target SQL Server instance or instances
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

    // Overridden only to carry the pinned .PARAMETER EnableException help; same bare [Parameter] as the base.
    /// <para>
    /// By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
    /// This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
    /// Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.
    /// </para>
    [Parameter]
    public override SwitchParameter EnableException { get; set; }

    /// <summary>Reports the error log configuration of each instance in this record.</summary>
    protected override void ProcessRecord()
    {
        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            // Azure SQL Database has no instance error log; the pin returned a row of nulls there, the port refuses it as -AzureUnsupported does
            // (correction azure-errorlog-refusal).
            Server? server = ConnectInstance(instance, azureUnsupported: true);
            if (server is null)
                continue;

            object? logCount = Member(server, "NumberOfLogFiles");
            object? logSize = null;
            if (server.VersionMajor >= 11)
            {
                object? logSizeKb = Member(server, "ErrorLogSizeKb");
                if (logSizeKb is not null)
                    logSize = new Size(LanguagePrimitives.ConvertTo<long>(logSizeKb) * 1024);
            }

            PSObject output = new PSObject();
            OutputHelper.AddInstanceProperties(output, server);
            output.Properties.Add(new PSNoteProperty("LogCount", logCount));
            output.Properties.Add(new PSNoteProperty("LogSize", logSize));
            output.Properties.Add(new PSNoteProperty("LogPath", Member(server, "ErrorLogPath")));
            WriteObject(output);
        }
    }

    // The pin's $server.name, where a failed read gives nothing. A login with no rights reads them all.
    private static object? Member(Server server, string name)
    {
        try
        {
            return PSObject.AsPSObject(server).Properties[name]?.Value;
        }
        catch (GetValueException)
        {
            return null;
        }
    }
}
