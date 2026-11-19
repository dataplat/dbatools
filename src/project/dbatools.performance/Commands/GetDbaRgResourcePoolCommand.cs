#nullable enable

using System;
using System.Collections.Generic;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

// Port of public/Get-DbaRgResourcePool.ps1 at refs/pins/dbatools-2026-10-22. Its nested Get-DbaResourceGovernor call runs inline:
// the same Connect-DbaInstance -MinimumVersion 10, the same decorated governor, and that command's own warning and record on a
// failed connection, whatever this command's -EnableException (the pin calls it without -EnableException).
// Corrections (quality/corrections/Get-DbaRgResourcePool.json): n-by-n (each -SqlInstance is read once, where the pin reads the
// whole -SqlInstance array once per element), piped-accumulation (each pipeline record reads only its own input, where the pin
// keeps appending to $InputObject across records) and azure-unsupported (Azure SQL Database is refused as the corrected
// Get-DbaResourceGovernor refuses it).

/// <summary>
/// Retrieves SQL Server Resource Governor resource pools with their CPU, memory, and IOPS configuration settings
/// </summary>
/// <para>
/// Retrieves detailed information about SQL Server Resource Governor resource pools, including both internal (CPU/memory) and external (R/Python) pools. Shows current configuration settings for minimum and maximum CPU percentages, memory percentages, and IOPS limits per volume. Essential for monitoring resource allocation, troubleshooting performance bottlenecks, and auditing resource governance policies across your SQL Server instances.
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaRgResourcePool -SqlInstance sql2016
/// </code>
/// <para>
/// Gets the internal resource pools on sql2016
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; 'Sql1','Sql2/sqlexpress' | Get-DbaResourceGovernor | Get-DbaRgResourcePool
/// </code>
/// <para>
/// Gets the internal resource pools on Sql1 and Sql2/sqlexpress instances
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; 'Sql1','Sql2/sqlexpress' | Get-DbaResourceGovernor | Get-DbaRgResourcePool -Type External
/// </code>
/// <para>
/// Gets the external resource pools on Sql1 and Sql2/sqlexpress instances
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
/// Microsoft.SqlServer.Management.Smo.ResourcePool (Internal pools) or Microsoft.SqlServer.Management.Smo.ExternalResourcePool (External pools)
/// </para>
/// <para>
/// Returns one ResourcePool or ExternalResourcePool object per resource pool found on the instance. The object type depends on the -Type parameter:
/// - Type "Internal" (default): Returns Microsoft.SqlServer.Management.Smo.ResourcePool objects
/// - Type "External": Returns Microsoft.SqlServer.Management.Smo.ExternalResourcePool objects
/// </para>
/// <para>
/// Default display properties (via Select-DefaultView):
/// - ComputerName: The computer name of the SQL Server instance
/// - InstanceName: The SQL Server instance name
/// - SqlInstance: The full SQL Server instance name (computer\instance)
/// - Id: Unique identifier for the resource pool
/// - Name: Name of the resource pool
/// - CapCpuPercentage: CPU cap percentage (0-100 for External pools, always 0 for Internal pools)
/// - IsSystemObject: Boolean indicating if this is a system-defined resource pool
/// - MaximumCpuPercentage: Maximum CPU percentage allocated to this pool (0-100)
/// - MaximumIopsPerVolume: Maximum I/O operations per second per volume (External pools only)
/// - MaximumMemoryPercentage: Maximum memory percentage allocated to this pool (0-100)
/// - MinimumCpuPercentage: Minimum CPU percentage reserved for this pool (0-100)
/// - MinimumIopsPerVolume: Minimum I/O operations per second per volume (External pools only)
/// - MinimumMemoryPercentage: Minimum memory percentage reserved for this pool (0-100)
/// - WorkloadGroups: Collection of workload groups associated with this resource pool
/// </para>
/// <para>
/// Additional properties available (from SMO ResourcePool or ExternalResourcePool objects):
/// - CreateDate: DateTime when the resource pool was created
/// - ModifyDate: DateTime when the resource pool was last modified
/// - Parent: Reference to the parent ResourceGovernor object
/// - State: Current state of the resource pool object (Existing, Creating, Pending, etc.)
/// </para>
/// <para>
/// All properties from the base SMO object are accessible using Select-Object *.
/// </para>
/// </description>
/// </item>
/// </list>
/// <seealso href="https://dbatools.io/Get-DbaRgResourcePool" />
[Cmdlet(VerbsCommon.Get, "DbaRgResourcePool")]
[OutputType(typeof(ResourcePool), typeof(ExternalResourcePool))]
public sealed class GetDbaRgResourcePoolCommand : ResourceGovernorReaderCmdlet
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
    /// Specifies whether to retrieve Internal resource pools (CPU/memory) or External resource pools (R/Python services).
    /// Internal pools control SQL Server workloads, while External pools govern Machine Learning Services resource consumption.
    /// </para>
    [Parameter(Position = 2)]
    [PsStringCast]
    [ValidateSet("Internal", "External")]
    public string Type { get; set; } = "Internal";

    /// <para>
    /// Accepts Resource Governor objects from Get-DbaResourceGovernor for pipeline processing.
    /// Use this when you need to filter or process resource pools from multiple instances collected earlier in your script.
    /// </para>
    [Parameter(ValueFromPipeline = true, Position = 3)]
    public ResourceGovernor[]? InputObject { get; set; }

    /// <para>
    /// By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
    /// This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
    /// Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.
    /// </para>
    [Parameter]
    public override SwitchParameter EnableException { get; set; }

    protected override void ProcessRecord()
    {
        // Correction piped-accumulation: only this record's governors, never those of earlier pipeline records.
        List<ResourceGovernor?> governors = new(InputObject ?? Array.Empty<ResourceGovernor>());

        // Correction n-by-n: each instance is read once (the pin reads the whole -SqlInstance array once per element).
        foreach (DbaInstanceParameter instance in SqlInstance ?? Array.Empty<DbaInstanceParameter>())
        {
            ResourceGovernor? governor = GetResourceGovernor(instance);
            if (governor is not null)
                governors.Add(governor);
        }

        bool external = string.Equals(Type, "External", StringComparison.OrdinalIgnoreCase);
        foreach (ResourceGovernor? resourcegov in governors)
        {
            // PS: $null.ResourcePools is $null, and if ($respool) emits nothing.
            if (resourcegov is null)
                continue;

            if (external)
            {
                foreach (ExternalResourcePool pool in resourcegov.ExternalResourcePools)
                    EmitPool(pool, resourcegov);
            }
            else
            {
                foreach (ResourcePool pool in resourcegov.ResourcePools)
                    EmitPool(pool, resourcegov);
            }
        }
    }

    // PS: $respool | Add-Member -Force ComputerName, InstanceName, SqlInstance from the governor's notes, then Select-DefaultView.
    private void EmitPool(object pool, ResourceGovernor resourcegov)
    {
        WriteObject(DecoratePool(pool, resourcegov));
    }
}
