#nullable enable

using System;
using System.Collections.Generic;
using System.Management.Automation;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;
using Microsoft.SqlServer.Management.Smo.Agent;

namespace Dataplat.Dbatools.Commands;

/// <summary>Removes SQL Server Agent job categories from one or more instances.</summary>
[Cmdlet(VerbsCommon.Remove, "DbaAgentJobCategory", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High)]
[OutputType(typeof(PSObject))]
public sealed class RemoveDbaAgentJobCategoryCommand : DbaInstanceCmdlet
{
    /// <summary>Target SQL Server instances.</summary>
    [Parameter(ParameterSetName = "NonPipeline", Mandatory = true, Position = 0)]
    [PsDbaInstanceArrayCast]
    public override DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter(ParameterSetName = "NonPipeline")]
    public override PSCredential? SqlCredential { get; set; }

    /// <summary>Exact job category names to remove.</summary>
    [Parameter(ParameterSetName = "NonPipeline")]
    // The pinned lookup validates Category before it reads or removes anything.
    [ValidateNotNullOrEmpty]
    [PsStringArrayCast]
    public string[]? Category { get; set; }

    /// <summary>Category types accepted by the pinned parameter surface.</summary>
    [Parameter(ParameterSetName = "NonPipeline")]
    [PsStringArrayCast]
    [ValidateSet("LocalJob", "MultiServerJob", "None")]
    public string[]? CategoryType { get; set; }

    /// <summary>Job categories supplied directly or through the pipeline.</summary>
    [Parameter(ParameterSetName = "Pipeline", Mandatory = true, ValueFromPipeline = true)]
    public JobCategory[]? InputObject { get; set; }

    /// <summary>Throw terminating errors instead of friendly warnings.</summary>
    [Parameter(ParameterSetName = "NonPipeline")]
    [Parameter(ParameterSetName = "Pipeline")]
    public override SwitchParameter EnableException { get; set; }

    private readonly List<JobCategory> _categories = new();

    protected override void ProcessRecord()
    {
        if (Interrupted)
            return;

        if (ParameterSetName == "Pipeline")
        {
            _categories.AddRange(InputObject ?? Array.Empty<JobCategory>());
            return;
        }

        // The pinned instance path replaces its selection; pipeline records append.
        _categories.Clear();
        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            Server? server = ConnectInstance(instance);
            if (server is null)
                continue;
            try
            {
                foreach (JobCategory category in server.JobServer.JobCategories)
                {
                    if (TestBound(nameof(Category)) && !AgentCategoryNames.Contains(Category, category.Name))
                        continue;
                    if (TestBound(nameof(CategoryType)) && !AgentCategoryNames.Contains(CategoryType, category.CategoryType.ToString()))
                        continue;
                    _categories.Add(category);
                }
            }
            catch (Exception exception) when (exception is not PipelineStoppedException)
            {
                ErrorRecord record = new(exception, MyInvocation.MyCommand.Name, ErrorCategory.NotSpecified, instance);
                StopFunction(String.Format("Something went wrong getting the job category on {0}", instance),
                    target: instance, errorRecord: record, continueLoop: true);
            }
        }
    }

    protected override void EndProcessing()
    {
        if (Interrupted)
            return;

        // Drop only after the upstream SMO collection has finished enumerating.
        foreach (JobCategory category in _categories)
        {
            if (Stopping)
                return;
            Server server = category.Parent.Parent;
            string name = category.Name;
            if (!ShouldProcess(server.Name, String.Format("Removing the SQL Agent category(-ies) {0} on {1}", name, server.Name)))
                continue;

            PSObject output = new();
            OutputHelper.AddInstanceProperties(output, server);
            output.Properties.Add(new PSNoteProperty("Name", name));
            output.Properties.Add(new PSNoteProperty("Status", null));
            output.Properties.Add(new PSNoteProperty("IsRemoved", false));
            try
            {
                category.Drop();
                output.Properties["Status"].Value = "Dropped";
                output.Properties["IsRemoved"].Value = true;
            }
            catch (Exception exception) when (exception is not PipelineStoppedException)
            {
                ErrorRecord record = new(exception, MyInvocation.MyCommand.Name, ErrorCategory.NotSpecified, null);
                StopFunction(String.Format("Failed removing the SQL Agent job category(-ies) {0} on {1}", name, server.Name),
                    errorRecord: record);
                output.Properties["Status"].Value = MessageService.GetErrorMessage(record);
            }
            // The pinned end block keeps emitting after a warning, but stops on EnableException.
            WriteObject(output);
        }
    }

}
