#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;
using Microsoft.SqlServer.Management.Smo.Agent;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Removes SQL Server Agent alert categories from SQL Server instances.
/// </summary>
/// <para>
/// Removes custom alert categories from SQL Server Agent, useful for cleaning up unused organizational structures or standardizing alert management across environments.
/// Any existing alerts that reference the removed category will automatically be reassigned to the [Uncategorized] category, so you don't need to manually update alert assignments before removal.
/// The function works with both individual category names and accepts pipeline input from Get-DbaAgentAlertCategory for bulk operations.
/// Returns detailed status information showing which categories were successfully removed and any that failed with error details.
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Remove-DbaAgentAlertCategory -SqlInstance sql1 -Category 'Category 1'
/// </code>
/// <para>
/// Remove the alert category Category 1 from the instance.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Remove-DbaAgentAlertCategory -SqlInstance sql1 -Category Category1, Category2, Category3
/// </code>
/// <para>
/// Remove multiple alert categories from the instance.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Remove-DbaAgentAlertCategory -SqlInstance sql1, sql2, sql3 -Category Category1, Category2, Category3
/// </code>
/// <para>
/// Remove multiple alert categories from the multiple instances.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaAgentAlertCategory -SqlInstance SRV1 | Out-GridView -Title 'Select SQL Agent alert category(-ies) to drop' -OutputMode Multiple | Remove-DbaAgentAlertCategory
/// </code>
/// <para>
/// Using a pipeline this command gets all SQL Agent alert category(-ies) on SRV1, lets the user select those to remove and then removes the selected SQL Agent alert category(-ies).
/// </para>
/// </example>
/// <list type="alertSet">
/// <item>
/// <term />
/// <description>
/// <para>
/// Tags: Agent, Alert, AlertCategory
/// Author: Patrick Flynn (@sqllensman)
/// </para>
/// <para>
/// Website: https://dbatools.io
/// Copyright: (c) 2018 by dbatools, licensed under MIT
/// License: MIT https://opensource.org/licenses/MIT
/// </para>
/// </description>
/// </item>
/// </list>
/// <seealso href="https://dbatools.io/Remove-DbaAgentAlertCategory" />
[Cmdlet(VerbsCommon.Remove, "DbaAgentAlertCategory", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High)]
[OutputType(typeof(PSObject))]
public sealed class RemoveDbaAgentAlertCategoryCommand : DbaInstanceCmdlet
{
    /// <para>
    /// The target SQL Server instance or instances. You must have sysadmin access and server version must be SQL Server version 2000 or greater.
    /// </para>
    [Parameter(ParameterSetName = "NonPipeline", Mandatory = true, Position = 0)]
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
    [Parameter(ParameterSetName = "NonPipeline")]
    public override PSCredential? SqlCredential { get; set; }

    /// <para>
    /// Specifies the names of the alert categories to remove from SQL Server Agent. Accepts multiple category names for bulk removal.
    /// Use this to target specific custom categories you want to delete while keeping others intact.
    /// </para>
    [Parameter(ParameterSetName = "NonPipeline")]
    [PsStringArrayCast]
    public string[]? Category { get; set; }

    /// <para>
    /// Accepts alert category objects from Get-DbaAgentAlertCategory for pipeline-based operations.
    /// Use this when you need to filter or select categories interactively before removal, such as with Out-GridView.
    /// </para>
    [Parameter(ParameterSetName = "Pipeline", Mandatory = true, ValueFromPipeline = true)]
    public AlertCategory[]? InputObject { get; set; }

    /// <para>
    /// By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
    /// This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
    /// Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.
    /// </para>
    [Parameter(ParameterSetName = "NonPipeline")]
    [Parameter(ParameterSetName = "Pipeline")]
    public override SwitchParameter EnableException { get; set; }

    private readonly List<AlertCategory> _categories = new();

    protected override void ProcessRecord()
    {
        if (Interrupted)
            return;

        if (ParameterSetName == "Pipeline")
        {
            _categories.AddRange(InputObject ?? Array.Empty<AlertCategory>());
            return;
        }

        // The pinned instance path replaces its selection; pipeline records append.
        _categories.Clear();
        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            if (Interrupted)
                return;
            Server? server = ConnectInstance(instance, azureUnsupported: true);
            if (server is null)
                continue;
            List<AlertCategory>? selected = ReadCategories(server);
            if (selected is null)
                continue;
            PSObject? currentCategory = null;
            try
            {
                foreach (AlertCategory category in selected)
                {
                    currentCategory = PSObject.AsPSObject(category);
                    int count = AgentCategoryOutput.CountUsage(server, category);
                    AgentCategoryOutput.DecorateAlert(currentCategory, server, count);
                    _categories.Add(category);
                }
            }
            catch (Exception exception) when (exception is not PipelineStoppedException)
            {
                // The pinned Get catches count failures and preserves categories it already emitted.
                ErrorRecord record = new(exception, "Get-DbaAgentAlertCategory", ErrorCategory.NotSpecified, currentCategory?.BaseObject);
                StopAttributedFunction("Get-DbaAgentAlertCategory",
                    String.Format("Something went wrong getting the alert category {0} on {1}", currentCategory, instance),
                    target: currentCategory?.BaseObject, errorRecord: record, continueLoop: true);
            }
        }
    }

    private List<AlertCategory>? ReadCategories(Server server)
    {
        List<AlertCategory> categories = new();
        IEnumerator? enumerator = null;
        try
        {
            enumerator = LanguagePrimitives.GetEnumerator(server.JobServer.AlertCategories);
            while (enumerator is not null && enumerator.MoveNext())
            {
                AlertCategory category = (AlertCategory)enumerator.Current;
                if (!TestBound(nameof(Category)) || AgentCategoryNames.Contains(Category, category.Name))
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
            ReportReadFailure(record);
            // No selection was produced. Unlike the pin's retained collection, this list is not
            // enumerated again by the count loop; omit that unperformed read's consequential
            // Get-DbaAgentAlertCategory warning and Stop-Function record (keep-going point 2).
            return null;
        }
        return categories;
    }

    private void ReportReadFailure(ErrorRecord record)
    {
        if (EnableException)
        {
            // caller-try: terminate -- -EnableException requests a stop before any selected category is removed.
            ThrowTerminatingError(record); // style-ok: cs-raw-streams preserve the read error under EnableException
        }
        StatementFault.Surface(this, record);
    }

    protected override void EndProcessing()
    {
        if (Interrupted)
            return;

        // Drop only after the upstream SMO collection has finished enumerating.
        foreach (AlertCategory category in _categories)
        {
            if (Stopping)
                return;
            Server server = category.Parent.Parent;
            string name = category.Name;
            if (!ShouldProcess(server.Name, String.Format("Removing the SQL Agent alert category {0} on {1}", name, server.Name)))
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
                StopFunction(String.Format("Failed removing the SQL Agent alert category {0} on {1}", name, server.Name),
                    errorRecord: record);
                output.Properties["Status"].Value = MessageService.GetErrorMessage(record);
            }
            // The pinned end block keeps emitting after a warning, but stops on EnableException.
            WriteObject(output);
        }
    }

}
