#nullable enable

using System;
using System.Collections.Generic;
using System.Management.Automation;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

// Port of public/Get-DbaRgWorkloadGroup.ps1 at refs/pins/dbatools-2026-10-22. Its nested Get-DbaRgResourcePool -SqlInstance
// -SqlCredential call runs inline (ResourceGovernorReaderCmdlet): that command's nested Get-DbaResourceGovernor connect, the
// decorated governor and internal pools, and Get-DbaResourceGovernor's own warning and record on a failed connection, whatever
// this command's -EnableException (the pin passes none to the nested call).
// Corrections (quality/corrections/Get-DbaRgWorkloadGroup.json): n-by-n (each -SqlInstance is read once, where the pin passes the
// whole -SqlInstance array to the nested Get-DbaRgResourcePool once per element, which reads it once per element again),
// piped-accumulation (each pipeline record reads only its own input, where the pin keeps appending to $InputObject across
// records) and azure-unsupported (Azure SQL Database is refused as the corrected Get-DbaResourceGovernor refuses it).

/// <summary>
/// Retrieves Resource Governor workload groups from SQL Server instances
/// </summary>
/// <para>
/// Retrieves Resource Governor workload groups along with their configuration settings including CPU limits, memory grants, and parallelism controls. Workload groups define how resource requests are classified and managed within resource pools, allowing DBAs to control resource consumption for different types of workloads. This function is essential for monitoring and troubleshooting Resource Governor configurations to ensure optimal performance isolation between competing workloads.
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaRgWorkloadGroup -SqlInstance sql2017
/// </code>
/// <para>
/// Gets the workload groups on sql2017
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaResourceGovernor -SqlInstance sql2017 | Get-DbaRgResourcePool | Get-DbaRgWorkloadGroup
/// </code>
/// <para>
/// Gets the workload groups on sql2017
/// </para>
/// </example>
/// <list type="alertSet">
/// <item>
/// <term />
/// <description>
/// <para>
/// Tags: ResourceGovernor
/// Author: Chrissy LeMaire (@cl), netnerds.net
/// </para>
/// <para>
/// Website: https://dbatools.io
/// Copyright: (c) 2018 by dbatools, licensed under MIT
/// License: MIT https://opensource.org/licenses/MIT
/// </para>
/// </description>
/// </item>
/// <item>
/// <term>OUTPUTS</term>
/// <description>
/// <para>
/// Microsoft.SqlServer.Management.Smo.WorkloadGroup
/// </para>
/// <para>
/// Returns one WorkloadGroup object per workload group found in the specified resource pools. Each workload group object includes configuration settings for resource consumption limits and request handling behavior.
/// </para>
/// <para>
/// Default display properties (via Select-DefaultView):
/// - ComputerName: The computer name of the SQL Server instance
/// - InstanceName: The SQL Server instance name
/// - SqlInstance: The full SQL Server instance name (computer\instance)
/// - Id: Unique identifier for the workload group
/// - Name: Name of the workload group
/// - ExternalResourcePoolName: Name of the associated external resource pool (if applicable)
/// - GroupMaximumRequests: Maximum number of concurrent requests allowed in the workload group (0 = unlimited)
/// - Importance: Importance level of requests in this group (Low, Medium, High)
/// - IsSystemObject: Boolean indicating if this is a system-defined workload group
/// - MaximumDegreeOfParallelism: Maximum number of processors for parallel query execution (0 = unlimited)
/// - RequestMaximumCpuTimeInSeconds: Maximum CPU time in seconds per request (0 = unlimited)
/// - RequestMaximumMemoryGrantPercentage: Maximum memory grant as percentage of resource pool memory
/// - RequestMemoryGrantTimeoutInSeconds: Timeout in seconds for memory grant requests
/// </para>
/// <para>
/// Additional properties available (from SMO WorkloadGroup object):
/// - ClassifierFunction: Name of the scalar classifier function (if any)
/// - CreateDate: DateTime when the workload group was created
/// - ModifyDate: DateTime when the workload group was last modified
/// - Parent: Reference to the parent ResourcePool object
/// - State: Current state of the workload group object
/// </para>
/// <para>
/// All properties from the base SMO object are accessible using Select-Object *.
/// </para>
/// </description>
/// </item>
/// </list>
/// <seealso href="https://dbatools.io/Get-DbaRgWorkloadGroup" />
[Cmdlet(VerbsCommon.Get, "DbaRgWorkloadGroup")]
[OutputType(typeof(WorkloadGroup))]
public sealed class GetDbaRgWorkloadGroupCommand : ResourceGovernorReaderCmdlet
{
    /// <para>
    /// The target SQL Server instance or instances
    /// </para>
    [Parameter(ValueFromPipeline = true, Position = 0)]
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
    /// Accepts resource pool objects from Get-DbaRgResourcePool to retrieve workload groups from specific pools only.
    /// Use this to filter workload groups when you need to examine groups within particular resource pools instead of all workload groups across the instance.
    /// </para>
    [Parameter(ValueFromPipeline = true, Position = 2)]
    public ResourcePool[]? InputObject { get; set; }

    /// <para>
    /// By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
    /// This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
    /// Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.
    /// </para>
    [Parameter]
    public override SwitchParameter EnableException { get; set; }

    protected override void ProcessRecord()
    {
        // Correction piped-accumulation: only this record's pools, never those of earlier pipeline records.
        List<ResourcePool?> pools = new(InputObject ?? Array.Empty<ResourcePool>());

        // PS: foreach ($instance in $SqlInstance) { $InputObject += Get-DbaRgResourcePool -SqlInstance $SqlInstance -SqlCredential $SqlCredential }
        // Correction n-by-n: each instance is read once, through the nested Get-DbaRgResourcePool (default -Type Internal) for that
        // instance only.
        foreach (DbaInstanceParameter instance in SqlInstance ?? Array.Empty<DbaInstanceParameter>())
        {
            ResourceGovernor? resourcegov = GetResourceGovernor(instance);
            // PS (Get-DbaRgResourcePool): $null.ResourcePools is $null, and if ($respool) emits nothing.
            if (resourcegov is null)
                continue;
            foreach (ResourcePool respool in resourcegov.ResourcePools)
            {
                DecoratePool(respool, resourcegov);
                pools.Add(respool);
            }
        }

        foreach (ResourcePool? pool in pools)
        {
            // PS: $null.WorkloadGroups is $null, and if ($group) emits nothing.
            if (pool is null)
                continue;

            // PS: $group | Add-Member -Force ComputerName, InstanceName, SqlInstance from the pool's notes ($null on a pool that has
            // none), then Select-DefaultView.
            object? computerName = SmoServerExtensions.GetPSProperty(pool, "ComputerName");
            object? instanceName = SmoServerExtensions.GetPSProperty(pool, "InstanceName");
            object? sqlInstance = SmoServerExtensions.GetPSProperty(pool, "SqlInstance");
            foreach (WorkloadGroup group in pool.WorkloadGroups)
            {
                PSObject wrapped = PSObject.AsPSObject(group);
                ReplaceNoteProperty(wrapped, "ComputerName", computerName);
                ReplaceNoteProperty(wrapped, "InstanceName", instanceName);
                ReplaceNoteProperty(wrapped, "SqlInstance", sqlInstance);
                OutputHelper.SetDefaultDisplayPropertySet(wrapped,
                    "ComputerName", "InstanceName", "SqlInstance", "Id", "Name", "ExternalResourcePoolName", "GroupMaximumRequests",
                    "Importance", "IsSystemObject", "MaximumDegreeOfParallelism", "RequestMaximumCpuTimeInSeconds",
                    "RequestMaximumMemoryGrantPercentage", "RequestMemoryGrantTimeoutInSeconds");
                WriteObject(wrapped);
            }
        }
    }
}
