function Remove-DbaRgResourcePool {
    <#
    .SYNOPSIS
        Removes internal or external resource pools from SQL Server Resource Governor configuration

    .DESCRIPTION
        Removes user-defined resource pools from SQL Server's Resource Governor, freeing up the allocated memory, CPU, and IO resources for redistribution to other workloads. This is typically done when cleaning up unused resource pools, consolidating workload management, or reconfiguring resource allocation strategies.

        Resource pools define the physical resource boundaries (memory, CPU, IO) that can be assigned to different database workloads through workload groups. Removing unused pools helps maintain a clean Resource Governor configuration and prevents resource fragmentation.

        The function automatically reconfigures Resource Governor after pool removal to ensure changes take effect immediately, unless you specify -SkipReconfigure for batch operations.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Credential object used to connect to the Windows server as a different user

    .PARAMETER ResourcePool
        Name of the resource pool to be created.

    .PARAMETER Type
        Internal or External.

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
        https://dbatools.io/Remove-DbaRgResourcePool

    .EXAMPLE
        PS C:\> Remove-DbaRgResourcePool -SqlInstance sql2016 -ResourcePool "poolAdmin" -Type Internal

        Removes an internal resource pool named "poolAdmin" for the instance sql2016.

    .EXAMPLE
        PS C:\> Get-DbaRgResourcePool -SqlInstance sql2016 -Type "Internal" | Where-Object { $_.IsSystemObject -eq $false } | Remove-DbaRgResourcePool

        Removes all user internal resource pools for the instance sql2016 by piping output from Get-DbaRgResourcePool.
    #>

    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = "Default", ConfirmImpact = "Low")]
    param (
        [parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [DbaInstanceParameter[]]$SqlInstance,
        [Parameter(ValueFromPipelineByPropertyName)]
        [PSCredential]$SqlCredential,
        [string[]]$ResourcePool,
        [ValidateSet("Internal", "External")]
        [string]$Type = "Internal",
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
            try {
                $server = $resPool.Parent.Parent
                if ($Pscmdlet.ShouldProcess($resPool, "Dropping existing resource pool")) {
                    try {
                        $resPool.Drop()
                    } catch {
                        Stop-Function -Message "Could not remove existing resource pool $resPool on $server." -Target $resPool -Continue
                    }
                }

                # Reconfigure Resource Governor
                if ($SkipReconfigure) {
                    Write-Message -Level Warning -Message "Resource pool changes will not take effect in Resource Governor until it is reconfigured."
                } elseif ($PSCmdlet.ShouldProcess($server, "Reconfiguring the Resource Governor")) {
                    $server.ResourceGovernor.Alter()
                }
            } catch {
                Stop-Function -Message "Failure" -ErrorRecord $_ -Target $resPool -Continue
            }
        }
    }
}