function Set-DbaAvailabilityGroup {
    <#
    .SYNOPSIS
        Sets availability group properties on a SQL Server instance.

    .DESCRIPTION
        Sets availability group properties on a SQL Server instance.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. Server version must be SQL Server version 2012 or higher.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER AvailabilityGroup
        Only set specific availability group properties.

    .PARAMETER AllAvailabilityGroups
        Set properties for all availability group on an instance.

    .PARAMETER DtcSupportEnabled
        Enables DtcSupport.

    .PARAMETER ClusterType
        Cluster type of the Availability Group. Only supported in SQL Server 2017 and above.
        Options include: External, Wsfc or None.

    .PARAMETER AutomatedBackupPreference
        Specifies how replicas in the primary role are treated in the evaluation to pick the desired replica to perform a backup.

    .PARAMETER FailureConditionLevel
        Specifies the different conditions that can trigger an automatic failover in Availability Group.

    .PARAMETER HealthCheckTimeout
        This setting used to specify the length of time, in milliseconds, that the SQL Server resource DLL should wait for information returned by the sp_server_diagnostics stored procedure before reporting the Always On Failover Cluster Instance (FCI) as unresponsive.

        Changes that are made to the timeout settings are effective immediately and do not require a restart of the SQL Server resource.

        Defaults is 30000 (30 seconds).

    .PARAMETER BasicAvailabilityGroup
        Indicates whether the availability group is basic. Basic availability groups like pumpkin spice and uggs.

        https://docs.microsoft.com/en-us/sql/database-engine/availability-groups/windows/basic-availability-groups-always-on-availability-groups

    .PARAMETER DatabaseHealthTrigger
        Indicates whether the availability group triggers the database health.

    .PARAMETER IsDistributedAvailabilityGroup
        Indicates whether the availability group is distributed.

    .PARAMETER InputObject
        Enables piping from Get-DbaAvailabilityGroup.

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
        https://dbatools.io/Set-DbaAvailabilityGroup

    .EXAMPLE
        PS C:\> Get-DbaAvailabilityGroup -SqlInstance sql2016 | Set-DbaAvailabilityGroup -DtcSupportEnabled

        Enables DTC for all availability groups on sql2016

    .EXAMPLE
        PS C:\> Get-DbaAvailabilityGroup -SqlInstance sql2016 -AvailabilityGroup AG1 | Set-DbaAvailabilityGroup -DtcSupportEnabled:$false

        Disables DTC support for the availability group AG1

    .EXAMPLE
        PS C:\> Set-DbaAvailabilityGroup -SqlInstance sql2016 -AvailabilityGroup AG1 -DtcSupportEnabled:$false

        Disables DTC support for the availability group AG1
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$AvailabilityGroup,
        [switch]$AllAvailabilityGroups,
        [switch]$DtcSupportEnabled,
        [ValidateSet('External', 'Wsfc', 'None')]
        [string]$ClusterType,
        [ValidateSet('None', 'Primary', 'Secondary', 'SecondaryOnly')]
        [string]$AutomatedBackupPreference,
        [ValidateSet('OnAnyQualifiedFailureCondition', 'OnCriticalServerErrors', 'OnModerateServerErrors', 'OnServerDown', 'OnServerUnresponsive')]
        [string]$FailureConditionLevel,
        [int]$HealthCheckTimeout,
        [switch]$BasicAvailabilityGroup,
        [switch]$DatabaseHealthTrigger,
        [switch]$IsDistributedAvailabilityGroup,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.AvailabilityGroup[]]$InputObject,
        [switch]$EnableException
    )
    process {
        if ((Test-Bound -ParameterName SqlInstance) -and (Test-Bound -Not -ParameterName AvailabilityGroup, AllAvailabilityGroups)) {
            Stop-Function -Message "You must specify AllAvailabilityGroups groups or AvailabilityGroups when using the SqlInstance parameter."
            return
        }
        if ($SqlInstance) {
            $InputObject += Get-DbaAvailabilityGroup -SqlInstance $SqlInstance -SqlCredential $SqlCredential -AvailabilityGroup $AvailabilityGroup
        }
        $props = "Name", "AutomatedBackupPreference", "BasicAvailabilityGroup", "ClusterType", "DatabaseHealthTrigger", "DtcSupportEnabled", "FailureConditionLevel", "HealthCheckTimeout", "IsDistributedAvailabilityGroup"

        foreach ($ag in $InputObject) {
            try {
                if ($Pscmdlet.ShouldProcess($ag.Parent.Name, "Seting properties on $ag")) {
                    foreach ($prop in $props) {
                        if (Test-Bound -ParameterName $prop) {
                            $ag.$prop = (Get-Variable -Name $prop -ValueOnly)
                        }
                    }
                    $ag.Alter()
                    $ag
                }
            } catch {
                Stop-Function -Message "Failure" -ErrorRecord $_ -Continue
            }
        }
    }
}