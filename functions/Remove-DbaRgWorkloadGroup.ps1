function Remove-DbaRgWorkloadGroup {
    <#
    .SYNOPSIS
        Removes a workload group from the Resource Governor on the specified SQL Server.

    .DESCRIPTION
        Removes a workload group from the Resource Governor on the specified SQL Server.
        A workload group represents a subset of the resources of an instance of the Database Engine.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Credential object used to connect to the Windows server as a different user.

    .PARAMETER WorkloadGroup
        Name of the workload group to be removed.

    .PARAMETER ResourcePool
        Name of the resource pool the workload group is in.

    .PARAMETER ResourcePoolType
        Internal or External.

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
        Tags: WorkloadGroup, ResourceGovernor
        Author: John McCall (@lowlydba), https://www.lowlydba.com/

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Remove-DbaRgWorkloadGroup

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

        foreach ($wklGroup in $InputObject) {
            try {
                $resPool = $wklGroup.Parent
                $server = $resPool.Parent.Parent
                if ($Pscmdlet.ShouldProcess($resPool, "Dropping existing workload group")) {
                    try {
                        $wklGroup.Drop()
                    } catch {
                        Stop-Function -Message "Could not remove existing workload group $wklGroup on $server." -Target $wklGroup -Continue
                    }
                }

                # Reconfigure Resource Governor
                if ($SkipReconfigure) {
                    Write-Message -Level Warning -Message "Workload group changes will not take effect in Resource Governor until it is reconfigured."
                } elseif ($PSCmdlet.ShouldProcess($server, "Reconfiguring the Resource Governor")) {
                    $server.ResourceGovernor.Alter()
                }
            } catch {
                Stop-Function -Message "Failure" -ErrorRecord $_ -Target $wklGroup -Continue
            }
        }
    }
}