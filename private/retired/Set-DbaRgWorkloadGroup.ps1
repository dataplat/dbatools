function Set-DbaRgWorkloadGroup {
    <#
    .SYNOPSIS
        Modifies Resource Governor workload group settings to control query resource consumption and limits.

    .DESCRIPTION
        Modifies configuration settings for Resource Governor workload groups, which control how SQL Server allocates CPU, memory, and parallelism resources to different categories of queries and connections.
        Use this function to adjust resource limits for specific workload groups when you need to prioritize critical applications, limit resource-hungry queries, or enforce service level agreements through resource allocation policies.
        Changes automatically trigger a Resource Governor reconfiguration unless skipped, and plan-affecting settings only apply to new query plans after clearing the procedure cache.
        Supports both internal resource pools (standard workloads) and external resource pools (R/Python integration scenarios).

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Credential object used to connect to the Windows server as a different user

    .PARAMETER WorkloadGroup
        Name of the specific workload group to modify within the resource pool.
        Use this to target individual workload groups when you need to adjust resource limits for specific application categories or user groups.

    .PARAMETER ResourcePool
        Name of the resource pool that contains the workload group to be modified.
        Required when specifying WorkloadGroup by name rather than piping from Get-DbaRgWorkloadGroup.

    .PARAMETER ResourcePoolType
        Specifies whether to target Internal resource pools (standard SQL workloads) or External resource pools (R/Python integration scenarios).
        Choose Internal for typical database workloads, or External when managing Machine Learning Services resource allocation.

    .PARAMETER Importance
        Sets the relative priority level for requests within this workload group compared to other groups in the same resource pool.
        Use HIGH for critical business applications, MEDIUM for standard workloads, or LOW for background processes that can tolerate delays.

    .PARAMETER RequestMaximumMemoryGrantPercentage
        Sets the maximum percentage of the resource pool's memory that any single query can request for operations like sorting and hashing.
        Values range from 1-100 percent. Use lower values to prevent single queries from monopolizing memory resources.

    .PARAMETER RequestMaximumCpuTimeInSeconds
        Defines the maximum CPU time in seconds that any single request can consume before being terminated.
        Set this to prevent runaway queries from consuming excessive CPU resources. Use 0 for unlimited CPU time.

    .PARAMETER RequestMemoryGrantTimeoutInSeconds
        Sets how long queries can wait for memory grants before timing out with insufficient memory errors.
        Increase this for environments with heavy memory contention, or decrease to fail fast when memory is unavailable.

    .PARAMETER MaximumDegreeOfParallelism
        Controls the maximum number of parallel processors that queries in this workload group can use.
        Override the server-level MAXDOP setting for specific workload groups to optimize resource allocation based on workload characteristics.

    .PARAMETER GroupMaximumRequests
        Limits the total number of concurrent requests that can execute simultaneously within this workload group.
        Use this to prevent resource pool saturation by limiting how many queries from this group can run at once.

    .PARAMETER SkipReconfigure
        Prevents automatic Resource Governor reconfiguration after making workload group changes.
        Use this when making multiple configuration changes and you want to reconfigure manually once at the end to minimize disruption.

    .PARAMETER InputObject
        Accepts workload group objects piped from Get-DbaRgWorkloadGroup for bulk configuration operations.
        Allows you to modify multiple workload groups across different instances in a single pipeline operation.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: ResourcePool, ResourceGovernor
        Author: John McCall (@lowlydba), lowlydba.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Set-DbaRgWorkloadGroup

    .OUTPUTS
        Microsoft.SqlServer.Management.Smo.WorkloadGroup

        Returns the modified WorkloadGroup object(s) after configuration changes are applied. One object is returned per workload group that was modified, containing the updated workload group properties and resource constraints.

        The output is obtained by retrieving the updated workload group from the Resource Governor configuration after the Alter() operation completes, ensuring that the returned object reflects all applied changes.

        Properties available on the returned WorkloadGroup objects include:
        - Name: Name of the workload group
        - Importance: Relative priority level (LOW, MEDIUM, or HIGH)
        - RequestMaximumMemoryGrantPercentage: Maximum memory percentage per query request
        - RequestMaximumCpuTimeInSeconds: Maximum CPU time per request
        - RequestMemoryGrantTimeoutInSeconds: Memory grant timeout setting
        - MaximumDegreeOfParallelism: Maximum parallel processors for queries
        - GroupMaximumRequests: Maximum concurrent requests limit
        - Parent: Reference to the parent ResourcePool or ExternalResourcePool object

    .EXAMPLE
        PS C:\> Set-DbaRgWorkloadGroup -SqlInstance sql2016 -WorkloadGroup "groupAdmin" -ResourcePool "poolAdmin"

        Configures a workload group named "groupAdmin" in the resource pool "poolAdmin" for the instance sql2016.

    .EXAMPLE
        PS C:\> Get-DbaRgWorkloadGroup | Where-Object Name -eq "groupSuperUsers" | Set-DbaRgWorkloadGroup -GroupMaximumRequests 2

        Configures a workload group named "groupSuperUsers" by setting the maximum number of group requests to 2 for the instance sql2016.
    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = "Default", ConfirmImpact = "Low")]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$WorkloadGroup,
        [string]$ResourcePool,
        [ValidateSet("Internal", "External")]
        [string]$ResourcePoolType,
        [ValidateSet("LOW", "MEDIUM", "HIGH")]
        [string]$Importance,
        [ValidateRange(1, 100)]
        [int]$RequestMaximumMemoryGrantPercentage,
        [ValidateRange(0, [int]::MaxValue)]
        [int]$RequestMaximumCpuTimeInSeconds,
        [ValidateRange(0, [int]::MaxValue)]
        [int]$RequestMemoryGrantTimeoutInSeconds,
        [ValidateRange(0, 64)]
        [int]$MaximumDegreeOfParallelism,
        [ValidateRange(0, [int]::MaxValue)]
        [int]$GroupMaximumRequests,
        [switch]$SkipReconfigure,
        [Parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.WorkloadGroup[]]$InputObject,
        [switch]$EnableException
    )

    process {
        if (-not $InputObject -and -not $WorkloadGroup) {
            Stop-Function -Message "You must pipe in a workload group or specify a ResourcePool."
            return
        }
        if (-not $InputObject -and -not $SqlInstance) {
            Stop-Function -Message "You must pipe in a workload group or specify a SqlInstance."
            return
        }

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
            switch ($ResourcePoolType) {
                'Internal' { $resPools = $server.ResourceGovernor.ResourcePools }
                'External' { $resPools = $server.ResourceGovernor.ExternalResourcePools }
            }
            $resPool = $resPools | Where-Object Name -eq $ResourcePool
            $InputObject += $resPool.WorkloadGroups | Where-Object Name -in $WorkloadGroup
        }

        foreach ($wklGroup in $InputObject) {
            $resPool = $wklGroup.Parent
            switch ($resPool.GetType().Name) {
                'ResourcePool' { $resPoolType = "Internal" }
                'ExternalResourcePool' { $resPoolType = "External" }
            }
            $server = $resPool.Parent.Parent
            if ($PSBoundParameters.Keys -contains 'Importance') {
                $wklGroup.Importance = $Importance
            }
            if ($PSBoundParameters.Keys -contains 'RequestMaximumMemoryGrantPercentage') {
                $wklGroup.RequestMaximumMemoryGrantPercentage = $RequestMaximumMemoryGrantPercentage
            }
            if ($PSBoundParameters.Keys -contains 'RequestMaximumCpuTimeInSeconds') {
                $wklGroup.RequestMaximumCpuTimeInSeconds = $RequestMaximumCpuTimeInSeconds
            }
            if ($PSBoundParameters.Keys -contains 'RequestMemoryGrantTimeoutInSeconds') {
                $wklGroup.RequestMemoryGrantTimeoutInSeconds = $RequestMemoryGrantTimeoutInSeconds
            }
            if ($PSBoundParameters.Keys -contains 'MaximumDegreeOfParallelism') {
                $wklGroup.MaximumDegreeOfParallelism = $MaximumDegreeOfParallelism
            }
            if ($PSBoundParameters.Keys -contains 'GroupMaximumRequests') {
                $wklGroup.GroupMaximumRequests = $GroupMaximumRequests
            }

            #Execute
            try {
                if ($PSCmdlet.ShouldProcess($server, "Altering workload group $wklGroup")) {
                    $wklGroup.Alter()
                }
            } catch {
                Stop-Function -Message "Failure setting the workload group $wklGroup." -ErrorRecord $_ -Target $wklGroup -Continue
            }

            #Reconfigure Resource Governor
            try {
                if ($SkipReconfigure) {
                    Write-Message -Level Warning -Message "Workload group changes will not take effect in Resource Governor until it is reconfigured."
                } elseif ($PSCmdlet.ShouldProcess($server, "Reconfiguring the Resource Governor")) {
                    $server.ResourceGovernor.Alter()
                }
            } catch {
                Stop-Function -Message "Failure reconfiguring the Resource Governor." -ErrorRecord $_ -Target $server.ResourceGovernor -Continue
            }
            Get-DbaRgResourcePool -SqlInstance $server -Type $resPoolType | Where-Object Name -eq $resPool.Name | Get-DbaRgWorkloadGroup | Where-Object Name -eq $wklGroup.Name
        }
    }
}