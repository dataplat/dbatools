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
        Specifies the name of the workload group to create within the resource pool. Use descriptive names that reflect the workload type, like 'ReportingQueries', 'ETLProcesses', or 'AdminTasks'.
        Each workload group acts as a container for classifying requests and applying specific resource limits and priorities.

    .PARAMETER ResourcePool
        Specifies which resource pool will contain the new workload group. Defaults to 'default' if not specified.
        Use this to organize workload groups within custom resource pools that have specific CPU and memory allocations.

    .PARAMETER ResourcePoolType
        Determines whether to create the workload group in an Internal or External resource pool. Defaults to Internal.
        Use External for R/Python workloads or machine learning services; use Internal for standard SQL Server workloads like queries and stored procedures.

    .PARAMETER Importance
        Sets the relative priority for requests in this workload group when competing for CPU resources. Defaults to MEDIUM.
        Use HIGH for critical application queries, MEDIUM for normal operations, and LOW for background tasks like maintenance or reporting.

    .PARAMETER RequestMaximumMemoryGrantPercentage
        Limits how much memory any single query in this workload group can consume from the resource pool. Defaults to 25%.
        Lower this for concurrent workloads to prevent memory hogging, or increase it for data warehouse queries that need large memory grants for sorting and hashing.

    .PARAMETER RequestMaximumCpuTimeInSeconds
        Sets the maximum CPU time in seconds that any single request can consume before being terminated. Default of 0 means unlimited.
        Use this to prevent runaway queries from consuming excessive CPU, typically setting values between 300-3600 seconds depending on your workload requirements.

    .PARAMETER RequestMemoryGrantTimeoutInSeconds
        Defines how long a query will wait for memory grants before timing out. Default of 0 means unlimited wait time.
        Set this to prevent queries from waiting indefinitely during memory pressure, typically using values like 60-300 seconds for interactive workloads.

    .PARAMETER MaximumDegreeOfParallelism
        Controls the maximum number of processors that queries in this workload group can use for parallel execution. Default of 0 uses the server's MAXDOP setting.
        Lower values prevent queries from consuming too many CPU cores, while higher values can improve performance for analytical workloads on servers with many cores.

    .PARAMETER GroupMaximumRequests
        Limits the total number of concurrent requests that can execute simultaneously within this workload group. Default of 0 means unlimited.
        Use this to control concurrency for resource-intensive workloads, preventing too many expensive queries from running at once and overwhelming the system.

    .PARAMETER SkipReconfigure
        Prevents automatic reconfiguration of Resource Governor after creating the workload group. Changes won't take effect until you manually run ALTER RESOURCE GOVERNOR RECONFIGURE.
        Use this when creating multiple workload groups in a batch to avoid repeated reconfigurations, but remember to reconfigure manually afterward.

    .PARAMETER Force
        Drops and recreates the workload group if it already exists, applying new configuration settings.
        Use this when you need to modify an existing workload group's properties, as Resource Governor workload groups cannot be altered once created.

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

    .OUTPUTS
        Microsoft.SqlServer.Management.Smo.WorkloadGroup

        Returns one workload group object per workload group created within the specified resource pool(s).

        Default display properties (via Select-DefaultView):
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - Id: The unique identifier for the workload group
        - Name: The name of the workload group
        - ExternalResourcePoolName: Name of the external resource pool (for External pools only)
        - GroupMaximumRequests: Maximum number of concurrent requests allowed in this group (0 = unlimited)
        - Importance: Relative priority when competing for CPU resources (LOW, MEDIUM, or HIGH)
        - IsSystemObject: Boolean indicating if the workload group is a system-defined group
        - MaximumDegreeOfParallelism: Maximum number of processors for parallel execution (0 = server default)
        - RequestMaximumCpuTimeInSeconds: Maximum CPU time in seconds per request (0 = unlimited)
        - RequestMaximumMemoryGrantPercentage: Maximum memory grant percentage from the pool (1-100)
        - RequestMemoryGrantTimeoutInSeconds: Maximum wait time in seconds for memory grants (0 = unlimited)

        All properties from the base SMO WorkloadGroup object are accessible using Select-Object *.

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