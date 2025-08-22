function Set-DbaRgResourcePool {
    <#
    .SYNOPSIS
        Modifies CPU, memory, and IOPS limits for existing SQL Server Resource Governor pools.

    .DESCRIPTION
        Modifies resource allocation settings for existing Resource Governor pools to control how much CPU, memory, and disk I/O different workloads can consume.
        This lets you adjust performance limits after analyzing workload patterns or when server capacity changes.
        Works with both internal pools (for SQL Server queries) and external pools (for R Services, Python, or other external processes).
        The Resource Governor is automatically reconfigured to apply changes immediately unless you skip reconfiguration.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Credential object used to connect to the Windows server as a different user

    .PARAMETER ResourcePool
        Name of the resource pool to be created.

    .PARAMETER Type
        Internal or External.

    .PARAMETER MinimumCpuPercentage
        Specifies the guaranteed average CPU bandwidth for all requests in the resource pool when there is CPU contention.

    .PARAMETER MaximumCpuPercentage
        Specifies the maximum average CPU bandwidth that all requests in resource pool will receive when there is CPU contention.

    .PARAMETER CapCpuPercentage
        Specifies a hard cap on the CPU bandwidth that all requests in the resource pool will receive.
        Limits the maximum CPU bandwidth level to be the same as the specified value. Only for SQL Server 2012+

    .PARAMETER MinimumMemoryPercentage
        Specifies the minimum amount of memory reserved for this resource pool that can not be shared with other resource pools.

    .PARAMETER MaximumMemoryPercentage
        Specifies the total server memory that can be used by requests in this resource pool. value is an integer with a default setting of 100.

    .PARAMETER MinimumIOPSPerVolume
        Specifies the minimum I/O operations per second (IOPS) per disk volume to reserve for the resource pool.

    .PARAMETER MaximumIOPSPerVolume
        Specifies the maximum I/O operations per second (IOPS) per disk volume to allow for the resource pool.

    .PARAMETER MaximumProcesses
        Specifies the maximum number of processes allowed for the external resource pool.
        Specify 0 to set an unlimited threshold for the pool, which is thereafter bound only by computer resources.

    .PARAMETER SkipReconfigure
        Resource Governor requires a reconfiguriation for resource pool changes to take effect.
        Use this switch to skip issuing a reconfigure for the Resource Governor.

    .PARAMETER InputObject
        Allows input to be piped from Get-DbaRgResourcePool.

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
        https://dbatools.io/Set-DbaRgResourcePool

    .EXAMPLE
        PS C:\> Set-DbaRgResourcePool-SqlInstance sql2016 -ResourcePool "poolAdmin" -MaximumCpuPercentage 5

        Configures a resource pool named "poolAdmin" for the instance sql2016 with a Maximum CPU Percent of 5.

    .EXAMPLE
        PS C:\> Set-DbaRgResourcePool-SqlInstance sql2012\dev1 -ResourcePool "poolDeveloper" -SkipReconfigure

        Configures a resource pool named "poolDeveloper" for the instance dev1 on sq2012.
        Reconfiguration is skipped and the Resource Governor will not be able to use the new resource pool
        until it is reconfigured.

    .EXAMPLE
        PS C:\> Get-DbaRgResourcePool -SqlInstance sql2016 -Type "Internal" | Where-Object { $_.IsSystemObject -eq $false } | Set-DbaRgResourcePool -MinMemoryPercent 10

        Configures all user internal resource pools to have a minimum memory percent of 10
        for the instance sql2016 by piping output from Get-DbaRgResourcePool.
    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = "Default", ConfirmImpact = "Low")]
    param (
        [parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$ResourcePool,
        [ValidateSet("Internal", "External")]
        [string]$Type = "Internal",
        [Parameter(ValueFromPipelineByPropertyName)]
        [Parameter(ParameterSetName = "Internal")]
        [ValidateRange(0, 100)]
        [int]$MinimumCpuPercentage,
        [Parameter(ValueFromPipelineByPropertyName)]
        [ValidateRange(1, 100)]
        [int]$MaximumCpuPercentage,
        [Parameter(ValueFromPipelineByPropertyName)]
        [Parameter(ParameterSetName = "Internal")]
        [ValidateRange(1, 100)]
        [int]$CapCpuPercentage,
        [Parameter(ValueFromPipelineByPropertyName)]
        [Parameter(ParameterSetName = "Internal")]
        [ValidateRange(0, 100)]
        [int]$MinimumMemoryPercentage,
        [Parameter(ValueFromPipelineByPropertyName)]
        [ValidateRange(1, 100)]
        [int]$MaximumMemoryPercentage,
        [Parameter(ValueFromPipelineByPropertyName)]
        [Parameter(ParameterSetName = "Internal")]
        [ValidateRange(0, 2147483647)]
        [int]$MinimumIOPSPerVolume,
        [Parameter(ValueFromPipelineByPropertyName)]
        [Parameter(ParameterSetName = "Internal")]
        [ValidateRange(0, 2147483647)]
        [int]$MaximumIOPSPerVolume,
        [Parameter(ParameterSetName = "External")]
        [int]$MaximumProcesses,
        [switch]$SkipReconfigure,
        [Parameter(ValueFromPipeline)]
        [object[]]$InputObject,
        [switch]$EnableException
    )

    process {
        if (-not $InputObject -and -not $ResourcePool) {
            Stop-Function -Message "You must pipe in a resource pool or specify a ResourcePool."
            return
        }
        if (-not $InputObject -and -not $SqlInstance) {
            Stop-Function -Message "You must pipe in a resource pool or specify a SqlInstance."
            return
        }

        if (($InputObject) -and ($PSBoundParameters.Keys -notcontains 'Type')) {
            if ($InputObject -is [Microsoft.SqlServer.Management.Smo.ResourcePool]) {
                $Type = "Internal"
            } elseif ($InputObject -is [Microsoft.SqlServer.Management.Smo.ExternalResourcePool]) {
                $Type = "External"
            }
        }

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
            if ($Type -eq "Internal") {
                $InputObject += $server.ResourceGovernor.ResourcePools | Where-Object Name -in $ResourcePool
            } elseif ($Type -eq "External") {
                $InputObject += $server.ResourceGovernor.ExternalResourcePools | Where-Object Name -in $ResourcePool
            }
        }

        foreach ($resPool in $InputObject) {
            $server = $resPool.Parent.Parent
            if ($Type -eq "External") {
                if ($PSBoundParameters.Keys -contains 'MaximumCpuPercentage') {
                    $resPool.MaximumCpuPercentage = $MaximumCpuPercentage
                }
                if ($PSBoundParameters.Keys -contains 'MaximumMemoryPercentage') {
                    $resPool.MaximumMemoryPercentage = $MaximumMemoryPercentage
                }
                if ($PSBoundParameters.Keys -contains 'MaximumProcesses') {
                    $resPool.MaximumProcesses = $MaximumProcesses
                }
            } elseif ($Type -eq "Internal") {
                if ($PSBoundParameters.Keys -contains 'MinimumCpuPercentage') {
                    $resPool.MinimumCpuPercentage = $MinimumCpuPercentage
                }
                if ($PSBoundParameters.Keys -contains 'MaximumCpuPercentage') {
                    $resPool.MaximumCpuPercentage = $MaximumCpuPercentage
                }
                if ($PSBoundParameters.Keys -contains 'MinimumMemoryPercentage') {
                    $resPool.MinimumMemoryPercentage = $MinimumMemoryPercentage
                }
                if ($PSBoundParameters.Keys -contains 'MaximumMemoryPercentage') {
                    $resPool.MaximumMemoryPercentage = $MaximumMemoryPercentage
                }
                if ($PSBoundParameters.Keys -contains 'MinimumIOPSPerVolume') {
                    $resPool.MinimumIopsPerVolume = $MinimumIOPSPerVolume
                }
                if ($PSBoundParameters.Keys -contains 'MaximumIOPSPerVolume') {
                    $resPool.MaximumIopsPerVolume = $MaximumIOPSPerVolume
                }
                if ($PSBoundParameters.Keys -contains 'CapCpuPercentage') {
                    if ($server.ResourceGovernor.ServerVersion.Major -ge 11) {
                        $resPool.CapCpuPercentage = $CapCpuPercentage
                    } elseif ($server.ResourceGovernor.ServerVersion.Major -lt 11) {
                        Write-Message -Level Warning -Message "SQL Server version 2012+ required to specify a CPU percentage cap."
                    }
                }
            }

            #Execute
            try {
                if ($PSCmdlet.ShouldProcess($server, "Altering resource pool $resPool")) {
                    $resPool.Alter()
                }
            } catch {
                Stop-Function -Message "Failure" -ErrorRecord $_ -Target $resPool -Continue
            }

            #Reconfigure Resource Governor
            try {
                if ($SkipReconfigure) {
                    Write-Message -Level Warning -Message "Resource pool changes will not take effect in Resource Governor until it is reconfigured."
                } elseif ($PSCmdlet.ShouldProcess($server, "Reconfiguring the Resource Governor")) {
                    $server.ResourceGovernor.Alter()
                }
            } catch {
                Stop-Function -Message "Failure" -ErrorRecord $_ -Target $server.ResourceGovernor -Continue
            }

            $respool | Add-Member -Force -MemberType NoteProperty -Name ComputerName -value $server.ComputerName
            $respool | Add-Member -Force -MemberType NoteProperty -Name InstanceName -value $server.InstanceName
            $respool | Add-Member -Force -MemberType NoteProperty -Name SqlInstance -value $server.DomainInstanceName
            $respool | Select-DefaultView -Property ComputerName, InstanceName, SqlInstance, Id, Name, CapCpuPercentage, IsSystemObject, MaximumCpuPercentage, MaximumIopsPerVolume, MaximumMemoryPercentage, MinimumCpuPercentage, MinimumIopsPerVolume, MinimumMemoryPercentage, WorkloadGroups
        }
    }
}