function New-DbaRgWorkloadGroup {
    <#
    .SYNOPSIS
        Creates a Resource Governor workload group within a specified resource pool to control SQL Server resource allocation.

    .DESCRIPTION
        Creates a Resource Governor workload group within a specified resource pool, allowing you to define specific resource limits and priorities for different types of SQL Server workloads. Workload groups act as containers that classify incoming requests and apply resource policies like CPU time limits, memory grant percentages, and maximum degree of parallelism.

        This is essential for DBAs managing multi-tenant environments, mixed workloads, or systems where you need to prevent resource-intensive queries from impacting critical applications. You can create separate workload groups for reporting queries, ETL processes, application traffic, or administrative tasks, each with tailored resource constraints.

        The function supports both internal and external resource pools, handles existing workload group conflicts with optional force recreation, and automatically reconfigures Resource Governor to apply the changes immediately.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Credential object used to connect to the Windows server as a different user

    .PARAMETER WorkloadGroup
        Name of the workload group to be created.

    .PARAMETER ResourcePool
        Name of the resource pool to create the workload group in. If not provided, set to the Default Resource Pool.

    .PARAMETER ResourcePoolType
        Internal (default) or External

    .PARAMETER Importance
        Specifies the relative importance of a request in the workload group. Default is MEDIUM, allowed: LOW, MEDIUM, HIGH

    .PARAMETER RequestMaximumMemoryGrantPercentage
        Specifies the maximum amount of memory that a single request can take from the pool. Default is 25%.

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

    .PARAMETER Force
        If the workload group already exists, drop and re-create it.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: WorkloadGroup, ResourceGovernor
        Author: John McCall (@lowlydba), lowlydba.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/New-DbaRgWorkloadGroup

    .EXAMPLE
        PS C:\> New-DbaRgWorkloadGroup -SqlInstance sql2016 -WorkloadGroup "groupAdmin" -ResourcePool "poolAdmin"

        Creates a workload group "groupAdmin" in the resource pool named "poolAdmin" for the instance sql2016.

    .EXAMPLE
        PS C:\> New-DbaRgWorkloadGroup -SqlInstance sql2016 -WorkloadGroup "groupAdmin" -Force

        If "groupAdmin" exists, it is dropped and re-created in the default resource pool for the instance sql2016.
    #>

    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = "Default", ConfirmImpact = "Low")]
    param (
        [parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [DbaInstanceParameter[]]$SqlInstance,
        [Parameter(ValueFromPipelineByPropertyName)]
        [PSCredential]$SqlCredential,
        [string[]]$WorkloadGroup,
        [string]$ResourcePool = "default",
        [ValidateSet("Internal", "External")]
        [string]$ResourcePoolType = "Internal",
        [ValidateSet("LOW", "MEDIUM", "HIGH")]
        [string]$Importance = "MEDIUM",
        [ValidateRange(1, 100)]
        [int]$RequestMaximumMemoryGrantPercentage = 25,
        [ValidateRange(0, [int]::MaxValue)]
        [int]$RequestMaximumCpuTimeInSeconds = 0,
        [ValidateRange(0, [int]::MaxValue)]
        [int]$RequestMemoryGrantTimeoutInSeconds = 0,
        [ValidateRange(0, 64)]
        [int]$MaximumDegreeOfParallelism = 0,
        [ValidateRange(0, [int]::MaxValue)]
        [int]$GroupMaximumRequests = 0,
        [switch]$SkipReconfigure,
        [switch]$Force,
        [switch]$EnableException
    )
    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            foreach ($wklGroup in $WorkloadGroup) {
                switch ($ResourcePoolType) {
                    'Internal' { $resPools = $server.ResourceGovernor.ResourcePools }
                    'External' { $resPools = $server.ResourceGovernor.ExternalResourcePools }
                }
                $resPool = $resPools | Where-Object Name -eq $ResourcePool
                $existingWorkloadGroup = $resPool.WorkloadGroups | Where-Object Name -eq $wklGroup
                if ($null -ne $existingWorkloadGroup) {
                    if ($Force) {
                        if ($PSCmdlet.ShouldProcess($existingWorkloadGroup, "Dropping existing workload group $wklGroup because -Force was used")) {
                            try {
                                $existingWorkloadGroup.Drop()
                            } catch {
                                Stop-Function -Message "Could not remove existing workload group $wklGroup on $instance, skipping." -Target $existingWorkloadGroup -Continue
                            }
                        }
                    } else {
                        Stop-Function -Message "Workload group $wklGroup already exists." -Category ResourceExists -ErrorRecord $_ -Target $existingWorkloadGroup -Continue
                        return
                    }
                }

                #Create workload group
                if ($PSCmdlet.ShouldProcess($instance, "Creating workload group $wklGroup")) {
                    try {
                        $newWorkloadGroup = New-Object Microsoft.SqlServer.Management.Smo.WorkloadGroup($resPool, $wklGroup)
                        $newWorkloadGroup.Importance = $Importance
                        $newWorkloadGroup.RequestMaximumMemoryGrantPercentage = $RequestMaximumMemoryGrantPercentage
                        $newWorkloadGroup.RequestMaximumCpuTimeInSeconds = $RequestMaximumCpuTimeInSeconds
                        $newWorkloadGroup.RequestMemoryGrantTimeoutInSeconds = $RequestMemoryGrantTimeoutInSeconds
                        $newWorkloadGroup.MaximumDegreeOfParallelism = $MaximumDegreeOfParallelism
                        $newWorkloadGroup.GroupMaximumRequests = $GroupMaximumRequests
                        $newWorkloadGroup.Create()

                        #Reconfigure Resource Governor
                        if ($SkipReconfigure) {
                            Write-Message -Level Warning -Message "Not reconfiguring the Resource Governor after creating a new workload group may create problems."
                        } elseif ($PSCmdlet.ShouldProcess($instance, "Reconfiguring the Resource Governor")) {
                            $server.ResourceGovernor.Alter()
                        }

                    } catch {
                        Stop-Function -Message "Failure" -ErrorRecord $_ -Target $newWorkloadGroup -Continue
                    }
                }
                Get-DbaRgResourcePool -SqlInstance $server -Type $ResourcePoolType | Where-Object Name -eq $resPool.Name | Get-DbaRgWorkloadGroup | Where-Object Name -eq $wklGroup
            }
        }
    }
}