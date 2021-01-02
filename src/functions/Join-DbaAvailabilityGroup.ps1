function Join-DbaAvailabilityGroup {
    <#
    .SYNOPSIS
        Joins a secondary replica to an availability group on a SQL Server instance.

    .DESCRIPTION
        Joins a secondary replica to an availability group on a SQL Server instance.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. Server version must be SQL Server version 2012 or higher.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER AvailabilityGroup
        The availability group to join.

    .PARAMETER ClusterType
        Cluster type of the Availability Group. Only supported in SQL Server 2017 and above.
        Options include: External, Wsfc or None.

    .PARAMETER InputObject
        Enables piped input from Get-DbaAvailabilityGroup.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: AvailabilityGroup, HA, AG
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Join-DbaAvailabilityGroup

    .EXAMPLE
        PS C:\> Get-DbaAvailabilityGroup -SqlInstance sql01 -AvailabilityGroup SharePoint | Join-DbaAvailabilityGroup -SqlInstance sql02

        Joins sql02 to the SharePoint availability group on sql01

    .EXAMPLE
        PS C:\> $ag = Get-DbaAvailabilityGroup -SqlInstance sql01 -AvailabilityGroup SharePoint
        PS C:\> Join-DbaAvailabilityGroup -SqlInstance sql02 -InputObject $ag

        Joins sql02 to the SharePoint availability group on sql01

    .EXAMPLE
        PS C:\> Get-DbaAvailabilityGroup -SqlInstance sql01 -AvailabilityGroup SharePoint | Join-DbaAvailabilityGroup -SqlInstance sql02 -WhatIf

        Shows what would happen if the command were to run. No actions are actually performed.

    .EXAMPLE
        PS C:\> Get-DbaAvailabilityGroup -SqlInstance sql01 -AvailabilityGroup SharePoint | Join-DbaAvailabilityGroup -SqlInstance sql02 -Confirm

        Prompts for confirmation then joins sql02 to the SharePoint availability group on sql01.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$AvailabilityGroup,
        [ValidateSet('External', 'Wsfc', 'None')]
        [string]$ClusterType,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.AvailabilityGroup[]]$InputObject,
        [switch]$EnableException
    )
    process {
        if (Test-Bound -Not SqlInstance, InputObject) {
            Stop-Function -Message "You must supply either -SqlInstance or an Input Object"
            return
        }

        if ($InputObject) {
            $AvailabilityGroup += $InputObject.Name
            if (-not $ClusterType) {
                $tempclustertype = ($InputObject | Select-Object -First 1).ClusterType
                if ($tempclustertype) {
                    $ClusterType = $tempclustertype
                }
            }
        }

        if (-not $AvailabilityGroup) {
            Stop-Function -Message "No availability group to add"
            return
        }

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            foreach ($ag in $AvailabilityGroup) {
                if ($Pscmdlet.ShouldProcess($server.Name, "Joining $ag")) {
                    try {
                        if ($ClusterType -and $server.VersionMajor -ge 14) {
                            $server.Query("ALTER AVAILABILITY GROUP [$ag] JOIN WITH (CLUSTER_TYPE = $ClusterType)")
                        } else {
                            $server.JoinAvailabilityGroup($ag)
                        }
                    } catch {
                        Stop-Function -Message "Failure" -ErrorRecord $_ -Continue
                    }
                }
            }
        }
    }
}