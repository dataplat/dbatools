function Set-DbaRgWorkloadGroup {
    <#
    .SYNOPSIS
        Sets a workload group for use by the Resource Governor on the specified SQL Server.

    .DESCRIPTION
        Sets a workload group for use by the Resource Governor on the specified SQL Server.
        A workload group represents a subset of resources of an instance of the Database Engine.

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
        Author: John McCall (@lowlydba), https://www.lowlydba.com/

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
        [parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [DbaInstanceParameter[]]$SqlInstance,
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
        Write-Message -Level Warning -Message "When changing a plan affecting setting, the new setting will only take effect in previously cached plans after executing 'DBCC FREEPROCCACHE (pool_name);'"

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
            if ($ResourcePoolType -eq "Internal") {
                $resPools = $server.ResourceGovernor.ResourcePools
            } elseif ($ResourcePoolType -eq "External") {
                $resPools = $server.ResourceGovernor.ExternalResourcePools
            }
            $resPool = $resPools | Where-Object Name -eq $ResourcePool
            $InputObject += $resPool.WorkloadGroups | Where-Object Name -in $WorkloadGroup
        }

        foreach ($wklGroup in $InputObject) {
            $resPool = $wklGroup.Parent
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
            $wklGroup | Add-Member -Force -MemberType NoteProperty -Name ComputerName -Value $server.ComputerName
            $wklGroup | Add-Member -Force -MemberType NoteProperty -Name InstanceName -Value $server.ServiceName
            $wklGroup | Add-Member -Force -MemberType NoteProperty -Name SqlInstance -Value $server.DomainInstanceName
            $wklGroup | Select-DefaultView -Property ComputerName, InstanceName, SqlInstance, Id, Name, ExternalResourcePoolName, GroupMaximumRequests, Importance, IsSystemObject, MaximumDegreeOfParallelism, RequestMaximumCpuTimeInSeconds, RequestMaximumMemoryGrantPercentage, RequestMemoryGrantTimeoutInSeconds
        }

    }
}