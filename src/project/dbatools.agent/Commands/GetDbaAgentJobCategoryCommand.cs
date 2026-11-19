#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;
using Microsoft.SqlServer.Management.Smo;
using Microsoft.SqlServer.Management.Smo.Agent;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Retrieves SQL Server Agent job categories with usage counts and filtering options
/// </summary>
/// <para>
/// Returns SQL Server Agent job categories from one or more instances, showing how many jobs are assigned to each category. Job categories help organize and group related SQL Agent jobs for easier management and reporting. This function retrieves both built-in categories (like Database Maintenance, Log Shipping) and custom categories created by DBAs. You can filter by specific category names or types (LocalJob for single-instance jobs, MultiServerJob for MSX/TSX environments, or None for uncategorized jobs) to focus on particular organizational schemes.
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaAgentJobCategory -SqlInstance sql1
/// </code>
/// <para>
/// Return all the job categories.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaAgentJobCategory -SqlInstance sql1 -Category 'Log Shipping'
/// </code>
/// <para>
/// Return all the job categories that have the name 'Log Shipping'.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaAgentJobCategory -SqlInstance sstad-pc -CategoryType MultiServerJob
/// </code>
/// <para>
/// Return all the job categories that have a type MultiServerJob.
/// </para>
/// </example>
/// <list type="alertSet">
/// <item>
/// <term />
/// <description>
/// <para>
/// Tags: Agent, Job, Category
/// Author: Sander Stad (@sqlstad), sqlstad.nl
/// </para>
/// <para>
/// Website: https://dbatools.io
/// Copyright: (c) 2018 by dbatools, licensed under MIT
/// License: MIT https://opensource.org/licenses/MIT
/// </para>
/// </description>
/// </item>
/// </list>
/// <seealso href="https://dbatools.io/Get-DbaAgentJobCategory" />
[Cmdlet(VerbsCommon.Get, "DbaAgentJobCategory", DefaultParameterSetName = "Default")]
[OutputType(typeof(JobCategory))]
public sealed class GetDbaAgentJobCategoryCommand : DbaInstanceCmdlet
{
    /// <para>
    /// The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.
    /// </para>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    [PsDbaInstanceArrayCast]
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
    /// Specifies one or more job category names to return, filtering the results to only those categories. Accepts multiple values and supports built-in categories like 'Database Maintenance', 'Log Shipping', 'Replication', and custom categories created by DBAs.
    /// Use this when you need to check specific categories for job assignments or verify custom organizational schemes. If not specified, all job categories are returned.
    /// </para>
    [Parameter(Position = 2)]
    [ValidateNotNullOrEmpty]
    public string[]? Category { get; set; }

    /// <para>
    /// Filters job categories by their deployment type: 'LocalJob' for single-instance jobs, 'MultiServerJob' for Master Server/Target Server (MSX/TSX) environments, or 'None' for uncategorized jobs.
    /// Use this in MSX/TSX configurations to distinguish between locally managed jobs and multi-server jobs, or to identify jobs that haven't been assigned a proper category. If not specified, all category types are returned.
    /// </para>
    [Parameter(Position = 3)]
    [PsStringCast]
    [ValidateSet("LocalJob", "MultiServerJob", "None")]
    public string? CategoryType { get; set; }

    // The pinned function retains its decorated loop variable between input records.
    private PSObject? _category;

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

            Server? server = ConnectInstance(instance, azureUnsupported: true);
            if (server is null)
                continue;

            List<JobCategory>? categories = ReadCategories(server.JobServer.JobCategories);
            if (categories is null)
                continue;
            try
            {
                foreach (JobCategory category in categories)
                {
                    _category = PSObject.AsPSObject(category);
                    int count = AgentCategoryOutput.CountUsage(server, category);
                    AgentCategoryOutput.DecorateJob(_category, server, count);
                    WriteObject(_category);
                }
            }
            catch (Exception ex) when (ex is not PipelineStoppedException)
            {
                ErrorRecord record = new(ex, MyInvocation.MyCommand.Name, ErrorCategory.NotSpecified, _category);
                StopFunction(String.Format("Something went wrong getting the job category {0} on {1}", _category, instance),
                    target: _category, errorRecord: record, continueLoop: true);
            }
        }
    }

    private List<JobCategory>? ReadCategories(JobCategoryCollection collection)
    {
        List<JobCategory> categories = new();
        IEnumerator? enumerator = null;
        try
        {
            enumerator = LanguagePrimitives.GetEnumerator(collection);
            while (enumerator is not null && enumerator.MoveNext())
            {
                JobCategory category = (JobCategory)enumerator.Current;
                if (LanguagePrimitives.IsTrue(Category) && !AgentCategoryNames.Contains(Category, category.Name))
                    continue;
                if (LanguagePrimitives.IsTrue(CategoryType) && !LanguagePrimitives.Equals(
                    category.CategoryType.ToString(), CategoryType, true, CultureInfo.InvariantCulture))
                    continue;
                categories.Add(category);
            }
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            ErrorRecord record;
            if (failure is IContainsErrorRecord container && container.ErrorRecord is not null)
                record = new ErrorRecord(container.ErrorRecord, failure);
            else
            {
                RuntimeException fault = new(String.Format(CultureInfo.InvariantCulture,
                    "An error occurred while enumerating through a collection: {0}.", failure.Message), failure);
                record = new ErrorRecord(fault, "BadEnumeration", ErrorCategory.InvalidOperation, enumerator);
            }
            // caller-try: continue -- read-only; no input dropped, no stale rows
            if (EnableException)
                ThrowTerminatingError(record); // style-ok: cs-raw-streams pinned filtering statement fault outside Stop-Function
            WriteError(record); // style-ok: cs-raw-streams pinned filtering statement fault outside Stop-Function
            return null;
        }
        return categories;
    }
}
