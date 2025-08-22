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
        Name of the workload group to be configured.

    .PARAMETER ResourcePool
        Name of the resource pool to create the workload group in.

    .PARAMETER ResourcePoolType
        Internal or External

    .PARAMETER Importance
        Specifies the relative importance of a request in the workload group.

    .PARAMETER RequestMaximumMemoryGrantPercentage
        Specifies the maximum amount of memory that a single request can take from the pool.

    .PARAMETER RequestMaximumCpuTimeInSeconds
        Specifies the maximum amount of CPU time, in seconds, that a request can use.

    .PARAMETER RequestMemoryGrantTimeoutInSeconds
        Specifies the maximum time, in seconds, that a query can wait for a memory grant (work buffer memory) to become available.

    .PARAMETER MaximumDegreeOfParallelism
        Specifies the maximum degree of parallelism (MAXDOP) for parallel query execution.

    .PARAMETER GroupMaximumRequests
        Specifies the maximum number of simultaneous requests that are allowed to execute in the workload group.

    .PARAMETER SkipReconfigure
        Resource Governor requires a reconfiguriation for workload group changes to take effect.
        Use this switch to skip issuing a reconfigure for the Resource Governor.

    .PARAMETER InputObject
        Allows input to be piped from Get-DbaRgWorkloadGroup.

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