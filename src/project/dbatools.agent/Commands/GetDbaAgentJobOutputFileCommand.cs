#nullable enable

using System;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;
using Microsoft.SqlServer.Management.Smo.Agent;
using AgentJob = Microsoft.SqlServer.Management.Smo.Agent.Job;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Retrieves output file paths configured for SQL Agent job steps
/// </summary>
/// <para>
/// This function returns the file paths where SQL Agent job steps write their output logs. When troubleshooting failed jobs or reviewing execution history, DBAs often need to locate these output files to examine detailed error messages and execution details. The function returns both the local file path and the UNC path for remote access, but only displays job steps that have an output file configured.
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaAgentJobOutputFile -SqlInstance SERVERNAME -Job 'The Agent Job'
/// </code>
/// <para>
/// This will return the configured paths to the output files for each of the job step of the The Agent Job Job
/// on the SERVERNAME instance
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaAgentJobOutputFile -SqlInstance SERVERNAME
/// </code>
/// <para>
/// This will return the configured paths to the output files for each of the job step of all the Agent Jobs
/// on the SERVERNAME instance
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaAgentJobOutputFile -SqlInstance SERVERNAME,SERVERNAME2 -Job 'The Agent Job'
/// </code>
/// <para>
/// This will return the configured paths to the output files for each of the job step of the The Agent Job Job
/// on the SERVERNAME instance and SERVERNAME2
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaAgentJobOutputFile -SqlInstance SERVERNAME  | Out-GridView
/// </code>
/// <para>
/// This will return the configured paths to the output files for each of the job step of all the Agent Jobs
/// on the SERVERNAME instance and Pipe them to Out-GridView
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaAgentJobOutputFile -SqlInstance SERVERNAME -Verbose
/// </code>
/// <para>
/// This will return the configured paths to the output files for each of the job step of all the Agent Jobs
/// on the SERVERNAME instance and also show the job steps without an output file
/// </para>
/// </example>
/// <list type="alertSet">
/// <item>
/// <term />
/// <description>
/// <para>
/// Tags: Agent, Job
/// Author: Rob Sewell (sqldbawithabeard.com) | Simone Bizzotto (@niphlod)
/// </para>
/// <para>
/// Website: https://dbatools.io
/// Copyright: (c) 2018 by dbatools, licensed under MIT
/// License: MIT https://opensource.org/licenses/MIT
/// </para>
/// </description>
/// </item>
/// </list>
/// <seealso href="https://dbatools.io/Get-DbaAgentJobOutputFile" />
[Cmdlet(VerbsCommon.Get, "DbaAgentJobOutputFile")]
public sealed class GetDbaAgentJobOutputFileCommand : DbaInstanceCmdlet
{
    /// <para>
    /// The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.
    /// </para>
    [Parameter(Mandatory = true, HelpMessage = "The SQL Server Instance", ValueFromPipeline = true, ValueFromPipelineByPropertyName = true, ValueFromRemainingArguments = false, Position = 0)]
    [PsDbaInstanceArrayCast]
    [ValidateNotNull]
    [ValidateNotNullOrEmpty]
    public override DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <para>
    /// Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).
    /// </para>
    /// <para>
    /// Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.
    /// </para>
    /// <para>
    /// For MFA support, please use Connect-DbaInstance. be it Windows or SQL Server. Windows users are determined by the existence of a backslash, so if you are intending to use an alternative Windows connection instead of a SQL login, ensure it contains a backslash.
    /// </para>
    [Parameter(HelpMessage = "SQL Credential", ValueFromPipelineByPropertyName = true, ValueFromRemainingArguments = false, Position = 1)]
    public override PSCredential? SqlCredential { get; set; }

    /// <para>
    /// Specifies specific SQL Agent jobs to examine for output file configurations. Accepts job names as strings and supports multiple values.
    /// Use this when you need to check output file paths for specific jobs rather than scanning all jobs on the instance.
    /// </para>
    [Parameter]
    public object[]? Job { get; set; }

    /// <para>
    /// Specifies SQL Agent jobs to exclude from the output file search. Accepts job names as strings and supports multiple values.
    /// Use this when you want to scan most jobs but skip specific ones, such as excluding system maintenance jobs or jobs you know don't use output files.
    /// </para>
    [Parameter]
    public object[]? ExcludeJob { get; set; }

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

        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            if (Interrupted)
                return;

            // PS: try { Connect-DbaInstance } catch { Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue }
            // Upstream correction azure-unsupported: SQL Server Agent and msdb do not exist in Azure SQL Database, so the
            // connection refuses it as Connect-DbaInstance -AzureUnsupported does instead of failing on the Agent read.
            Server? server = ConnectInstance(instance, "Failure", azureUnsupported: true);
            if (server is null)
                continue;

            foreach (AgentJob job in server.JobServer.Jobs)
            {
                if (Interrupted)
                    return;
                if (FilterHelper.IsActive(Job) && !Contains(Job!, job.Name))
                    continue;
                if (FilterHelper.IsActive(ExcludeJob) && Contains(ExcludeJob!, job.Name))
                    continue;

                foreach (JobStep step in job.JobSteps)
                {
                    if (Interrupted)
                        return;

                    if (!string.IsNullOrEmpty(step.OutputFileName))
                    {
                        PSObject result = new();
                        result.Properties.Add(new PSNoteProperty("ComputerName", SmoServerExtensions.GetComputerName(server)));
                        result.Properties.Add(new PSNoteProperty("InstanceName", server.ServiceName));
                        result.Properties.Add(new PSNoteProperty("SqlInstance", SmoServerExtensions.GetDomainInstanceName(server)));
                        result.Properties.Add(new PSNoteProperty("Job", job.Name));
                        result.Properties.Add(new PSNoteProperty("JobStep", step.Name));
                        result.Properties.Add(new PSNoteProperty("OutputFileName", step.OutputFileName));
                        result.Properties.Add(new PSNoteProperty("RemoteOutputFileName", JoinAdminUnc(SmoServerExtensions.GetComputerName(server), step.OutputFileName)));
                        result.Properties.Add(new PSNoteProperty("StepId", step.ID));
                        OutputHelper.SetDefaultDisplayPropertySet(result,
                            "ComputerName", "InstanceName", "Job", "JobStep", "OutputFileName",
                            "RemoteOutputFileName", "SqlInstance");
                        WriteObject(result);
                    }
                    else
                    {
                        WriteMessage(MessageLevel.Verbose, step + " for " + job + " has no output file");
                    }
                }
            }
        }
    }

    private static bool Contains(object[] values, string name)
    {
        foreach (object? value in values)
        {
            if (LanguagePrimitives.Equals(name, value, true, CultureInfo.InvariantCulture))
                return true;
        }
        return false;
    }

    private static string JoinAdminUnc(string? serverName, string filePath)
    {
        if (string.IsNullOrEmpty(filePath) || filePath.StartsWith("\\\\", StringComparison.Ordinal) ||
            Environment.OSVersion.Platform != PlatformID.Win32NT)
            return filePath;

        string host = (serverName ?? string.Empty).Split('\\')[0];
        // The PS source is Join-Path "\\server\" (filePath with : -> $), which normalizes forward
        // slashes to backslashes and collapses the single duplicate separator at the parent/child
        // boundary. Replicate both so a root-relative ("\logs\x") or forward-slash ("/logs/x")
        // output-file path yields "\\server\logs\x" rather than a malformed UNC.
        string child = filePath.Replace(':', '$').Replace('/', '\\');
        if (child.Length > 0 && child[0] == '\\')
        {
            child = child.Substring(1);
        }
        return "\\\\" + host + "\\" + child;
    }
}

/// <summary>Reproduces an advanced function's typed-array conversion before validation.</summary>
internal sealed class PsDbaInstanceArrayCastAttribute : ArgumentTransformationAttribute
{
    public override object? Transform(EngineIntrinsics engineIntrinsics, object? inputData)
    {
        if (inputData is null)
            return null;

        try
        {
            return LanguagePrimitives.ConvertTo(inputData, typeof(DbaInstanceParameter[]), CultureInfo.InvariantCulture);
        }
        catch (PSInvalidCastException ex)
        {
            throw new ArgumentTransformationMetadataException(ex.Message, ex);
        }
    }
}
