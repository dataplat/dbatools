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
/// Retrieves SQL Server Agent alert categories and their associated alert counts
/// </summary>
/// <para>
/// Retrieves all SQL Server Agent alert categories from the target instances, showing how alerts are organized and grouped. Categories help DBAs manage alerts logically by grouping related notifications (such as severity-based alerts, database maintenance alerts, or custom business alerts). The function also returns a count of how many alerts are currently assigned to each category, making it useful for understanding your alerting structure and identifying unused or heavily-used categories.
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaAgentAlertCategory -SqlInstance sql1
/// </code>
/// <para>
/// Return all the agent alert categories.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaAgentAlertCategory -SqlInstance sql1 -Category 'Severity Alert'
/// </code>
/// <para>
/// Return all the agent alert categories that have the name 'Severity Alert'.
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
/// <seealso href="https://dbatools.io/Get-DbaAgentAlertCategory" />
[Cmdlet(VerbsCommon.Get, "DbaAgentAlertCategory")]
[OutputType(typeof(AlertCategory))]
public sealed class GetDbaAgentAlertCategoryCommand : DbaInstanceCmdlet
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
    /// Specifies one or more alert category names to return from the SQL Server Agent. Accepts multiple values and wildcards are not supported.
    /// Use this when you need to examine specific alert categories rather than retrieving all categories on the instance.
    /// </para>
    [Parameter(Position = 2)]
    [PsStringArrayCast]
    public string[]? Category { get; set; }

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

            bool hasFilter = TestBound(nameof(Category));
            List<AlertCategory>? filtered = hasFilter ? FilterCategories(server.JobServer.AlertCategories, instance) : null;
            if (hasFilter && filtered is null)
                continue;
            try
            {
                IEnumerable categories = filtered is null ? server.JobServer.AlertCategories : filtered;
                foreach (AlertCategory category in categories)
                {
                    _category = PSObject.AsPSObject(category);
                    int count = AgentCategoryOutput.CountUsage(server, category);
                    AgentCategoryOutput.DecorateAlert(_category, server, count);
                    WriteObject(_category);
                }
            }
            catch (Exception ex) when (ex is not PipelineStoppedException)
            {
                ErrorRecord record = new(ex, MyInvocation.MyCommand.Name, ErrorCategory.NotSpecified, _category);
                StopFunction(String.Format("Something went wrong getting the alert category {0} on {1}", _category, instance),
                    target: _category, errorRecord: record, continueLoop: true);
            }
        }
    }

    private List<AlertCategory>? FilterCategories(AlertCategoryCollection collection, DbaInstanceParameter instance)
    {
        List<AlertCategory> categories = new();
        IEnumerator? enumerator = null;
        try
        {
            enumerator = LanguagePrimitives.GetEnumerator(collection);
            while (enumerator is not null && enumerator.MoveNext())
            {
                AlertCategory category = (AlertCategory)enumerator.Current;
                if (AgentCategoryNames.Contains(Category, category.Name)) categories.Add(category);
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
            if (EnableException)
                // caller-try: terminate -- EnableException explicitly requests the enumeration fault to stop.
                ThrowTerminatingError(record); // style-ok: cs-raw-streams preserve the enumeration error under EnableException
            StatementFault.Surface(this, record);
            ErrorRecord warningRecord = new(failure, MyInvocation.MyCommand.Name, ErrorCategory.NotSpecified, _category);
            StopFunction(String.Format("Something went wrong getting the alert category {0} on {1}", _category, instance),
                target: _category, errorRecord: warningRecord, continueLoop: true);
            return null;
        }
        return categories;
    }

}
