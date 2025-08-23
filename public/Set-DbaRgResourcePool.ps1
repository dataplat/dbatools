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
        Specifies the name of the existing resource pool to modify.
        Use this to target specific pools like 'poolAdmin' or 'poolDeveloper' when you need to adjust their resource limits.

    .PARAMETER Type
        Specifies whether to modify Internal or External resource pools.
        Internal pools control SQL Server queries and connections, while External pools manage R Services, Python, or other external processes.
        Defaults to Internal if not specified.

    .PARAMETER MinimumCpuPercentage
        Sets the guaranteed minimum CPU percentage (0-100) that this pool will always receive during CPU contention.
        Use this to ensure critical workloads get sufficient CPU even when the server is busy.
        For example, set to 20 to guarantee a pool always gets at least 20% of available CPU.

    .PARAMETER MaximumCpuPercentage
        Sets the maximum CPU percentage (1-100) that this pool can consume during CPU contention.
        Use this to prevent runaway queries from monopolizing CPU resources.
        For example, set to 30 to limit a development pool to 30% of available CPU.

    .PARAMETER CapCpuPercentage
        Sets an absolute hard cap (1-100) on CPU usage that cannot be exceeded even when CPU is available.
        Unlike MaximumCpuPercentage, this limit applies regardless of server load or contention.
        Only available on SQL Server 2012 and later. Use this for strict resource isolation requirements.

    .PARAMETER MinimumMemoryPercentage
        Sets the minimum memory percentage (0-100) that is reserved exclusively for this pool and cannot be shared.
        Use this to guarantee memory for critical workloads that must have dedicated memory allocation.
        For example, set to 15 to ensure a production pool always has at least 15% of server memory reserved.

    .PARAMETER MaximumMemoryPercentage
        Sets the maximum memory percentage (1-100) that this pool can consume from total server memory.
        Use this to prevent memory-intensive workloads from consuming all available memory.
        Defaults to 100, meaning no memory restrictions. Set lower values like 50 to limit pool memory usage.

    .PARAMETER MinimumIOPSPerVolume
        Sets the minimum guaranteed IOPS per disk volume that this pool will receive during I/O contention.
        Use this to ensure critical workloads get sufficient disk I/O performance even when storage is busy.
        For example, set to 1000 to guarantee at least 1000 IOPS per volume for a production pool.

    .PARAMETER MaximumIOPSPerVolume
        Sets the maximum IOPS per disk volume that this pool can consume during I/O operations.
        Use this to prevent I/O-intensive workloads from overwhelming disk subsystems and affecting other pools.
        For example, set to 5000 to limit a reporting pool to 5000 IOPS per volume.

    .PARAMETER MaximumProcesses
        Sets the maximum number of external processes allowed in this external resource pool.
        Only applies to External pool types used for R Services, Python, or other external runtime processes.
        Set to 0 for unlimited processes (limited only by server resources), or specify a number like 10 to restrict concurrent external processes.

    .PARAMETER SkipReconfigure
        Prevents automatic reconfiguration of the Resource Governor after making pool changes.
        Use this when making multiple pool modifications and you want to reconfigure manually later.
        Without reconfiguration, your pool changes won't take effect until you manually reconfigure the Resource Governor.

    .PARAMETER InputObject
        Accepts resource pool objects piped from Get-DbaRgResourcePool for bulk modifications.
        Use this to modify multiple pools at once by piping them from Get-DbaRgResourcePool.
        Eliminates the need to specify SqlInstance and ResourcePool parameters when working with existing pool objects.

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