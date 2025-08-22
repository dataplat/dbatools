function New-DbaRgResourcePool {
    <#
    .SYNOPSIS
        Creates a Resource Governor resource pool to control CPU, memory, and I/O allocation for SQL Server workloads.

    .DESCRIPTION
        Creates a new Resource Governor resource pool that defines specific limits for CPU, memory, and I/O resources on a SQL Server instance.
        Resource pools let you isolate different workloads by setting minimum and maximum thresholds for system resources, preventing one application from consuming all server resources.
        Supports both Internal pools (for SQL Server workloads) and External pools (for external processes like R Services).
        The Resource Governor is automatically reconfigured after pool creation unless you specify otherwise.

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

    .PARAMETER Force
        If the resource pool already exists, drop and re-create it.

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
        https://dbatools.io/New-DbaRgResourcePool

    .EXAMPLE
        PS C:\> New-DbaRgResourcePool -SqlInstance sql2016 -ResourcePool "poolAdmin"

        Creates a new resource pool named "poolAdmin" for the instance sql2016.

    .EXAMPLE
        PS C:\> New-DbaRgResourcePool -SqlInstance sql2012\dev1 -ResourcePool "poolDeveloper" -SkipReconfigure

        Creates a new resource pool named "poolDeveloper" for the instance dev1 on sq2012.
        Reconfiguration is skipped and the Resource Governor will not be able to use the new resource pool
        until it is reconfigured.
    #>

    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = "Default", ConfirmImpact = "Low")]
    param (
        [parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$ResourcePool,
        [ValidateSet("Internal", "External")]
        [string]$Type = "Internal",
        [Parameter(ParameterSetName = "Internal")]
        [ValidateRange(0, 100)]
        [int]$MinimumCpuPercentage = 0,
        [ValidateRange(1, 100)]
        [int]$MaximumCpuPercentage = 100,
        [Parameter(ParameterSetName = "Internal")]
        [ValidateRange(1, 100)]
        [int]$CapCpuPercentage = 100,
        [Parameter(ParameterSetName = "Internal")]
        [ValidateRange(0, 100)]
        [int]$MinimumMemoryPercentage = 0,
        [ValidateRange(1, 100)]
        [int]$MaximumMemoryPercentage = 100,
        [Parameter(ParameterSetName = "Internal")]
        [ValidateRange(0, 2147483647)]
        [int]$MinimumIOPSPerVolume = 0,
        [Parameter(ParameterSetName = "Internal")]
        [ValidateRange(0, 2147483647)]
        [int]$MaximumIOPSPerVolume = 0,
        [Parameter(ParameterSetName = "External")]
        [int]$MaximumProcesses,
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

            foreach ($resPool in $ResourcePool) {
                $existingResourcePool = Get-DbaRgResourcePool -SqlInstance $server -Type $Type | Where-Object Name -eq $resPool
                if ($null -ne $existingResourcePool) {
                    if ($Force) {
                        if ($Pscmdlet.ShouldProcess($existingResourcePool, "Dropping existing resource pool '$resPool' because -Force was used")) {
                            try {
                                $existingResourcePool.Drop()
                            } catch {
                                Stop-Function -Message "Could not remove existing resource pool '$resPool' on $instance, skipping." -Target $existingResourcePool -Continue
                            }
                        }
                    } else {
                        Stop-Function -Message "Resource Pool '$resPool' already exists." -Category ResourceExists -Target $existingResourcePool -Continue
                        return
                    }
                }

                #Create resource pool
                if ($PSCmdlet.ShouldProcess($instance, "Creating resource pool '$resPool'")) {
                    try {
                        if ($Type -eq "External") {
                            $splatSetDbaRgResourcePool = @{
                                SqlInstance             = $server
                                ResourcePool            = $resPool
                                Type                    = $Type
                                MaximumCpuPercentage    = $MaximumCpuPercentage
                                MaximumMemoryPercentage = $MaximumMemoryPercentage
                                MaximumProcesses        = $MaximumProcesses
                                SkipReconfigure         = $SkipReconfigure
                            }
                            $newResourcePool = New-Object Microsoft.SqlServer.Management.Smo.ExternalResourcePool($server.ResourceGovernor, $resPool)
                            $newResourcePool.Create()
                        } elseif ($Type -eq "Internal") {
                            $splatSetDbaRgResourcePool = @{
                                SqlInstance             = $server
                                ResourcePool            = $resPool
                                Type                    = $Type
                                MinimumCpuPercentage    = $MinimumCpuPercentage
                                MaximumCpuPercentage    = $MaximumCpuPercentage
                                CapCpuPercentage        = $CapCpuPercentage
                                MinimumMemoryPercentage = $MinimumMemoryPercentage
                                MaximumMemoryPercentage = $MaximumMemoryPercentage
                                MinimumIOPSPerVolume    = $MinimumIOPSPerVolume
                                MaximumIOPSPerVolume    = $MaximumIOPSPerVolume
                                SkipReconfigure         = $SkipReconfigure
                            }
                            $newResourcePool = New-Object Microsoft.SqlServer.Management.Smo.ResourcePool($server.ResourceGovernor, $resPool)
                            $newResourcePool.Create()
                        }

                        #Reconfigure Resource Governor
                        if ($SkipReconfigure) {
                            Write-Message -Level Warning -Message "Not reconfiguring the Resource Governor after creating a new pool may create problems."
                        } elseif ($PSCmdlet.ShouldProcess($instance, "Reconfiguring the Resource Governor")) {
                            $server.ResourceGovernor.Alter()
                        }

                        $null = Set-DbaRgResourcePool @splatSetDbaRgResourcePool
                    } catch {
                        Stop-Function -Message "Failure" -ErrorRecord $_ -Target $newResourcePool -Continue
                    }
                }
                Get-DbaRgResourcePool -SqlInstance $server -Type $Type | Where-Object Name -eq $resPool
            }
        }
    }
}