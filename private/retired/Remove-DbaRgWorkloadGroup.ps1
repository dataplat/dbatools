function Remove-DbaRgWorkloadGroup {
    <#
    .SYNOPSIS
        Removes workload groups from SQL Server Resource Governor

    .DESCRIPTION
        Removes specified workload groups from SQL Server Resource Governor and automatically reconfigures the Resource Governor so changes take effect immediately.
        Workload groups define resource allocation policies for incoming requests, and removing them eliminates those resource controls.
        Useful for cleaning up test environments, removing deprecated resource policies, or simplifying Resource Governor configurations during performance tuning.
        Works with both internal and external resource pools, and can process multiple workload groups through pipeline input from Get-DbaRgWorkloadGroup.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Credential object used to connect to the Windows server as a different user.

    .PARAMETER WorkloadGroup
        Specifies the name of the workload group(s) to remove from Resource Governor.
        Use this when you need to eliminate specific resource allocation policies or clean up deprecated workload configurations.

    .PARAMETER ResourcePool
        Specifies the resource pool containing the workload group to be removed. Defaults to "default" pool.
        Required when workload groups exist in custom resource pools rather than the default SQL Server resource pool.

    .PARAMETER ResourcePoolType
        Specifies whether to target Internal or External resource pools. Defaults to "Internal".
        Use "External" when removing workload groups that manage external script execution resources like R or Python jobs.

    .PARAMETER SkipReconfigure
        Skips the automatic Resource Governor reconfiguration that makes workload group changes take effect immediately.
        Use this when removing multiple workload groups in sequence to avoid repeated reconfigurations, but remember to manually reconfigure afterwards.

    .PARAMETER InputObject
        Accepts workload group objects piped from Get-DbaRgWorkloadGroup for removal.
        Use this approach when you need to filter workload groups first or when processing multiple groups across different resource pools.

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
        https://dbatools.io/Remove-DbaRgWorkloadGroup

    .OUTPUTS
        PSCustomObject

        Returns one object per workload group removed, containing the following properties:
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name (service name)
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - Name: The name of the workload group that was removed
        - Status: Status of the removal operation ("Dropped" on success, or error message on failure)
        - IsRemoved: Boolean indicating whether the workload group was successfully removed ($true or $false)

    .EXAMPLE
        PS C:\> Remove-DbaRgResourcePool -SqlInstance sql2016 -WorkloadGroup "groupAdmin" -ResourcePool "poolAdmin" -ResourcePoolType Internal

        Removes a workload group named "groupAdmin" in the "poolAdmin" resource pool for the instance sql2016

    .EXAMPLE
        PS C:\> Remove-DbaRgResourcePool -SqlInstance sql2016 -WorkloadGroup "groupAdmin"

        Removes a workload group named "groupAdmin" in the default resource pool for the instance sql2016.
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
        [switch]$SkipReconfigure,
        [Parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.WorkloadGroup[]]$InputObject,
        [switch]$EnableException
    )
    process {
        if (-not $InputObject -and -not $WorkloadGroup) {
            Stop-Function -Message "You must pipe in a workload group or specify a WorkloadGroup."
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

            if ($ResourcePoolType -eq "Internal") {
                $resPools = $server.ResourceGovernor.ResourcePools
            } elseif ($ResourcePoolType -eq "External") {
                $resPools = $server.ResourceGovernor.ExternalResourcePools
            }
            $resPool = $resPools | Where-Object Name -eq $ResourcePool
            $InputObject += $resPool.WorkloadGroups | Where-Object Name -in $WorkloadGroup
        }
    }
    end {
        foreach ($wklGroup in $InputObject) {
            $server = $wklGroup.Parent.Parent.Parent
            if ($Pscmdlet.ShouldProcess($wklGroup, "Dropping workload group")) {
                $output = [PSCustomObject]@{
                    ComputerName = $server.ComputerName
                    InstanceName = $server.ServiceName
                    SqlInstance  = $server.DomainInstanceName
                    Name         = $wklGroup.Name
                    Status       = $null
                    IsRemoved    = $false
                }
                try {
                    $wklGroup.Drop()
                    $output.Status = "Dropped"
                    $output.IsRemoved = $true
                } catch {
                    Stop-Function -Message "Could not remove existing workload group $wklGroup on $server." -Target $wklGroup -Continue
                    $output.Status = (Get-ErrorMessage -Record $_)
                    $output.IsRemoved = $false
                }
            }

            # Reconfigure Resource Governor
            if ($SkipReconfigure) {
                Write-Message -Level Warning -Message "Workload group changes will not take effect in Resource Governor until it is reconfigured."
            } elseif ($PSCmdlet.ShouldProcess($server, "Reconfiguring the Resource Governor")) {
                try {
                    $server.ResourceGovernor.Alter()
                } catch {
                    Stop-Function -Message "Could not reconfigure Resource Governor on $server." -Target $server.ResourceGovernor -Continue
                }
            }
            $output
        }
    }
}