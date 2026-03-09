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
        Specifies the name of the resource pool to create. Pool names must be unique within the Resource Governor configuration.
        Use descriptive names that indicate the workload type, like 'ReportingPool' or 'BatchProcessingPool' for easier management.

    .PARAMETER Type
        Specifies whether to create an Internal pool for SQL Server workloads or External pool for external processes like R Services.
        Internal pools control database workloads, while External pools manage machine learning and external script execution resources.

    .PARAMETER MinimumCpuPercentage
        Sets the guaranteed minimum CPU percentage reserved for this pool during CPU contention. Ranges from 0-100, defaults to 0.
        Use this to ensure critical workloads always get their required CPU resources, even when the server is under heavy load.

    .PARAMETER MaximumCpuPercentage
        Sets the maximum CPU percentage this pool can consume during CPU contention. Ranges from 1-100, defaults to 100.
        Use this to prevent runaway queries or resource-intensive workloads from monopolizing server CPU resources.

    .PARAMETER CapCpuPercentage
        Creates an absolute hard limit on CPU usage that cannot be exceeded, regardless of available CPU capacity. Ranges from 1-100, defaults to 100.
        Unlike MaximumCpuPercentage, this enforces the limit even when CPU resources are idle. Requires SQL Server 2012 or later.

    .PARAMETER MinimumMemoryPercentage
        Reserves a minimum percentage of server memory exclusively for this pool that cannot be shared with other pools. Ranges from 0-100, defaults to 0.
        Use this to guarantee memory allocation for critical workloads that require consistent memory availability.

    .PARAMETER MaximumMemoryPercentage
        Sets the maximum percentage of total server memory this pool can consume. Ranges from 1-100, defaults to 100.
        Use this to prevent memory-intensive operations from consuming all available server memory and affecting other workloads.

    .PARAMETER MinimumIOPSPerVolume
        Reserves a minimum number of IOPS per disk volume exclusively for this pool. Defaults to 0 (unlimited).
        Use this to guarantee disk I/O performance for workloads that require consistent data access speeds, such as OLTP systems.

    .PARAMETER MaximumIOPSPerVolume
        Limits the maximum IOPS per disk volume that this pool can consume. Defaults to 0 (unlimited).
        Use this to prevent I/O-intensive workloads like batch processing or reporting from saturating disk subsystems.

    .PARAMETER MaximumProcesses
        Sets the maximum number of external processes allowed to run concurrently in this External pool. Specify 0 for unlimited.
        Use this to control how many R or Python scripts can execute simultaneously, preventing external processes from overwhelming the server.

    .PARAMETER SkipReconfigure
        Skips the automatic Resource Governor reconfiguration that makes the new pool active immediately after creation.
        Use this when creating multiple pools in succession to avoid repeated reconfigurations, then manually reconfigure once at the end.

    .PARAMETER Force
        Automatically drops and recreates the resource pool if it already exists with the same name.
        Use this when you need to update an existing pool's configuration or ensure a clean pool creation.

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

    .OUTPUTS
        Microsoft.SqlServer.Management.Smo.ResourcePool (for Internal pools)
        Microsoft.SqlServer.Management.Smo.ExternalResourcePool (for External pools)

        Returns one resource pool object per pool created on the specified instance(s).

        Default display properties (via Select-DefaultView):
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - Id: The unique identifier for the resource pool
        - Name: The name of the resource pool
        - CapCpuPercentage: Absolute maximum CPU percentage limit (1-100)
        - IsSystemObject: Boolean indicating if the pool is a system-defined pool
        - MaximumCpuPercentage: Maximum CPU percentage during contention (1-100)
        - MaximumIopsPerVolume: Maximum IOPS per disk volume (0 = unlimited)
        - MaximumMemoryPercentage: Maximum memory percentage (1-100)
        - MinimumCpuPercentage: Guaranteed minimum CPU percentage (0-100)
        - MinimumIopsPerVolume: Guaranteed minimum IOPS per disk volume (0 = unlimited)
        - MinimumMemoryPercentage: Guaranteed minimum memory percentage (0-100)
        - WorkloadGroups: Collection of workload groups associated with this pool

        All properties from the base SMO ResourcePool or ExternalResourcePool objects are accessible using Select-Object *.

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